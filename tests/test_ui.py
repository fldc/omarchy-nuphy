"""Run real QML components in an isolated, offscreen Quickshell instance."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class UiTests(unittest.TestCase):
    def test_editor_behavior(self):
        self.run_scene("Smoke", "NuPhy UI smoke passed")

    def test_keymap_behavior(self):
        self.run_scene("KeymapSmoke", "NuPhy keymap smoke passed")

    def test_matrix_behavior(self):
        self.run_scene("MatrixSmoke", "NuPhy matrix smoke passed")

    def test_keymap_flow(self):
        self.run_scene("KeymapFlow", "NuPhy keymap flow passed")

    def test_settings_flow(self):
        self.run_scene("SettingsFlow", "NuPhy settings flow passed")

    def test_bounded_paste(self):
        self.run_scene("PasteSmoke", "NuPhy paste smoke passed")

    def test_worker_start_failure_recovery(self):
        self.run_scene("RecoverySmoke", "NuPhy recovery smoke passed")

    def run_scene(self, scene, success):
        omarchy = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))
        shell = omarchy / 'shell'
        if not shutil.which('quickshell') or not (shell / 'Commons').is_dir():
            self.skipTest('Requires Quickshell and Omarchy shell components')
        with tempfile.TemporaryDirectory(prefix='nuphy-ui-') as directory:
            root = Path(directory)
            for name in ['Commons', 'Ui']:
                (root / name).symlink_to(shell / name, target_is_directory=True)
            from keymap_fixture import prepare
            fixture_env = prepare(root)
            binary = root / 'bin'
            binary.mkdir(exist_ok=True)
            cli = binary / 'nuphyctl'
            if scene not in ('KeymapFlow', 'SettingsFlow'): cli.write_text('#!/bin/sh\n[ "$1" = "list" ] || exit 77\n')
            cli.chmod(0o700)
            paste = binary / 'wl-paste'
            paste.write_text('#!/bin/sh\nsleep 0.1\nprintf "#abc"\n')
            paste.chmod(0o700)
            tests = Path(__file__).parent.resolve()
            (root / 'shell.qml').write_text('import Quickshell\nimport "' + tests.as_uri() + '" as Tests\nShellRoot { Tests.' + scene + ' {} }\n')
            process = subprocess.run(['quickshell', '--path', str(root), '--no-color'],
                env=dict(fixture_env, QT_QPA_PLATFORM='offscreen', QS_NO_RELOAD='1', PATH=str(binary) + os.pathsep + os.environ['PATH'], XDG_STATE_HOME=str(root / 'state')),
                capture_output=True, text=True, timeout=15)
            output = process.stdout + process.stderr
            self.assertEqual(process.returncode, 0, output)
            self.assertIn(success, output)
            self.assertNotIn('TypeError', output)
            self.assertNotIn('ReferenceError', output)
            self.assertNotIn('Binding loop detected', output)


if __name__ == '__main__':
    unittest.main()
