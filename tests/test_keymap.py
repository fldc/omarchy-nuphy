import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import nuphy_keymap as km

INFO = {'layer_count': 2, 'layers_per_mode': 1, 'matrix': {'rows': 1, 'cols': 2}, 'extra_entries': 0}


def dump(values=(4, 5, 6, 7)):
    return {'layers': [{'layer': l, 'keys': [{'index': i, 'value': values[l * 2 + i], 'position': str(i)} for i in range(2)]} for l in range(2)]}


class KeymapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(patch.stopall)
        patch.object(km.backend, 'STATE', Path(self.tmp.name)).start()
        self.device = {'identity': 'test'}
        self.map = km.Keymap()
        self.map.state = {'identity': 'test', 'known': True, 'info': INFO, 'keys': km.mappings(dump(), (2, 2))}
        self.payload = {'identity': 'test', 'changes': [{'layer': 0, 'index': 0, 'original': 4, 'value': 9}]}
        self.calls = []
        self.current = dump()
        self.fail = False
        self.read_fail = False

    def cli(self, args, device=None):
        self.calls.append(args)
        if args[0] == 'dump':
            if self.read_fail:
                raise RuntimeError('read failed')
            if '--raw-out' in args:
                Path(args[args.index('--raw-out') + 1]).write_bytes(b'\0' * 8)
            return self.current
        if args[0] == 'apply':
            self.assertEqual(Path(args[1]).read_text(), '[layers.0]\n"#0" = 9\n')
            if self.fail:
                raise subprocess.TimeoutExpired('nuphyctl', 30)
            self.current = dump((9, 5, 6, 7))
            return {'verified': True}
        raise AssertionError(args)

    def test_apply_and_backup_readback(self):
        with patch.object(km, 'cli', self.cli):
            state = self.map.execute('keymap-apply', self.device, self.payload)
        self.assertTrue(state['known'])
        self.assertEqual(state['keys']['0:0']['value'], 9)
        self.assertTrue(Path(state['backup']).exists())
        self.assertEqual([a[0] for a in self.calls], ['dump', 'apply', 'dump'])

    def test_conflict_does_not_write(self):
        self.current = dump((8, 5, 6, 7))
        with patch.object(km, 'cli', self.cli):
            state = self.map.execute('keymap-apply', self.device, self.payload)
        self.assertIn('externally', state['error'])
        self.assertTrue(state['known'])
        self.assertEqual(state['conflicts'][0]['current'], 8)
        self.assertEqual(len(self.calls), 1)

    def test_matching_assignment_is_noop(self):
        self.current = dump((9, 5, 6, 7))
        with patch.object(km, 'cli', self.cli):
            state = self.map.execute('keymap-apply', self.device, self.payload)
        self.assertFalse(state['error'])
        self.assertFalse(any(a[0] == 'apply' for a in self.calls))

    def test_timeout_preserves_actual_state_and_backup(self):
        self.fail = True
        with patch.object(km, 'cli', self.cli):
            state = self.map.execute('keymap-apply', self.device, self.payload)
        self.assertTrue(state['known'])
        self.assertTrue(state['error'])
        self.assertEqual(state['keys']['0:0']['value'], 4)
        self.assertTrue(Path(state['backup']).exists())

    def test_stale_device_and_invalid_changes_do_not_run_cli(self):
        for payload in [dict(self.payload, identity='other'), dict(self.payload, changes=[None]), dict(self.payload, changes=[{'layer': True}]), []]:
            with patch.object(km, 'cli') as run:
                self.map.execute('keymap-apply', self.device, payload)
                run.assert_not_called()

    def test_incomplete_readback_and_duplicate_addresses_rejected(self):
        for data in [{}, {'layers': [None, None]}, dump((4, 5, 6, 7))]:
            bad = copy.deepcopy(data)
            if 'layers' in bad and isinstance(bad['layers'][0], dict):
                bad['layers'][0]['keys'][1]['index'] = 0
            with self.assertRaises(ValueError):
                km.mappings(bad, (2, 2))

    def test_explicit_selectors_and_json(self):
        device = {'identity': 'test', 'path': '/dev/hidraw9', 'vid': 6645, 'pid': 1, 'iface': 3, 'page': 1, 'usage': 0}
        def run(args, *, timeout, limit):
            self.assertIn('--path', args)
            self.assertIn('--iface', args)
            self.assertIn('--usage-page', args)
            self.assertIn('--vid', args)
            return subprocess.CompletedProcess(args, 0, json.dumps({'ok': True}), '')
        with patch.object(km.backend, 'device_identity', return_value='test'), patch.object(km.backend, 'run_command', side_effect=run):
            self.assertTrue(km.cli(['info'], device)['ok'])

    def test_failed_readback_blocks_next_apply(self):
        def run(args, device=None):
            result = self.cli(args, device)
            if args[0] == 'apply':
                self.read_fail = True
            return result
        with patch.object(km, 'cli', run):
            state = self.map.execute('keymap-apply', self.device, self.payload)
            self.assertFalse(state['known'])
            self.assertIn('Readback failed', state['error'])
            count = len(self.calls)
            self.map.execute('keymap-apply', self.device, self.payload)
            self.assertEqual(len(self.calls), count)

    def test_incomplete_backup_prevents_write(self):
        def run(args, device=None):
            result = self.cli(args, device)
            if '--raw-out' in args:
                Path(args[args.index('--raw-out') + 1]).write_bytes(b'')
            return result
        with patch.object(km, 'cli', run):
            state = self.map.execute('keymap-apply', self.device, self.payload)
        self.assertIn('Incomplete recovery backup', state['error'])
        self.assertEqual(len(self.calls), 1)

    def test_load_caches_catalog_and_preserves_unknown_values(self):
        calls = []
        def run(args, device=None):
            calls.append(args)
            if args[0] == 'info':
                return dict(INFO, current_mode={'mode': 1}, product='<img src="https://example.invalid">')
            if args[0] == 'keycodes':
                return {'keycodes': [{'name': 'A', 'value': 4}]}
            return dump((65535, 5, 6, 7))
        with patch.object(km, 'cli', run):
            state = self.map.load(self.device)
            self.map.load(self.device)
        self.assertEqual(state['keys']['0:0']['value'], 65535)
        self.assertEqual(sum(a[0] == 'keycodes' for a in calls), 1)
        self.assertEqual(state['info']['current_mode']['mode'], 1)

    def test_numeric_toml_round_trip_across_layers(self):
        import tomllib
        result = tomllib.loads(km.toml([{'layer': 0, 'index': 0, 'value': 9}, {'layer': 1, 'index': 1, 'value': 65535}]))
        self.assertEqual(result, {'layers': {'0': {'#0': 9}, '1': {'#1': 65535}}})
