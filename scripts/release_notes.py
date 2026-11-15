#!/usr/bin/env python3
from version import ROOT, read_version

print('\n' + (ROOT / 'docs/release-compatibility.md').read_text(encoding='utf-8').replace('<version>', read_version()))
