"""Keymap operations through nuphyctl; all hardware access stays in the worker."""
import json
from pathlib import Path
import subprocess
import tempfile

import nuphy_backend as backend

LIMIT = 4 * 1024 * 1024


class CommandError(RuntimeError):
    def __init__(self, message):
        super().__init__(message)
        lowered = message.lower()
        self.kind = 'unsupported' if any(word in lowered for word in ('unrecognized subcommand', 'unknown subcommand', 'unexpected argument', 'unrecognized option')) else 'read'



def integer(value, maximum):
    if type(value) is not int or not 0 <= value <= maximum:
        raise ValueError('Invalid keymap integer')
    return value


def cli(args, device=None):
    command = ['nuphyctl', 'keymap', *args, '--json']
    if device:
        if backend.device_identity(device) != device['identity']:
            raise RuntimeError('Keyboard changed; refresh keymap')
        for flag, field in [('path', 'path'), ('vid', 'vid'), ('pid', 'pid'), ('iface', 'iface'),
                            ('usage-page', 'page'), ('usage', 'usage')]:
            command += ['--' + flag, str(device[field])]
    # File-backed output keeps large/malformed CLI responses out of shell memory.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        result = subprocess.run(command, stdout=out, stderr=err, timeout=30)
        out.seek(0)
        raw = out.read(LIMIT + 1)
        err.seek(0)
        diagnostic = err.read(4096).decode(errors='replace')
    if result.returncode:
        raise CommandError(diagnostic.strip()[:600] or 'nuphyctl keymap failed')
    if len(raw) > LIMIT:
        raise ValueError('Keymap response too large')
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError('Invalid keymap response')
    return value


def parse_info(info):
    layers = integer(info.get('layer_count'), 32)
    matrix = info.get('matrix', {})
    if not isinstance(matrix, dict):
        raise ValueError('Invalid keymap matrix')
    rows = integer(matrix.get('rows'), 32)
    cols = integer(matrix.get('cols'), 32)
    extras = integer(info.get('extra_entries'), 32)
    if not layers or not rows or not cols:
        raise ValueError('Empty keymap geometry')
    return layers, rows * cols + extras


def mappings(value, geometry):
    layers, count = geometry
    result = {}
    entries = value.get('layers')
    if not isinstance(entries, list) or len(entries) != layers:
        raise ValueError('Incomplete keymap layers')
    for layer in entries:
        if not isinstance(layer, dict):
            raise ValueError('Invalid keymap layer')
        number = integer(layer.get('layer'), layers - 1)
        keys = layer.get('keys')
        if not isinstance(keys, list) or len(keys) != count:
            raise ValueError('Incomplete keymap keys')
        for key in keys:
            if not isinstance(key, dict):
                raise ValueError('Invalid keymap key')
            index = integer(key.get('index'), count - 1)
            address = f'{number}:{index}'
            if address in result:
                raise ValueError('Duplicate keymap address')
            result[address] = {'layer': number, 'index': index,
                               'value': integer(key.get('value'), 65535),
                               'position': str(key.get('position') or (f'{key["row"]},{key["col"]} (#{index})' if key.get('row') is not None and key.get('col') is not None else f'#{index}'))[:80],
                               'name': str(key.get('name') or key.get('code') or '')[:80]}
    return result


def catalog(value):
    keys = value.get('keycodes')
    if not isinstance(keys, list) or len(keys) > 4096:
        raise ValueError('Invalid keycode catalog')
    if any(not isinstance(k, dict) for k in keys):
        raise ValueError('Invalid keycode entry')
    return [{'value': integer(k.get('value'), 65535), 'name': str(k.get('name', ''))[:80],
             'group': str(k.get('group', ''))[:80], 'description': str(k.get('description', ''))[:200],
             'aliases': str(k.get('aliases', []))[:300]} for k in keys]


def toml(changes):
    sections = []
    for layer in sorted({c['layer'] for c in changes}):
        sections.append(f'[layers.{layer}]')
        sections.extend(f'"#{c["index"]}" = {c["value"]}' for c in changes if c['layer'] == layer)
    return '\n'.join(sections) + '\n'


