#!/usr/bin/env python3
"""Verified NuPhy writes and recoverable preferences. No shell execution."""
import contextlib
import copy
import fcntl
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

MAIN = 'ray stair static breath flower wave ripple spout galaxy rotation ripple2 point grid time rain ribbon gaming identify windmill diagonal'.split()
SIDE = 'time neon static breathe rhythm'.split()
ZONES = ('main', 'side', 'decorative')
ACTIVE_ZONES = ('main', 'side')
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'omarchy-nuphy'
THEME = Path.home() / '.local/state/omarchy/current/theme/keyboard.rgb'
RETRY_SECONDS = 30
MAX_JSON = 65536


def defaults():
    return {'zones': {z: {'effect': 'static', 'hex': '#ffffff', 'brightness': 70,
                        'speed': 2, 'direction': 'right', 'sync': False,
                        'offset': 17} for z in ZONES},
            'applied': {}, 'deviceIdentity': '', 'error': '', 'retryAfter': 0, 'message': ''}


def validate(zone, values):
    if zone not in ZONES or not isinstance(values, dict):
        raise ValueError('Invalid lighting zone')
    result = copy.deepcopy(defaults()['zones'][zone])
    if set(values) - set(result):
        raise ValueError('Unknown lighting option')
    result.update(values)
    if result['effect'] not in (MAIN if zone == 'main' else SIDE):
        raise ValueError('Invalid effect')
    if not isinstance(result['hex'], str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', result['hex']):
        raise ValueError('Color must be #RRGGBB')
    result['hex'] = result['hex'].lower()
    for key, maximum in [('brightness', 100), ('speed', 4), ('offset', 53)]:
        if type(result[key]) is not int or not 0 <= result[key] <= maximum:
            raise ValueError(f'Invalid {key}')
    if type(result['sync']) is not bool or result['direction'] not in ('left', 'right'):
        raise ValueError('Invalid sync or direction')
    return result


def load_state(path):
    state = defaults()
    if not path.exists():
        return state
    try:
        with path.open() as source:
            text = source.read(MAX_JSON + 1)
        if len(text) > MAX_JSON:
            raise ValueError('State exceeds maximum size')
        raw = json.loads(text)
        if not isinstance(raw, dict) or not isinstance(raw.get('zones'), dict):
            raise ValueError('Invalid state object')
        state['zones'] = {z: validate(z, raw['zones'].get(z, {})) for z in ZONES}
        applied = raw.get('applied', {})
        if not isinstance(applied, dict) or any(z not in ZONES or not isinstance(v, str) or len(v) > 4096 for z, v in applied.items()):
            raise ValueError('Invalid applied signatures')
        state['applied'] = applied
        for key, limit in [('error', 600), ('message', 600), ('deviceIdentity', 1024)]:
            if not isinstance(raw.get(key, ''), str):
                raise ValueError(f'Invalid {key}')
            state[key] = raw.get(key, '')[:limit]
        retry = raw.get('retryAfter', 0)
        if type(retry) not in (float, int) or not math.isfinite(retry):
            raise ValueError('Invalid retry deadline')
        state['retryAfter'] = min(max(0, retry), time.time() + RETRY_SECONDS)
        return state
    except (ValueError, TypeError, OSError) as error:
        backup = path.with_name(f'state.corrupt-{time.time_ns()}.json')
        try:
            path.replace(backup)
            detail = f'Backup: {backup.name}'
        except OSError:
            detail = 'Could not back up preferences'
        state = defaults()
        state['error'] = f'Preferences could not be loaded; sync disabled. {detail}: {error}'[:600]
        return state


def save_state(path, state):
    encoded = json.dumps(state, sort_keys=True)
    if path.exists() and path.read_text() == encoded:
        return
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.state-', delete=False) as target:
            name = target.name
            target.write(encoded)
            target.flush()
            os.fsync(target.fileno())
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


@contextlib.contextmanager
def state_lock(timeout=2):
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'lock').open('w') as lock:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Keyboard worker busy; try again shortly')
                time.sleep(0.02)
        yield


def theme_color():
    try:
        with THEME.open() as source:
            color = source.read(128).strip()
        return color.lower() if re.fullmatch(r'#[0-9a-fA-F]{6}', color) else ''
    except (OSError, UnicodeError):
        return ''


