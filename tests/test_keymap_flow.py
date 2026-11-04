import json
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest
from keymap_fixture import prepare


class FlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = prepare(self.root)
        self.worker = subprocess.Popen([sys.executable, '-u', self.env['NUPHY_TEST_WORKER']],
            env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.stop)
        self.read()
        self.state = self.request('keymap-load')['keymap']

    def stop(self):
        self.worker.stdin.close()
        try:
            self.worker.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.worker.kill()
            self.worker.wait()
        self.worker.stdout.close()
        self.worker.stderr.close()

    def read(self):
        self.assertTrue(select.select([self.worker.stdout], [], [], 5)[0])
        line = self.worker.stdout.readline()
        self.assertTrue(line)
        return json.loads(line)

    def request(self, action, changes=None):
        payload = {'id': 99, 'action': action, 'config': {'identity': getattr(self, 'state', {}).get('identity'), 'changes': changes}}
        self.worker.stdin.write((json.dumps(payload)+'\n').encode())
        self.worker.stdin.flush()
        while True:
            value = self.read()
            if value.get('requestId') == 99:
                return value

    def test_real_cli_batch_backup_and_conflict(self):
        changes = [dict(layer=0,index=0,original=4,value=9),dict(layer=1,index=1,original=7,value=10)]
        state = self.request('keymap-apply', changes)['keymap']
        self.assertEqual(json.loads((self.root/'keys.json').read_text()), [9,5,6,10])
        self.assertEqual(Path(state['backup']).read_bytes(), b'\x04\0\x05\0\x06\0\x07\0')
        (self.root/'keys.json').write_text('[8,5,6,10]')
        state = self.request('keymap-apply', changes)['keymap']
        self.assertEqual(state['errorKind'], 'conflict')
        self.assertEqual(state['conflicts'][0]['current'], 8)
        self.assertEqual(json.loads((self.root/'keys.json').read_text()), [8,5,6,10])

    def test_partial_write_reads_back_and_never_retries(self):
        (self.root/'partial').touch()
        changes = [dict(layer=0,index=0,original=4,value=9),dict(layer=1,index=1,original=7,value=10)]
        state = self.request('keymap-apply', changes)['keymap']
        self.assertTrue(state['known'])
        self.assertEqual(state['errorKind'], 'write')
        self.assertEqual(state['keys']['0:0']['value'], 9)
        self.assertEqual(state['keys']['1:1']['value'], 7)
        self.request('status')
        commands = [json.loads(line) for line in (self.root/'commands.jsonl').read_text().splitlines()]
        self.assertEqual(sum(c[1]=='apply' for c in commands), 1)

    def test_new_external_edit_conflicts_after_resolution(self):
        changes = [dict(layer=0,index=0,original=4,value=9)]
        (self.root/'keys.json').write_text('[8,5,6,7]')
        self.assertEqual(self.request('keymap-apply', changes)['keymap']['errorKind'], 'conflict')
        changes[0]['original'] = 8
        (self.root/'keys.json').write_text('[10,5,6,7]')
        state = self.request('keymap-apply', changes)['keymap']
        self.assertEqual(state['conflicts'][0]['current'], 10)
        self.assertEqual(json.loads((self.root/'keys.json').read_text()), [10,5,6,7])
