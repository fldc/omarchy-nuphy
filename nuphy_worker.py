#!/usr/bin/env python3
"""Single persistent NDJSON worker; event-driven theme and HID discovery."""
import ctypes
import fcntl
import json
import os
from pathlib import Path
import selectors
import struct
import sys
import time

import nuphy_backend as backend

FALLBACK_SECONDS = 60


class Watcher:
    MASK = 0x00000002 | 0x00000004 | 0x00000008 | 0x00000040 | 0x00000080 | 0x00000100 | 0x00000200 | 0x00000400 | 0x00000800

    def __init__(self):
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), 'inotify_init1 failed')
        self.kinds = {}
        self.arm()

    def arm(self):
        # Follow theme symlink replacements as well as writes to keyboard.rgb.
        paths = {backend.THEME.parent, backend.THEME.parent.resolve(),
                 backend.THEME.parent.parent, backend.THEME.parent.parent.parent}
        current = {}
        for path, kind in [(p, 'theme') for p in paths] + [(Path('/dev'), 'device')]:
            wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), self.MASK)
            if wd >= 0:
                current[wd] = kind
        for wd in self.kinds.keys() - current.keys():
            self.libc.inotify_rm_watch(self.fd, wd)
        self.kinds = current

    def drain(self):
        changed = set()
        while True:
            try:
                data = os.read(self.fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset + 16 <= len(data):
                wd, mask, _, length = struct.unpack_from('iIII', data, offset)
                name = data[offset + 16:offset + 16 + length].split(b'\0', 1)[0]
                offset += 16 + length
                kind = self.kinds.get(wd)
                if mask & 0x00004000:  # IN_Q_OVERFLOW
                    changed.update(('theme', 'device'))
                elif (kind == 'theme' and name in (b'', b'keyboard.rgb', b'theme', b'current')) or (kind == 'device' and name.startswith(b'hidraw')):
                    changed.add(kind)
                if mask & 0x00008000:  # IN_IGNORED
                    self.kinds.pop(wd, None)
        return changed

    def close(self):
        os.close(self.fd)


def serve():
    backend.STATE.mkdir(parents=True, exist_ok=True)
    with (backend.STATE / 'worker.lock').open('w') as singleton:
        try:
            fcntl.flock(singleton, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('A NuPhy worker is already running')
        worker = backend.Worker()
        worker.discover()
        selector = selectors.DefaultSelector()
        selector.register(sys.stdin, selectors.EVENT_READ, 'input')
        watcher = None
        try:
            watcher = Watcher()
            selector.register(watcher.fd, selectors.EVENT_READ, 'watch')
        except OSError:
            pass
        last_output = ''
        next_discovery = time.monotonic() + FALLBACK_SECONDS
        pending = set()
        deadline = None
        buffer = b''

        def emit(request):
            nonlocal last_output
            try:
                result = worker.execute(request)
            except (OSError, RuntimeError) as error:
                result = {'error': str(error)[:600]}
            result['requestId'] = request.get('id')
            encoded = json.dumps(result, sort_keys=True)
            if request.get('id') is not None or encoded != last_output:
                print(encoded, flush=True)
                last_output = encoded
            return result

        result = emit({'action': 'tick'})
        try:
            while True:
                now = time.monotonic()
                wake = min(next_discovery, deadline if deadline is not None else float('inf'))
                retry = result.get('retryAfter', 0) - time.time()
                if retry > 0:
                    wake = min(wake, now + retry)
                for key, _ in selector.select(max(0, wake - now)):
                    if key.data == 'watch':
                        pending.update(watcher.drain())
                        if pending and deadline is None:
                            deadline = time.monotonic() + 0.2
                    else:
                        chunk = os.read(sys.stdin.fileno(), backend.MAX_JSON)
                        if not chunk:
                            return
                        buffer += chunk
                        if len(buffer) > backend.MAX_JSON:
                            raise ValueError('Request exceeds maximum size')
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            try:
                                request = json.loads(line)
                                if not isinstance(request, dict) or request.get('action') not in ('apply', 'sync', 'status'):
                                    raise ValueError('Invalid worker request')
                                if request['action'] != 'status':
                                    # Outside state lock; fresh verification for explicit writes.
                                    worker.discover()
                                result = emit(request)
                            except (ValueError, TypeError) as error:
                                print(json.dumps({'error': str(error)[:600], 'protocolError': True}), flush=True)
                now = time.monotonic()
                due = deadline is not None and now >= deadline
                fallback = now >= next_discovery
                retry_due = result.get('retryAfter', 0) > 0 and result['retryAfter'] <= time.time()
                if due or fallback or retry_due:
                    if fallback or (due and 'device' in pending):
                        worker.discover()
                        next_discovery = now + FALLBACK_SECONDS
                        if watcher:
                            watcher.arm()
                    if due:
                        if watcher:
                            watcher.arm()
                        pending.clear()
                        deadline = None
                    result = emit({'action': 'tick'})
                    # No busy-loop when an old retry deadline is in the past.
                    if not result.get('error'):
                        result['retryAfter'] = 0
        finally:
            selector.close()
            if watcher:
                watcher.close()


if __name__ == '__main__':
    try:
        serve()
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