def select_device(output):
    """Rank only verified NuPhy interfaces; never target an unrelated HID."""
    devices = []
    for line in output[:262144].splitlines()[:1024]:
        fields = re.search(r'^path=("(?:[^"\\]|\\.)*") vid=(0x[0-9a-f]+) pid=(0x[0-9a-f]+) usage_page=(0x[0-9a-f]+) usage=(0x[0-9a-f]+) iface=(-?\d+) ', line)
        if not fields:
            continue
        def string_field(key):
            match = re.search(r'\b' + key + r'=Some\(("(?:[^"\\]|\\.)*")\)', line)
            try:
                return json.loads(match[1])[:128].strip() if match else ''
            except ValueError:
                return ''
        try:
            path = json.loads(fields[1])
        except ValueError:
            continue
        vid, pid, page, usage = [int(v, 16) for v in fields.groups()[1:5]]
        iface = int(fields[6])
        if not re.fullmatch(r'/dev/hidraw\d+', path):
            continue
        if vid != 0x19f5 and string_field('manufacturer').casefold() != 'nuphy':
            continue
        score = (100 if (page, usage) == (1, 0) else 0) + (50 if iface == 3 else 0)
        score -= 20 if (page, usage) == (1, 128) else 30 if (page, usage) == (1, 6) else 0
        product = string_field('product')
        devices.append({'path': path, 'vid': vid, 'pid': pid, 'page': page, 'usage': usage,
                        'iface': iface, 'score': score, 'serial': string_field('serial'),
                        'name': product if 'nuphy' in product.lower() else ('NuPhy ' + product if product else '')})
    devices.sort(key=lambda d: d['score'], reverse=True)
    if not devices:
        return None
    if len({d['path'] for d in devices}) > 1:
        if devices[0]['score'] <= 0 or devices[0]['score'] == devices[1]['score']:
            return None
    return devices[0]


def keyboard_name(output):
    device = select_device(output)
    return device['name'] if device else ''


def device_identity(device):
    node = os.stat(device['path'])
    return json.dumps([device['vid'], device['pid'], device['serial'], device['path'], node.st_ino, node.st_ctime_ns])


def discover_device():
    result = subprocess.run(['nuphyctl', 'list'], capture_output=True, text=True, timeout=3)
    if result.returncode:
        raise RuntimeError((result.stderr or 'Unable to list NuPhy keyboards').strip()[:600])
    device = select_device(result.stdout)
    if device:
        try:
            device['identity'] = device_identity(device)
        except OSError:
            return None
    return device


def command(zone, config, color, device):
    args = ['nuphyctl', 'rgb', 'set' if zone == 'main' else zone,
            '--effect', config['effect'], '--hex', color,
            '--brightness', str(config['brightness']), '--speed', str(config['speed']),
            '--path', device['path'], '--vid', str(device['vid']), '--pid', str(device['pid']),
            '--iface', str(device['iface']), '--usage-page', str(device['page']), '--usage', str(device['usage'])]
    if zone == 'main':
        args += ['--direction', config['direction']]
    return args


def apply(state, zone, color, device, force=False):
    if zone not in ACTIVE_ZONES:
        raise ValueError('Lighting zone is disabled in this widget')
    if not device:
        raise ValueError('No unambiguous NuPhy control interface found; connect one keyboard')
    args = command(zone, state['zones'][zone], color, device)
    signature = json.dumps(args)
    if not force and state['applied'].get(zone) == signature:
        return
    if device_identity(device) != device['identity']:
        raise RuntimeError('Keyboard changed; retry after device discovery')
    completed = subprocess.run(args, capture_output=True, text=True, timeout=12)
    if completed.returncode:
        raise RuntimeError((completed.stderr or completed.stdout or 'nuphyctl failed').strip()[:600])
    state['applied'][zone] = signature
    state['message'] = f'{zone.capitalize()} lighting applied'


def run(state, action, device=None, zone=None, payload=None):
    identity = device['identity'] if device else ''
    if state['deviceIdentity'] != identity:
        state['deviceIdentity'] = identity
        state['applied'] = {}
        state['retryAfter'] = 0
    color = theme_color()
    if action == 'apply':
        if zone not in ACTIVE_ZONES:
            raise ValueError('Lighting zone is disabled in this widget')
        config = validate(zone, payload)
        if config['sync'] and not color:
            raise ValueError('Theme keyboard.rgb is missing or invalid')
        state['zones'][zone] = config
        state['applied'].pop(zone, None)
        apply(state, zone, color if config['sync'] else config['hex'], device, force=True)
        state['error'] = ''
        state['retryAfter'] = 0
    elif action in ('tick', 'sync'):
        targets = [z for z in ACTIVE_ZONES if state['zones'][z]['sync']]
        if action == 'sync' or time.time() >= state['retryAfter']:
            if targets and not color:
                raise ValueError('Theme keyboard.rgb is missing or invalid')
            for z in targets:
                apply(state, z, color, device, force=action == 'sync')
            if targets:
                state['error'] = ''
                state['retryAfter'] = 0
    elif action != 'status':
        raise ValueError('Unknown action')


class Worker:
    def __init__(self):
        self.device = None
        self.discovery_error = ''
        self.starting = True

    def discover(self):
        try:
            self.device = discover_device()
            self.discovery_error = ''
        except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
            self.device = None
            self.discovery_error = str(error)[:600]

    def execute(self, request):
        with state_lock():
            path = STATE / 'state.json'
            state = load_state(path)
            if self.starting:
                state['applied'] = {}
                state['retryAfter'] = 0
                self.starting = False
            try:
                run(state, request.get('action', 'tick'), self.device, request.get('zone'), request.get('config'))
            except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
                state['error'] = str(error)[:600]
                state['retryAfter'] = time.time() + RETRY_SECONDS
            save_state(path, state)
        return {**state, 'theme': theme_color(), 'keyboardName': self.device['name'] if self.device else '',
                'connected': self.device is not None, 'discoveryError': self.discovery_error}
