"""Explicit, verified sleep/accessory edits through the mechanical settings CLI."""
import json
import re
import subprocess

import nuphy_backend as backend

FIELDS = {'auto_sleep', 'level1_minutes', 'level2_minutes', 'accessory'}


def validate(values):
    if not isinstance(values, dict) or set(values) - FIELDS:
        raise ValueError('Invalid keyboard settings')
    for key, value in values.items():
        if key == 'auto_sleep':
            if type(value) is not bool:
                raise ValueError('Auto sleep must be on or off')
        elif key == 'accessory':
            if value not in ('knob', 'button'):
                raise ValueError('Accessory must be knob or button')
        elif type(value) is not int or not 5 <= value <= 127:
            raise ValueError('Sleep timers must be 5–127 minutes')
    return values


class Settings:
    def __init__(self):
        self.state = {}

    def view(self, device):
        if not device or self.state.get('identity') != device['identity']:
            self.state = {'known': False, 'identity': device['identity'] if device else ''}
        return self.state

    def cli(self, args, device):
        if not device or backend.device_identity(device) != device['identity']:
            raise ValueError('Keyboard changed; refresh settings')
        if re.search(r'\bHE\b', device.get('name', ''), re.I):
            raise ValueError('HE keyboard settings are unsupported')
        command = [backend.CLI, 'settings', *args, '--json']
        for flag, field in [('path', 'path'), ('vid', 'vid'), ('pid', 'pid'), ('iface', 'iface'),
                            ('usage-page', 'page'), ('usage', 'usage')]:
            command += ['--' + flag, str(device[field])]
        result = backend.run_command(command, timeout=30, limit=16384)
        if result.returncode:
            diagnostic = (result.stderr or result.stdout).strip()[:600]
            if any(word in diagnostic.lower() for word in ('unrecognized subcommand', 'unknown subcommand', 'unexpected argument', 'unrecognized option')):
                raise RuntimeError('Settings unavailable: this nuphyctl backend does not support the settings commands. Upgrade nuphyctl or select a compatible development build.')
            raise RuntimeError(diagnostic or 'Unable to access keyboard settings')
        return result.stdout

    def read(self, device, accessory=False):
        raw = json.loads(self.cli(['get'] + (['--accessory'] if accessory else []), device))
        required = {'auto_sleep', 'level1_minutes', 'level2_minutes'} | ({'accessory'} if accessory else set())
        if not isinstance(raw, dict) or not required <= raw.keys():
            raise ValueError('Incomplete keyboard settings response')
        values = validate({key: raw[key] for key in required})
        if backend.device_identity(device) != device['identity']:
            raise ValueError('Keyboard changed during settings read; refresh settings')
        return values

    def load(self, device, accessory=False):
        self.view(device)
        self.state = {'identity': device['identity'] if device else '', 'known': False}
        if not device:
            raise ValueError('Connect one unambiguous NuPhy keyboard')
        values = self.read(device)
        self.state.update(known=True, values=values, error='', accessoryError='', message='')
        if accessory:
            try:
                self.state['values'] = self.read(device, True)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                self.state['accessoryError'] = str(error)[:600]
        return self.state

    def apply(self, device, payload):
        self.view(device)
        if not device or not self.state.get('known') or not isinstance(payload, dict) or payload.get('identity') != device['identity']:
            raise ValueError('Keyboard changed; refresh settings before applying')
        changes = validate(payload.get('changes'))
        original = validate(payload.get('original'))
        if not changes or set(changes) != set(original):
            raise ValueError('Invalid settings draft')
        accessory = 'accessory' in self.state.get('values', {})
        if 'accessory' in changes and not accessory:
            raise ValueError('Read the accessory switch before editing it')
        # Re-read before writing and refuse edited-field conflicts; untouched fields stay untouched.
        current = self.read(device, accessory)
        self.state.update(values=current, message='', error='')
        if any(current[key] not in (original[key], changes[key]) for key in changes):
            raise ValueError('Settings changed on the keyboard. Refresh and review your edits.')
        pending = {key: value for key, value in changes.items() if current[key] != value}
        if not pending:
            self.state['message'] = 'unchanged'
            return self.state
        args = ['set']
        for key, value in pending.items():
            args += ['--' + key.replace('_', '-'), ('on' if value else 'off') if key == 'auto_sleep' else str(value)]
        self.state['known'] = False
        error = ''
        try:
            self.cli(args, device)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as failure:
            error = str(failure)[:600]
        # Always refresh after a write attempt; command success alone is insufficient.
        try:
            values = self.read(device, accessory)
            self.state.update(values=values, known=True)
            if any(values[key] != value for key, value in pending.items()):
                error = error or 'Readback differs from requested settings'
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as failure:
            error = (error + '\nReadback failed: ' + str(failure)).strip()[:600]
        self.state.update(error=error, message='' if error else 'applied')
        return self.state

    def execute(self, action, device, payload):
        try:
            if action == 'settings-load':
                return self.load(device, isinstance(payload, dict) and payload.get('accessory') is True)
            return self.apply(device, payload)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            self.state.update(error=str(error)[:600], message='')
            # Failed preflight/read is not current hardware state. Validation/conflict errors also require review.
            self.state['known'] = False
            return self.state
