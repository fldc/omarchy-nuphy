"""Settings tests use mocked CLI output and never access HID hardware."""
import copy
import json
import subprocess
import unittest
from unittest.mock import patch

import nuphy_backend as backend
from nuphy_settings import Settings, validate

VALUES = dict(auto_sleep=True, level1_minutes=6, level2_minutes=24, accessory='knob')
DEVICE = dict(identity='one', path='/dev/hidraw99', vid=6645, pid=1, iface=3, page=1, usage=0, name='NuPhy Test')


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.settings = Settings()
        self.values = copy.deepcopy(VALUES)
        self.calls = []
        self.fail = False
        self.fail_read = False
        self.ignore_write = False
        identity = patch.object(backend, 'device_identity', side_effect=lambda d: d['identity'])
        identity.start(); self.addCleanup(identity.stop)
        cli = patch.object(backend, 'run_command', side_effect=self.cli)
        cli.start(); self.addCleanup(cli.stop)

    def cli(self, command, **kwargs):
        self.calls.append(command)
        for flag in ('--path', '--vid', '--pid', '--iface', '--usage-page', '--usage', '--json'):
            self.assertIn(flag, command)
        self.assertEqual(kwargs['timeout'], 30)
        if command[2] == 'get':
            if self.fail_read: raise RuntimeError('read failed')
            data = dict(self.values)
            if '--accessory' not in command: data.pop('accessory')
            return subprocess.CompletedProcess(command, 0, json.dumps(data), '')
        for key in self.values:
            flag = '--' + key.replace('_', '-')
            if flag in command and not self.ignore_write:
                value = command[command.index(flag) + 1]
                self.values[key] = (value == 'on') if key == 'auto_sleep' else (value if key == 'accessory' else int(value))
        if self.fail: raise RuntimeError('partial write')
        return subprocess.CompletedProcess(command, 0, '{"verified":true}', '')

    def load(self, accessory=False):
        return self.settings.execute('settings-load', DEVICE, {'accessory': accessory})

    def apply(self, changes):
        original = {key: self.settings.state['values'][key] for key in changes}
        return self.settings.execute('settings-apply', DEVICE, dict(identity='one', changes=changes, original=original))

    def test_plain_read_does_not_probe_accessory_or_write(self):
        state = self.load()
        self.assertTrue(state['known'])
        self.assertNotIn('accessory', state['values'])
        self.assertEqual(len(self.calls), 1)
        self.assertNotIn('--accessory', self.calls[0])

    def test_accessory_requires_opt_in(self):
        self.load()
        # Crafted request cannot enable writes before the accessory has been read.
        state = self.settings.execute('settings-apply', DEVICE, dict(identity='one',changes={'accessory':'button'},original={'accessory':'knob'}))
        self.assertIn('before editing', state['error'])
        self.assertFalse(any(c[2]=='set' for c in self.calls))
        self.load(True)
        self.assertEqual(self.apply({'accessory':'button'})['values']['accessory'], 'button')

    def test_disable_preserves_timers_and_only_requested_flag_is_sent(self):
        self.load()
        state = self.apply({'auto_sleep':False})
        self.assertEqual(state['message'], 'applied')
        self.assertEqual(self.values, dict(VALUES, auto_sleep=False))
        command = next(c for c in self.calls if c[2]=='set')
        self.assertNotIn('--level1-minutes', command)
        self.assertNotIn('--level2-minutes', command)
        self.assertEqual([c[2] for c in self.calls], ['get','get','set','get'])

    def test_failure_refreshes_without_automatic_retry(self):
        self.load()
        self.fail = True
        state = self.apply({'level1_minutes':8})
        self.assertIn('partial write', state['error'])
        self.assertTrue(state['known'])
        self.assertEqual(state['values']['level1_minutes'], 8)
        self.assertEqual(sum(c[2]=='set' for c in self.calls), 1)
        self.assertEqual(state['message'], '')

    def test_success_requires_matching_readback(self):
        self.load(); self.ignore_write = True
        state = self.apply({'level2_minutes':30})
        self.assertIn('Readback differs', state['error'])
        self.assertEqual(state['message'], '')

    def test_unchanged_and_conflicting_values_never_write(self):
        self.load()
        self.assertEqual(self.apply({'level1_minutes':6})['message'], 'unchanged')
        self.values['level1_minutes'] = 9
        self.assertIn('changed on the keyboard', self.apply({'level1_minutes':8})['error'])
        self.assertFalse(any(c[2]=='set' for c in self.calls))

    def test_stale_identity_and_disconnect_block_writes(self):
        self.load()
        state = self.settings.execute('settings-apply', dict(DEVICE, identity='two'), dict(identity='one',changes={'auto_sleep':False},original={'auto_sleep':True}))
        self.assertFalse(state['known'])
        self.assertFalse(any(c[2]=='set' for c in self.calls))
        self.assertFalse(self.settings.view(None)['known'])

    def test_unsupported_cli_has_clear_error(self):
        with patch.object(backend, 'run_command', return_value=subprocess.CompletedProcess([],2,'',"unrecognized subcommand 'settings'")):
            state = self.load()
        self.assertFalse(state['known'])
        self.assertIn('Upgrade nuphyctl', state['error'])

    def test_missing_cli_and_he_are_unavailable(self):
        with patch.object(backend, 'run_command', side_effect=FileNotFoundError('nuphyctl')):
            self.assertFalse(self.load()['known'])
        self.calls.clear()
        state = self.settings.execute('settings-load', dict(DEVICE,name='NuPhy HE'), {})
        self.assertIn('HE', state['error'])
        self.assertFalse(self.calls)

    def test_invalid_and_incomplete_values(self):
        for values in ({'reset':True},{'auto_sleep':1},{'level1_minutes':4},{'level2_minutes':128},{'level2_minutes':True},{'accessory':'bad'}):
            with self.assertRaises(ValueError): validate(values)
        with patch.object(backend,'run_command',return_value=subprocess.CompletedProcess([],0,'{}','')):
            self.assertFalse(self.load()['known'])

    def test_accessory_read_failure_preserves_sleep_controls(self):
        original = self.settings.read
        def read(device, accessory=False):
            if accessory: raise RuntimeError('Accessory unsupported')
            return original(device, accessory)
        with patch.object(self.settings, 'read', side_effect=read):
            state = self.load(True)
        self.assertTrue(state['known'])
        self.assertIn('unsupported', state['accessoryError'])
        self.assertNotIn('accessory', state['values'])

    def test_failed_readback_blocks_further_writes(self):
        self.load()
        original = self.cli
        def command(args, **kwargs):
            result = original(args, **kwargs)
            if args[2] == 'set': self.fail_read = True
            return result
        with patch.object(backend, 'run_command', side_effect=command):
            state = self.apply({'auto_sleep':False})
        self.assertFalse(state['known'])
        self.assertIn('Readback failed', state['error'])
        count = len(self.calls)
        self.apply({'auto_sleep':True})
        self.assertEqual(len(self.calls), count)

    def test_changing_device_during_read_prevents_writes(self):
        self.load()
        with patch.object(backend, 'device_identity', side_effect=['one', 'two']):
            state = self.apply({'level1_minutes':8})
        self.assertFalse(state['known'])
        self.assertFalse(any(c[2]=='set' for c in self.calls))
