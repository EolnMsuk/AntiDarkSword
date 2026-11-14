"""Read-only Mach-O inspection and slice selection for references/releases."""
import json
import pathlib
import struct
import sys

def extract_slice(data, cpu, subtype):
    """Return one unchanged thin slice, checking its container/header identity."""
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        if len(data) < 8:
            raise ValueError('Truncated fat header')
        wide = data[3] == 0xbf
        count = struct.unpack_from('>I', data, 4)[0]
        record_size = 32 if wide else 20
        table_end = 8 + count * record_size
        if table_end > len(data):
            raise ValueError('Truncated fat architecture table')
        candidates = []
        for i in range(count):
            pos = 8 + i * record_size
            if struct.unpack_from('>II', data, pos) != (cpu, subtype):
                continue
            offset, size = struct.unpack_from('>QQ' if wide else '>II', data, pos + 8)
            if offset < table_end or size < 28 or offset + size > len(data):
                raise ValueError('Invalid selected Mach-O slice range')
            candidates.append(data[offset:offset + size])
        if len(candidates) != 1:
            raise ValueError('Expected exactly one matching Mach-O slice')
        selected = candidates[0]
    else:
        selected = data
    header_size = 32 if selected[:4] == b'\xcf\xfa\xed\xfe' else 28
    if (selected[:4] not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe')
            or len(selected) < header_size):
        raise ValueError('Expected a complete little-endian Mach-O header')
    if struct.unpack_from('<II', selected, 4) != (cpu, subtype):
        raise ValueError('Selected Mach-O CPU/subtype does not match its fat record')
    return selected

def inspect(data):
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = data[3] == 0xbf
        count = struct.unpack_from('>I', data, 4)[0]
        result = []
        for i in range(count):
            pos = 8 + i * (32 if wide else 20)
            offset, size = struct.unpack_from('>QQ' if wide else '>II', data, pos + 8)
            result.extend(inspect(data[offset:offset + size]))
        return result
    if data[:4] not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
        raise ValueError('Expected a little-endian Mach-O')
    cpu, subtype, _, count, *_ = struct.unpack_from('<7I', data, 4)
    info = dict(cpu=cpu, subtype=subtype, id=None, loads=[], rpaths=[], minimum=None)
    pos = 32 if data[:4] == b'\xcf\xfa\xed\xfe' else 28
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', data, pos)
        if size < 8 or pos + size > len(data):
            raise ValueError('Invalid load command')
        kind = cmd & 0x7fffffff
        if kind in (0xc, 0xd, 0x18, 0x1c, 0x1f):
            offset = struct.unpack_from('<I', data, pos + 8)[0]
            text = data[pos + offset:pos + size].split(b'\0', 1)[0].decode('utf-8')
            if kind == 0xd:
                info['id'] = text
            elif kind == 0x1c:
                info['rpaths'].append(text)
            else:
                info['loads'].append(text)
        if kind in (0x25, 0x32):
            ver = struct.unpack_from('<I', data, pos + (12 if kind == 0x32 else 8))[0]
            info['minimum'] = [ver >> 16, (ver >> 8) & 255, ver & 255]
        pos += size
    return [info]

if __name__ == '__main__':
    for name in sys.argv[1:]:
        print(json.dumps(dict(path=name, slices=inspect(pathlib.Path(name).read_bytes())), indent=2))
