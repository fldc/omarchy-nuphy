import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest


class WorkerIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nuphy-worker-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.theme = self.root / '.local/state/omarchy/current/theme/keyboard.rgb'
        self.theme.parent.mkdir(parents=True)
        self.theme.write_text('#123456')
        binary = self.root / 'bin'
        binary.mkdir()
        # Never access real HID hardware in worker integration tests.
        cli = binary / 'nuphyctl'
        cli.write_text('#!' + sys.executable + '\nimport os,sys\n'
                       'with open(os.environ["NUPHY_TEST_LOG"], "a") as f: f.write(" ".join(sys.argv[1:]) + "\\n")\n'
                       'if sys.argv[1:] != ["list"]: sys.exit(77)\n')
        cli.chmod(0o700)
        self.log = self.root / 'cli.log'
        self.env = dict(os.environ, HOME=str(self.root), XDG_STATE_HOME=str(self.root / 'state'),
                        PATH=str(binary) + os.pathsep + os.environ['PATH'], NUPHY_TEST_LOG=str(self.log))
        self.script = Path(__file__).parents[1] / 'nuphy_worker.py'
        self.process = subprocess.Popen([sys.executable, '-u', str(self.script)], env=self.env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.addCleanup(self.stop)
        self.initial = self.receive()

    def stop(self):
        p = self.process
        if p.poll() is None:
            p.stdin.close()
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=3)
        for stream in [p.stdin, p.stdout, p.stderr]:
            if not stream.closed:
                stream.close()

    def receive(self, timeout=5):
        ready, _, _ = select.select([self.process.stdout], [], [], timeout)
        self.assertTrue(ready, 'Timed out waiting for worker output')
        line = self.process.stdout.readline()
        self.assertTrue(line, 'Worker exited unexpectedly')
        return json.loads(line)

    def request(self, value):
        self.process.stdin.write((json.dumps(value) + '\n').encode())
        while True:
            result = self.receive()
            if result.get('requestId') == value.get('id'):
                return result

    def test_protocol_status_does_not_enumerate_or_write(self):
        self.assertFalse(self.initial['connected'])
        for number in range(5):
            result = self.request({'action': 'status', 'id': number})
            self.assertEqual(result['theme'], '#123456')
        self.assertEqual(self.log.read_text().splitlines(), ['list'])

    def test_theme_event_updates_without_subprocess(self):
        self.theme.write_text('#abcdef')
        result = self.receive()
        self.assertEqual(result['theme'], '#abcdef')
        self.assertEqual(self.log.read_text().splitlines(), ['list'])

    def test_apply_without_device_never_runs_rgb_command(self):
        result = self.request({'action': 'apply', 'zone': 'main', 'config': {}, 'id': 1})
        self.assertIn('NuPhy control interface', result['error'])
        self.assertTrue(all(line == 'list' for line in self.log.read_text().splitlines()))

    def test_second_worker_cannot_start(self):
        other = subprocess.run([sys.executable, str(self.script)], env=self.env, input='',
            capture_output=True, text=True, timeout=5)
        self.assertNotEqual(other.returncode, 0)
        self.assertIn('already running', other.stderr)

    def test_idle_worker_does_not_spawn_helpers(self):
        # Wait across the old 3-second polling interval and inspect actual CPU ticks.
        def ticks():
            fields = Path(f'/proc/{self.process.pid}/stat').read_text().split()
            return int(fields[13]) + int(fields[14])
        before = ticks()
        ready, _, _ = select.select([self.process.stdout], [], [], 3.2)
        self.assertFalse(ready, 'Idle worker emitted an unexpected update')
        self.assertLessEqual(ticks() - before, 2)
        self.assertEqual(self.log.read_text().splitlines(), ['list'])

    def test_invalid_request_does_not_kill_worker(self):
        self.process.stdin.write(b'{broken\n')
        self.assertTrue(self.receive()['protocolError'])
        result = self.request({'action': 'status', 'id': 9})
        self.assertIn('zones', result)


if __name__ == '__main__':
    unittest.main()
