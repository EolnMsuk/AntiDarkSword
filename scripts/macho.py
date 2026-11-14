"""Small read-only Mach-O inspector for build reference and release checks."""
import json
import pathlib
import struct
import sys

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
