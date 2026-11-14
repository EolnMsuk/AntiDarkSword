#!/usr/bin/env python3
"""Collect exactly one versioned product. Never guess with find/head or wildcards."""
import pathlib
import shutil
import subprocess
import sys
from macho import inspect
from target_config import ROOT, TARGETS
from version import read_version

def product_name(target, version):
    return (f'AntiDarkSword_{version}_TrollFools.dylib' if target == 'trollfools'
            else f'com.eolnmsuk.antidarksword_{version}_{target}.deb')

def validate_package(path, target, version):
    for key, expected in [('Package', 'com.eolnmsuk.antidarksword'), ('Version', version),
                          ('Architecture', TARGETS[target]['package_arch'])]:
        actual = subprocess.check_output(['dpkg-deb', '-f', str(path), key], text=True).strip()
        if actual != expected:
            raise ValueError(f'{path.name}: {key} {actual!r}, expected {expected!r}')

def validate_dylib(path):
    slices = inspect(path.read_bytes())
    if {s['subtype'] & 0xffffff for s in slices if s['cpu'] == 0x100000c} != {0, 2}:
        raise ValueError('TrollFools must contain arm64 and arm64e slices')
    if any(s['minimum'] != [15, 0, 0] for s in slices):
        raise ValueError('Unexpected TrollFools deployment target')
    if any('substrate' in dep.lower() or 'roothide' in dep.lower() or '/var/jb/' in dep
           for s in slices for dep in s['loads']):
        raise ValueError('Unexpected jailbreak runtime dependency in TrollFools dylib')

def collect(target):
    spec = TARGETS[target]
    version = read_version()
    build = ROOT / '.build' / target
    if target == 'trollfools':
        # FINALPACKAGE selects release objects without the debug subdirectory.
        source = build / 'theos/AntiDarkSwordTF/obj/AntiDarkSword.dylib'
        validate_dylib(source)
    else:
        source = build / 'packages' / f'com.eolnmsuk.antidarksword_{version}_{spec["package_arch"]}.deb'
        candidates = list((build / 'packages').glob('*.deb'))
        if candidates != [source]:
            raise ValueError(f'Expected exactly {source}; found {candidates}')
        validate_package(source, target, version)
    if source.stat().st_size == 0:
        raise ValueError('Empty build product')
    destination = ROOT / 'output' / product_name(target, version)
    destination.parent.mkdir(exist_ok=True)
    if destination.exists():
        raise ValueError(f'Refusing to overwrite {destination}; move it aside first')
    shutil.copy2(source, destination)
    print(destination)

def verify_release():
    version = read_version()
    expected = {product_name(t, version) for t in TARGETS}
    actual = {p.name for p in (ROOT / 'output').iterdir() if p.is_file()}
    if actual != expected:
        raise ValueError(f'Expected five release assets; missing={expected-actual}, unexpected={actual-expected}')
    for target in TARGETS:
        path = ROOT / 'output' / product_name(target, version)
        if not path.stat().st_size:
            raise ValueError('Empty release asset')
        if target == 'trollfools':
            validate_dylib(path)
        else:
            validate_package(path, target, version)
    print(f'All five release products match control ({version})')

if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == 'verify-release':
        verify_release()
    elif len(sys.argv) == 2 and sys.argv[1] in TARGETS:
        collect(sys.argv[1])
    else:
        raise SystemExit('Usage: collect_product.py <target>|verify-release')
