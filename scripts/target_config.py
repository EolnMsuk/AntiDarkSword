#!/usr/bin/env python3
import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = json.loads((ROOT / 'config/targets.json').read_text(encoding='utf-8'))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('target', choices=TARGETS)
    parser.add_argument('field', choices=('fields', 'sdk', 'minimum', 'scheme', 'package_arch', 'framework'))
    args = parser.parse_args()
    spec = TARGETS[args.target]
    if args.field == 'fields':
        print(spec['sdk'], spec['minimum'], ','.join(spec['archs']), spec['scheme'] or '-', spec['package_arch'])
    else:
        print(spec[args.field] or '')
