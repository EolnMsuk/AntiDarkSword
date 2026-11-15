#!/usr/bin/env python3
"""Prepare an isolated layout BEFORE Theos loads/copies the package scripts."""
import pathlib
import shutil
import re
import sys
from target_config import ROOT, TARGETS
from version import atomic_write, read_version

target = sys.argv[1]
if target not in TARGETS or target == 'trollfools':
    raise SystemExit('A package target is required')
stage = ROOT / '.build' / target / 'layout'
shutil.copytree(ROOT / 'layout', stage, dirs_exist_ok=True)
read_version() # reject invalid authority before producing any package metadata
control = (ROOT / 'control').read_text(encoding='utf-8')
minimum = TARGETS[target]['minimum']
matches = re.findall(r'^Depends: (.+)$', control, re.M)
if len(matches) != 1:
    raise SystemExit('Expected one Depends field in authoritative control')
dependencies = matches[0]
if re.search(r'(^|,)\s*firmware\b', dependencies):
    raise SystemExit('Move environment-specific firmware requirements to targets.json')
if target == 'roothide':
    dependencies, count = re.subn(r'\bcom\.opa334\.altlist\b(?!\s*\()', 'com.opa334.altlist (>= 1.0.11)', dependencies)
    if count != 1:
        raise SystemExit('Review native AltList dependency against the verified reference')
dependencies += f', firmware (>= {minimum})'
control = re.sub(r'^Depends: .+$', lambda _: 'Depends: ' + dependencies, control, flags=re.M)
atomic_write(stage / 'DEBIAN/control', control.encode('utf-8'), mode=0o644)
for name in ('postinst', 'prerm'):
    text = (ROOT / 'layout/DEBIAN' / name).read_text(encoding='utf-8')
    if text.count('@ADS_ENVIRONMENT@') != 1:
        raise SystemExit('Expected exactly one environment token')
    path = stage / 'DEBIAN' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(path, text.replace('@ADS_ENVIRONMENT@', target).encode('utf-8'), mode=0o755)
