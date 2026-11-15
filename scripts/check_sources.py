#!/usr/bin/env python3
"""Syntax-only libclang check of the actual PreferenceLoader .m source list.

Requires the supplied Windows libclang/SDK references, plus the downloaded Theos
headers and matching LLVM C11 header. No package, Logos, linking, signing, or
device compatibility validation.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / '.theos-toolchain/python'))
from clang import cindex

sdk = ROOT / '.theos-toolchain/iPhoneOS16.5.sdk'
headers = ROOT / '.build-references/headers/headers-e1132e2bbc3ca15c50e2311bcd349cb7353409e1'
if not sdk.is_dir() or not (headers / 'Preferences/PSListController.h').is_file():
    raise SystemExit('SDK or downloaded pinned Theos headers missing; see docs/building.md')
makefile = (ROOT / 'antidarkswordprefs/Makefile').read_text(encoding='utf-8')
match = re.search(r'^AntiDarkSwordPrefs_FILES = (.+)$', makefile, re.M)
sources = [ROOT / 'antidarkswordprefs' / name for name in match[1].split()]
if len(sources) != 6 or any(path.suffix != '.m' or not path.is_file() for path in sources):
    raise SystemExit('Expected the six actual PreferenceLoader Objective-C sources')
args = ['-target', 'arm64-apple-ios13.0', '-isysroot', str(sdk),
        '-resource-dir', str(ROOT / '.theos-toolchain/clang-resource'),
        '-fobjc-arc', '-fblocks', '-x', 'objective-c', '-Wall', '-Wextra',
        '-Wno-unused-parameter', '-Wno-deprecated-declarations',
        '-I' + str(ROOT / '.build-references/clang-18/include'),
        '-I' + str(headers), '-F' + str(ROOT / 'vendor')]
index = cindex.Index.create()
failed = False
for source in sources:
    unit = index.parse(str(source), args=args)
    diagnostics = list(unit.diagnostics)
    errors = [d for d in diagnostics if d.severity >= cindex.Diagnostic.Error]
    warnings = [d for d in diagnostics if d.severity == cindex.Diagnostic.Warning]
    print(f'{source.relative_to(ROOT)}: {len(errors)} errors, {len(warnings)} warnings')
    for diagnostic in diagnostics:
        if diagnostic.severity >= cindex.Diagnostic.Warning:
            print(diagnostic)
    failed |= bool(errors)
print(f'Checked {len(sources)} actual .m files; no Logos/link/package/device check was run.')
sys.exit(1 if failed else 0)
