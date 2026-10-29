import concurrent.futures
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import nuphy_backend as b
import nuphy_worker as w


def device_line(product='Air75 V3', path='/dev/hidraw3', vid='0x19f5', iface=3, usage='0x0000', manufacturer='NuPhy'):
    return f'path="{path}" vid={vid} pid=0x1028 usage_page=0x0001 usage={usage} iface={iface} product=Some({json.dumps(product)}) manufacturer=Some({json.dumps(manufacturer)}) serial=Some("test-serial")'


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nuphy-test-')
        self.addCleanup(self.tmp.cleanup)
        self.state_dir = Path(self.tmp.name)
        self.device = b.select_device(device_line())
        self.device['identity'] = 'generation-1'
        for name, value in [('STATE', self.state_dir), ('THEME', self.state_dir / 'keyboard.rgb')]:
            p = patch.object(b, name, value)
            p.start()
            self.addCleanup(p.stop)
        b.THEME.write_text('#123456')
        identity = patch.object(b, 'device_identity', side_effect=lambda device: device['identity'])
        identity.start()
        self.addCleanup(identity.stop)

    def success(self):
        return patch.object(b.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', ''))

    def test_product_names(self):
        for product in ['Air75 V3', 'Air96 V2', 'Halo75', 'NuPhy Kick75']:
            self.assertEqual(b.keyboard_name(device_line(product)), product if product.startswith('NuPhy') else 'NuPhy ' + product)

    def test_unrelated_device_never_selected(self):
        other = device_line('USB Receiver', vid='0x046d', manufacturer='Logitech')
        self.assertIsNone(b.select_device(other))
        self.assertIsNotNone(b.select_device(other + '\n' + device_line()))
        self.assertIsNone(b.select_device(device_line('NuPhy fake', vid='0x046d', manufacturer='Logitech')))

    def test_ambiguous_devices_rejected(self):
        self.assertIsNone(b.select_device(device_line() + '\n' + device_line('Halo96', '/dev/hidraw9')))
        self.assertIsNone(b.select_device(''))
        self.assertIsNone(b.select_device('malformed output'))

    def test_interface_ranking(self):
        result = b.select_device(device_line(path='/dev/hidraw0', iface=0, usage='0x0006') + '\n' + device_line())
        self.assertEqual(result['path'], '/dev/hidraw3')

    def test_names_are_data(self):
        self.assertEqual(b.keyboard_name(device_line('<img src="https://example.invalid">')), 'NuPhy <img src="https://example.invalid">')
        self.assertIn('textFormat: Text.PlainText', (Path(__file__).parents[1] / 'PlainText.qml').read_text())

    def test_no_writes_without_opt_in(self):
        with self.success() as run:
            b.run(b.defaults(), 'tick', self.device)
            run.assert_not_called()

    def test_no_write_without_verified_device(self):
        with self.success() as run:
            with self.assertRaisesRegex(ValueError, 'NuPhy control interface'):
                b.run(b.defaults(), 'apply', None, 'main', {})
            run.assert_not_called()

    def test_all_writes_have_explicit_selectors(self):
        for zone in b.ACTIVE_ZONES:
            with self.subTest(zone=zone), self.success() as run:
                b.run(b.defaults(), 'apply', self.device, zone, {})
                args = run.call_args.args[0]
                self.assertEqual(args[:3], ['nuphyctl', 'rgb', 'set' if zone == 'main' else zone])
                for flag in ['--path', '--vid', '--pid', '--iface', '--usage-page', '--usage']:
                    self.assertIn(flag, args)
                self.assertEqual(args[args.index('--path') + 1], '/dev/hidraw3')

    def test_identity_rechecked_before_write(self):
        with patch.object(b, 'device_identity', return_value='replaced'), self.success() as run:
            with self.assertRaisesRegex(RuntimeError, 'Keyboard changed'):
                b.run(b.defaults(), 'apply', self.device, 'main', {})
            run.assert_not_called()

    def test_legacy_decorative_sync_never_writes(self):
        state = b.defaults()
        state['zones']['decorative']['sync'] = True
        with self.success() as run:
            b.run(state, 'tick', self.device)
            b.run(state, 'sync', self.device)
            run.assert_not_called()
        self.assertTrue(state['zones']['decorative']['sync'])

    def test_decorative_manual_writes_rejected(self):
        with self.success() as run:
            with self.assertRaisesRegex(ValueError, 'disabled'):
                b.run(b.defaults(), 'apply', self.device, 'decorative', {})
            with self.assertRaisesRegex(ValueError, 'disabled'):
                b.apply(b.defaults(), 'decorative', '#123456', self.device)
            run.assert_not_called()

    def test_sync_deduplication_and_theme_change(self):
        state = b.defaults()
        state['zones']['main']['sync'] = True
        with self.success() as run:
            b.run(state, 'tick', self.device)
            b.run(state, 'tick', self.device)
            self.assertEqual(run.call_count, 1)
            b.THEME.write_text('#abcdef')
            b.run(state, 'tick', self.device)
            self.assertEqual(run.call_count, 2)
            self.assertIn('#abcdef', run.call_args.args[0])

    def test_reconnect_invalidates_cache(self):
        state = b.defaults()
        state['zones']['main']['sync'] = True
        with self.success() as run:
            b.run(state, 'tick', self.device)
            self.device['identity'] = 'generation-2'
            b.run(state, 'tick', self.device)
            self.assertEqual(run.call_count, 2)

    def test_disconnect_invalidates_cache(self):
        state = b.defaults()
        state['zones']['main']['sync'] = True
        with self.success() as run:
            b.run(state, 'tick', self.device)
            with self.assertRaises(ValueError):
                b.run(state, 'tick', None)
            b.run(state, 'tick', self.device)
            self.assertEqual(run.call_count, 2)

    def test_worker_restart_invalidates_cache(self):
        state = b.defaults()
        state['zones']['main']['sync'] = True
        with self.success() as run:
            b.run(state, 'tick', self.device)
            b.save_state(self.state_dir / 'state.json', state)
            worker = b.Worker()
            worker.device = self.device
            worker.execute({'action': 'tick'})
            self.assertEqual(run.call_count, 2)

    def test_failed_forced_write_invalidates_success(self):
        state = b.defaults()
        with self.success():
            b.run(state, 'apply', self.device, 'main', {})
        with patch.object(b.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'Disconnected')):
            with self.assertRaises(RuntimeError):
                b.run(state, 'apply', self.device, 'main', {})
        self.assertNotIn('main', state['applied'])

    def test_invalid_preferences_never_write(self):
        for key, value in [('hex', '#123456; reboot'), ('brightness', 101), ('brightness', True),
                           ('speed', -1), ('effect', 'bad'), ('offset', 100), ('sync', 'yes'), ('direction', 'up')]:
            with self.subTest(key=key), self.success() as run:
                with self.assertRaises(ValueError):
                    b.run(b.defaults(), 'apply', self.device, 'main', {key: value})
                run.assert_not_called()

    def test_missing_theme_never_writes(self):
        b.THEME.unlink()
        state = b.defaults()
        state['zones']['main']['sync'] = True
        with self.success() as run:
            with self.assertRaises(ValueError):
                b.run(state, 'tick', self.device)
            run.assert_not_called()

    def test_timeout_is_reported_and_not_cached(self):
        worker = b.Worker()
        worker.device = self.device
        with patch.object(b.subprocess, 'run', side_effect=subprocess.TimeoutExpired('nuphyctl', 12)):
            result = worker.execute({'action': 'apply', 'zone': 'main', 'config': {}})
        self.assertIn('timed out', result['error'])
        self.assertNotIn('main', result['applied'])
        self.assertGreater(result['retryAfter'], time.time())

    def test_corrupt_state_is_preserved_and_sync_disabled(self):
        for text in ['{broken', '[]', '{"zones": 3}', '{"zones": {}, "retryAfter": "bad"}', '{"zones": {}, "applied": []}']:
            with self.subTest(text=text):
                path = self.state_dir / 'state.json'
                path.write_text(text)
                before = set(self.state_dir.glob('state.corrupt-*.json'))
                state = b.load_state(path)
                backups = set(self.state_dir.glob('state.corrupt-*.json')) - before
                self.assertEqual(len(backups), 1)
                self.assertEqual(next(iter(backups)).read_text(), text)
                self.assertTrue(state['error'])
                self.assertFalse(any(zone['sync'] for zone in state['zones'].values()))

    def test_worker_recovers_corrupt_state(self):
        (self.state_dir / 'state.json').write_text('{broken')
        worker = b.Worker()
        worker.device = self.device
        with self.success() as run:
            result = worker.execute({'action': 'tick'})
            run.assert_not_called()
        self.assertIn('sync disabled', result['error'])
        self.assertIsInstance(json.loads((self.state_dir / 'state.json').read_text()), dict)

    def test_unchanged_state_does_not_write(self):
        path = self.state_dir / 'state.json'
        b.save_state(path, b.defaults())
        stamp = path.stat().st_mtime_ns
        b.save_state(path, b.defaults())
        self.assertEqual(path.stat().st_mtime_ns, stamp)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_bounded_lock_wait(self):
        with (self.state_dir / 'lock').open('w') as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            start = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, 'busy'):
                with b.state_lock(timeout=0.03):
                    self.fail('acquired an already-held lock')
            self.assertLess(time.monotonic() - start, 0.5)

    def test_concurrent_actions_are_serialized(self):
        mutex = threading.Lock()
        active = 0
        peak = 0
        def write(*args, **kwargs):
            nonlocal active, peak
            with mutex:
                active += 1
                peak = max(peak, active)
            time.sleep(0.03)
            with mutex:
                active -= 1
            return subprocess.CompletedProcess([], 0, '', '')
        def execute(zone):
            worker = b.Worker()
            worker.device = self.device
            return worker.execute({'action': 'apply', 'zone': zone, 'config': {'brightness': 42}})
        with patch.object(b.subprocess, 'run', side_effect=write), concurrent.futures.ThreadPoolExecutor(2) as pool:
            results = list(pool.map(execute, ['main', 'side']))
        self.assertEqual(peak, 1)
        self.assertFalse(any(result['error'] for result in results))
        state = b.load_state(self.state_dir / 'state.json')
        self.assertEqual(state['zones']['main']['brightness'], 42)
        self.assertEqual(state['zones']['side']['brightness'], 42)

    def test_theme_watcher_handles_writes_and_symlink_replacement(self):
        parent = self.state_dir / 'current'
        parent.mkdir()
        for name in ['one', 'two']:
            (self.state_dir / name).mkdir()
            (self.state_dir / name / 'keyboard.rgb').write_text('#123456')
        (parent / 'theme').symlink_to(self.state_dir / 'one')
        with patch.object(b, 'THEME', parent / 'theme/keyboard.rgb'):
            watcher = w.Watcher()
            try:
                b.THEME.write_text('#abcdef')
                self.assertIn('theme', watcher.drain())
                (parent / 'next').symlink_to(self.state_dir / 'two')
                (parent / 'next').replace(parent / 'theme')
                self.assertIn('theme', watcher.drain())
                watcher.arm()
                watcher.drain()
                b.THEME.write_text('#fedcba')
                self.assertIn('theme', watcher.drain())
                self.assertLessEqual(len(watcher.kinds), 5)
            finally:
                watcher.close()


if __name__ == '__main__':
    unittest.main()
