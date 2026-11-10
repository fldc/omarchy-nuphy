"""Bounded subprocess output and isolated reads for local configuration/clipboard."""
import json
import os
from pathlib import Path
import selectors
import signal
import stat
import subprocess
import sys
import time


def run_command(args, *, timeout, limit=262144, stderr_limit=4096):
    """Drain both pipes with byte caps; kill the process group on overflow/deadline."""
    process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    buffers = {'stdout': bytearray(), 'stderr': bytearray()}
    limits = {'stdout': limit, 'stderr': stderr_limit}
    deadline = time.monotonic() + timeout
    try:
        with selectors.DefaultSelector() as selector:
            for name in buffers:
                stream = getattr(process, name)
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ, name)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(args, timeout)
                for key, _ in selector.select(remaining):
                    name = key.data
                    data = os.read(key.fd, min(65536, limits[name] - len(buffers[name]) + 1))
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    buffers[name].extend(data)
                    if len(buffers[name]) > limits[name]:
                        raise ValueError(f'{name} exceeds {limits[name]} byte output limit')
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(args, timeout)
            process.wait(timeout=remaining)
        return subprocess.CompletedProcess(args, process.returncode,
            buffers['stdout'].decode('utf-8', errors='replace'),
            buffers['stderr'].decode('utf-8', errors='replace'))
    finally:
        # Also stop descendants that inherited a pipe, even if the leader exited.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.stdout.close()
        process.stderr.close()
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass  # An uninterruptible kernel I/O operation must not hold the caller.


def read_text(path, limit):
    result = run_command([sys.executable, str(Path(__file__).resolve()), 'read', str(path), str(limit)],
                         timeout=1, limit=limit)
    if result.returncode == 2:
        raise FileNotFoundError(str(path))
    if result.returncode:
        raise OSError(result.stderr.strip()[:600] or 'Unable to read configuration')
    return result.stdout


def main():
    try:
        if sys.argv[1] == 'read':
            # O_NONBLOCK avoids waiting for a FIFO writer before fstat can reject it.
            fd = os.open(sys.argv[2], os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            with os.fdopen(fd, 'rb') as source:
                limit = int(sys.argv[3])
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
                    raise ValueError('Configuration must be a bounded regular file')
                data = source.read(limit + 1)
                if len(data) > limit:
                    raise ValueError('Configuration exceeds maximum size')
                data.decode('utf-8')  # Reject corrupt text, rather than repairing JSON silently.
                sys.stdout.buffer.write(data)
        elif sys.argv[1] == 'paste':
            args = ['wl-paste', '--no-newline', '--type', 'text']
            if sys.argv[2] == 'primary':
                args.append('--primary')
            result = run_command(args, timeout=2, limit=4096)
            if result.returncode:
                raise RuntimeError('Clipboard unavailable')
            print(json.dumps({'text': result.stdout}))
        else:
            raise ValueError('Unknown I/O operation')
    except FileNotFoundError as error:
        print(str(error)[:600], file=sys.stderr)
        return 2
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error)[:600], file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
