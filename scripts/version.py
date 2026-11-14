#!/usr/bin/env python3
"""Read the release version from control; synchronize only explicit mirrors."""
import argparse
import json
import os
import pathlib
import plistlib
import re
import stat
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION_RE = re.compile(r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', re.ASCII)

def read_version(control=None):
    path = control if control is not None else ROOT / 'control'
    values = re.findall(r'^Version:[ \t]*(.*)$', path.read_text(encoding='utf-8'), re.M | re.I)
    if len(values) != 1 or not VERSION_RE.fullmatch(values[0]) or len(values[0]) > 96:
        raise ValueError('control must contain exactly one Version: major.minor.patch field (decimal numbers only)')
    return values[0]

def release_notes(version):
    text = (ROOT / 'changelog.md').read_text(encoding='utf-8')
    sections = list(re.finditer(r'^## ([^\n]+)\n', text, re.M))
    if not sections or sections[0].group(1).strip() != version:
        raise ValueError('The current changelog heading must match control')
    end = sections[1].start() if len(sections) > 1 else len(text)
    return text[sections[0].start():end].strip()

def atomic_write(path, data, mode=None):
    existing_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    desired_mode = existing_mode if mode is None else mode
    if path.exists() and path.read_bytes() == data:
        if mode is not None and existing_mode != desired_mode:
            path.chmod(desired_mode)
        return
    fd, temp = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(temp, desired_mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

def mirrors(version):
    plist_path = ROOT / 'antidarkswordprefs/Resources/Info.plist'
    raw = plist_path.read_bytes()
    info = plistlib.loads(raw)
    expected = dict(info, CFBundleShortVersionString=version, CFBundleVersion=version)
    # Preserve this XML's layout and unrelated keys; validate the scoped replacement
    # against the structured representation before accepting it.
    xml = raw.decode('utf-8')
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        xml, count = re.subn(r'(<key>' + key + r'</key>\s*<string>)[^<]*(</string>)',
                             lambda m: m[1] + version + m[2], xml)
        if count != 1:
            raise ValueError(f'Expected exactly one {key} in preferences metadata')
    assert plistlib.loads(xml.encode('utf-8')) == expected

    depiction_path = ROOT / 'depiction.json'
    depiction = json.loads(depiction_path.read_text(encoding='utf-8'))
    info_tabs = [tab for tab in depiction['tabs'] if tab['tabname'] == 'Information']
    if len(info_tabs) != 1:
        raise ValueError('Expected one Information tab')
    versions = [view for view in info_tabs[0]['views'] if view.get('title') == 'Version']
    if len(versions) != 1:
        raise ValueError('Expected one depiction Version row')
    versions[0]['text'] = version
    changes = [tab for tab in depiction['tabs'] if tab['tabname'] == 'Changelog']
    if (ROOT / 'changelog.md').exists() or changes:
        if len(changes) != 1 or [t['tabname'] for t in depiction['tabs']][:3] != ['Details', 'Changelog', 'Information']:
            raise ValueError('Depiction tabs must be Details, Changelog, Information')
        markdown = [view for view in changes[0]['views'] if view.get('class') == 'DepictionMarkdownView']
        if len(markdown) != 1:
            raise ValueError('Expected one Changelog markdown view')
        markdown[0]['markdown'] = release_notes(version)
    return {
        plist_path: xml.encode('utf-8'),
        depiction_path: (json.dumps(depiction, indent=2, ensure_ascii=False) + '\n').encode('utf-8'),
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('print', 'sync', 'check', 'notes'))
    args = parser.parse_args()
    try:
        version = read_version()
        if args.mode == 'print':
            print(version)
        elif args.mode == 'notes':
            print(release_notes(version))
        else:
            expected = mirrors(version)
            drift = [path for path, data in expected.items() if path.read_bytes() != data]
            if args.mode == 'sync':
                for path in drift:
                    atomic_write(path, expected[path])
                print(f'Synchronized metadata to {version} ({len(drift)} files changed)')
            elif drift:
                raise ValueError('Metadata drift: ' + ', '.join(str(p.relative_to(ROOT)) for p in drift))
            else:
                print(f'Metadata matches control ({version})')
    except (ValueError, OSError, KeyError, TypeError, plistlib.InvalidFileException) as exc:
        print(f'Version error: {exc}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
