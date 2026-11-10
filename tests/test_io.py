"""Adversarial I/O fixtures: bounded reads, real subprocesses, no HID access."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import nuphy_backend as backend
import nuphy_io as io


class IoTests(unittest.TestCase):
    def test_output_caps_apply_while_both_streams_are_produced(self):
        for stream in (1, 2):
            with self.subTest(stream=stream):
                script = f'import os\nwhile True: os.write({stream}, b"x" * 65536)'
                start = time.monotonic()
                with self.assertRaisesRegex(ValueError, 'output limit'):
                    io.run_command([sys.executable, '-c', script], timeout=3, limit=8192)
                self.assertLess(time.monotonic() - start, 2)

    def test_deadline_covers_silent_and_continuously_streaming_producers(self):
        scripts = ['import time; time.sleep(10)',
                   'import os,time\nwhile True:\n os.write(1,b"x"); time.sleep(.02)']
        for script in scripts:
            with self.subTest(script=script):
                start = time.monotonic()
                with self.assertRaises(subprocess.TimeoutExpired):
                    io.run_command([sys.executable, '-c', script], timeout=.15)
                self.assertLess(time.monotonic() - start, 1)

    def test_deadline_covers_descendants_holding_pipes_open(self):
        script = 'import os,time\nif os.fork() == 0: time.sleep(10)'
        with self.assertRaises(subprocess.TimeoutExpired):
            io.run_command([sys.executable, '-c', script], timeout=.15)

    def test_regular_file_bounds_utf8_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'file'
            link = Path(directory) / 'link'
            link.symlink_to(path)
            with self.assertRaises(FileNotFoundError):
                io.read_text(path, 100)
            path.write_text('#abcdef')
            self.assertEqual(io.read_text(link, 7), '#abcdef')
            with self.assertRaises(OSError):
                io.read_text(path, 6)
            path.write_bytes(b'\xff')
            with self.assertRaises(OSError):
                io.read_text(path, 100)
            with self.assertRaises(OSError):
                io.read_text(Path(directory), 100)

    def test_fifo_and_device_reads_are_rejected_without_waiting(self):
        with tempfile.TemporaryDirectory() as directory:
            fifo = Path(directory) / 'fifo'
            os.mkfifo(fifo)
            for path in (fifo, Path('/dev/zero')):
                start = time.monotonic()
                with self.assertRaises(OSError):
                    io.read_text(path, 128)
                self.assertLess(time.monotonic() - start, .8)
            with patch.object(backend, 'THEME', fifo):
                self.assertEqual(backend.theme_color(), '')
            state = backend.load_state(fifo)
            self.assertIn('sync disabled', state['error'])
            self.assertFalse(any(z['sync'] for z in state['zones'].values()))
            # Saving over a special file must not read/block on it for comparison.
            os.mkfifo(fifo)
            backend.save_state(fifo, backend.defaults())
            self.assertFalse(backend.load_state(fifo)['error'])

    def test_clipboard_helper_rejects_large_and_stalled_transfers(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'wl-paste'
            for script, expected in [
                ('import os\nwhile True: os.write(1,b"x"*65536)', 'output limit'),
                ('import time; time.sleep(10)', 'timed out'),
            ]:
                executable.write_text('#!' + sys.executable + '\n' + script + '\n')
                executable.chmod(0o700)
                result = subprocess.run([sys.executable, io.__file__, 'paste', 'clipboard'],
                    env=dict(os.environ, PATH=directory), capture_output=True, text=True, timeout=4)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertIn(expected, result.stderr)