class Keymap:
    def __init__(self):
        self.codes = None
        self.state = {}

    def load(self, device):
        if not device:
            raise ValueError('Connect one unambiguous NuPhy keyboard')
        info = cli(['info'], device)
        geometry = parse_info(info)
        per_mode = integer(info.get('layers_per_mode'), geometry[0])
        mode = info.get('current_mode', {})
        if not per_mode or geometry[0] % per_mode or not isinstance(mode, dict):
            raise ValueError('Invalid keymap modes')
        mode_count = geometry[0] // per_mode
        current_mode = integer(mode.get('mode'), mode_count - 1)
        info = {**info, 'product': str(info.get('product') or '')[:128],
                'current_mode': {'mode': current_mode},
                'modes': [{'mode': i, 'name': ['mac', 'windows'][i] if i < 2 else str(i)} for i in range(mode_count)]}
        current = mappings(cli(['dump'], device), geometry)
        factory = mappings(cli(['dump', '--defaults'], device), geometry)
        if self.codes is None:
            self.codes = catalog(cli(['keycodes']))
        last_backup = self.state.get('backup', '') if self.state.get('identity') == device['identity'] else ''
        serial = device.get('serial', '').strip()
        stable = json.dumps([device.get('vid'), device.get('pid'), serial]) if serial and serial not in ('0', '00000000') and not serial.casefold().startswith(('nuphy keybord', 'nuphy keyboard')) else ''
        signature = json.dumps([info['product'], info['matrix'], info['extra_entries'], info['layer_count'], info['layers_per_mode']], sort_keys=True)
        self.state = {'identity': device['identity'], 'stableIdentity': stable, 'signature': signature,
                      'conflicts': [], 'errorKind': '', 'message': '', 'info': info, 'keys': current,
                      'factory': factory, 'codes': self.codes, 'known': True, 'error': '', 'backup': last_backup}
        return self.state

    def apply(self, device, payload):
        if not isinstance(payload, dict):
            raise ValueError('Invalid keymap request')
        if not device or not self.state.get('known') or payload.get('identity') != device['identity'] or self.state.get('identity') != device['identity']:
            raise ValueError('Keyboard changed; refresh keymap before applying')
        geometry = parse_info(self.state['info'])
        changes = payload.get('changes')
        if not isinstance(changes, list) or not changes or len(changes) > geometry[0] * geometry[1]:
            raise ValueError('Invalid keymap changes')
        seen = set()
        for change in changes:
            if not isinstance(change, dict):
                raise ValueError('Invalid keymap change')
            layer = integer(change.get('layer'), geometry[0] - 1)
            index = integer(change.get('index'), geometry[1] - 1)
            integer(change.get('value'), 65535)
            integer(change.get('original'), 65535)
            address = f'{layer}:{index}'
            if address in seen:
                raise ValueError('Duplicate keymap change')
            seen.add(address)
        backend.STATE.mkdir(parents=True, exist_ok=True)
        backup_dir = backend.STATE / 'keymap-backups'
        backup_dir.mkdir(mode=0o700, exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix='keymap-', suffix='.bin', dir=backup_dir, delete=False) as backup:
            self.state['backup'] = backup.name
        current = mappings(cli(['dump', '--raw-out', self.state['backup']], device), geometry)
        if Path(self.state['backup']).stat().st_size != geometry[0] * geometry[1] * 2:
            raise ValueError('Incomplete recovery backup; nothing was written')
        self.state['keys'] = current
        conflicts = [c for c in changes if current[f'{c["layer"]}:{c["index"]}']['value'] not in (c['original'], c['value'])]
        self.state['conflicts'] = [{**c, 'identity': device['identity'],
                                    'current': current[f'{c["layer"]}:{c["index"]}']['value']} for c in conflicts]
        if conflicts:
            self.state.update(error='Assignments changed externally; resolve the conflicting keys', errorKind='conflict', known=True, message='')
            return self.state
        pending = [c for c in changes if current[f'{c["layer"]}:{c["index"]}']['value'] != c['value']]
        self.state['known'] = False
        try:
            if pending:
                with tempfile.NamedTemporaryFile(mode='w', suffix='.toml') as config:
                    config.write(toml(pending))
                    config.flush()
                    result = cli(['apply', config.name], device)
                    if result.get('verified') is not True and result.get('changes') != []:
                        raise RuntimeError('Keymap write was not verified')
            self.state.update(error='', errorKind='', message='applied' if pending else 'unchanged')
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            self.state.update(error=str(error)[:600], errorKind='write', message='')
        finally:
            try:
                self.state['keys'] = mappings(cli(['dump'], device), geometry)
                self.state['known'] = True
                if any(self.state['keys'][f'{c["layer"]}:{c["index"]}']['value'] != c['value'] for c in changes):
                    self.state['error'] = self.state['error'] or 'Readback differs from requested assignments'
                    self.state.update(errorKind='write', message='')
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                self.state.update(errorKind='unknown', message='')
                self.state['error'] = (self.state['error'] + '\nReadback failed: ' + str(error))[:600]
        return self.state

    def execute(self, action, device, payload):
        try:
            if action == 'keymap-load':
                return self.load(device)
            return self.apply(device, payload or {})
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            self.state = {**self.state, 'error': str(error)[:600], 'known': False, 'message': '',
                          'errorKind': 'unavailable' if not device else getattr(error, 'kind', 'read')}
            return self.state
