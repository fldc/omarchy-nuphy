"""Isolated worker and stateful CLI; never opens HID devices."""
import json
import os
from pathlib import Path
import shutil
import sys


def prepare(root):
    source = Path(__file__).parents[1]
    for name in ['nuphy_worker.py', 'nuphy_backend.py', 'nuphy_keymap.py', 'nuphy_io.py']:
        shutil.copy(source / name, root / name)
    node = root / 'fake-device'
    node.touch()
    device = dict(path=str(node), vid=6645, pid=4136, iface=3, page=1, usage=0,
                  name='NuPhy Test', serial='test-unique-123')
    with (root / 'nuphy_backend.py').open('a') as out:
        out.write('\n# Test-only discovery; this copy never enumerates real hardware.\n')
        out.write('def discover_device():\n    device = ' + repr(device) + '\n    device["identity"] = device_identity(device)\n    return device\n')
    data = root / 'keys.json'
    data.write_text('[4,5,6,7]')
    binary = root / 'bin'
    binary.mkdir(exist_ok=True)
    cli = binary / 'nuphyctl'
    cli.write_text('#!' + sys.executable + '\n' + '''import json,os,sys,tomllib,struct
from pathlib import Path
args=sys.argv[1:]
root=Path(os.environ['NUPHY_FIXTURE'])
with (root/'commands.jsonl').open('a') as log: log.write(json.dumps(args)+'\\n')
assert args[0]=='keymap', args
command=args[1]
if command!='keycodes':
    assert all(flag in args for flag in ['--path','--vid','--pid','--iface','--usage-page','--usage'])
    assert args[args.index('--path')+1]==str(root/'fake-device')
path=root/'keys.json'
values=json.loads(path.read_text())
if command=='info':
    result=dict(product='NuPhy Test',layer_count=2,layers_per_mode=1,matrix=dict(rows=1,cols=2),extra_entries=0,current_mode=dict(mode=0))
elif command=='keycodes': result={'keycodes':[dict(name='A',value=4,group='basic'),dict(name='B',value=5,group='basic')]}
elif command=='dump':
    if '--raw-out' in args: Path(args[args.index('--raw-out')+1]).write_bytes(struct.pack('<4H',*values))
    if '--defaults' in args: values=[4,5,6,7]
    result={'layers':[{'layer':l,'keys':[dict(index=i,value=values[l*2+i],position=str(i)) for i in range(2)]} for l in range(2)]}
elif command=='apply':
    config=tomllib.loads(Path(args[2]).read_text())
    partial=(root/'partial').exists()
    for layer,keys in config['layers'].items():
        for index,value in keys.items():
            values[int(layer)*2+int(index[1:])]=value
            path.write_text(json.dumps(values))
            if partial: sys.exit('simulated partial write')
    result={'verified':True}
else: raise AssertionError(command)
print(json.dumps(result))
''')
    cli.chmod(0o700)
    return dict(os.environ, NUPHY_FIXTURE=str(root), NUPHY_TEST_WORKER=str(root / 'nuphy_worker.py'),
                PATH=str(binary) + os.pathsep + os.environ['PATH'], XDG_STATE_HOME=str(root / 'state'))
