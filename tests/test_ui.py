"""Run real QML components in an isolated, offscreen Quickshell instance."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class UiTests(unittest.TestCase):
    def test_editor_behavior(self):
        omarchy = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))
        shell = omarchy / 'shell'
        if not shutil.which('quickshell') or not (shell / 'Commons').is_dir():
            self.skipTest('Requires Quickshell and Omarchy shell components')
        with tempfile.TemporaryDirectory(prefix='nuphy-ui-') as directory:
            root = Path(directory)
            for name in ['Commons', 'Ui']:
                (root / name).symlink_to(shell / name, target_is_directory=True)
            tests = Path(__file__).parent.resolve()
            (root / 'shell.qml').write_text('import Quickshell\nimport "' + tests.as_uri() + '" as Tests\nShellRoot { Tests.Smoke {} }\n')
            process = subprocess.run(['quickshell', '--path', str(root), '--no-color'],
                env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QS_NO_RELOAD='1'),
                capture_output=True, text=True, timeout=15)
            output = process.stdout + process.stderr
            self.assertEqual(process.returncode, 0, output)
            self.assertIn('NuPhy UI smoke passed', output)
            self.assertNotIn('TypeError', output)
            self.assertNotIn('ReferenceError', output)


if __name__ == '__main__':
    unittest.main()
