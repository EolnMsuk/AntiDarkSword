#!/usr/bin/env python3
"""Validate and copy a link-only framework to its target-specific directory."""
import plistlib
import sys
from macho import inspect
from target_config import ROOT, TARGETS
from version import atomic_write, read_version

def copy_atomic(source, destination):
    for path in source.rglob('*'):
        if path.is_file():
            target = destination / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            atomic_write(target, path.read_bytes(), mode=0o644)

def prepare(target):
    spec = TARGETS[target]
    source = ROOT / 'vendor' / spec['framework']
    slices = inspect((source / 'AltList').read_bytes())
    minimum = tuple(map(int, spec['minimum'].split('.'))) + (0,)
    supported = [s for s in slices if s['cpu'] == 0x100000c and tuple(s['minimum']) <= minimum]
    needed = {0} if target == 'legacy' else {0, 2}
    if not needed <= {s['subtype'] & 0xffffff for s in supported}:
        raise ValueError('AltList CPU slices/deployment target do not match the selected target')
    expected_id = ('@loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList' if target == 'roothide'
                   else '/Library/Frameworks/AltList.framework/AltList' if target == 'legacy'
                   else '@rpath/AltList.framework/AltList')
    if any(s['id'] != expected_id for s in supported):
        raise ValueError('Unexpected AltList install ID')
    destination = ROOT / '.build' / target / 'references/AltList.framework'
    copy_atomic(source, destination)
    resources = ROOT / '.build' / target / 'preferences-resources'
    for path in (ROOT / 'antidarkswordprefs/Resources').iterdir():
        if not path.is_file():
            raise ValueError('Unexpected nested preferences resource; update the explicit preparation logic')
        resources.mkdir(parents=True, exist_ok=True)
        if path.name == 'Info.plist':
            info = plistlib.loads(path.read_bytes())
            version = read_version()
            if info['CFBundleShortVersionString'] != version or info['CFBundleVersion'] != version:
                raise ValueError('Run version.py sync before preparing resources')
            info['MinimumOSVersion'] = spec['minimum']
            data = plistlib.dumps(info, sort_keys=False)
        else:
            data = path.read_bytes()
        atomic_write(resources / path.name, data, mode=0o644)
    return destination.parent

if __name__ == '__main__':
    print(prepare(sys.argv[1]))
