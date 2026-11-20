# Minimal PNG reader/writer (8-bit RGB / RGBA, non-interlaced) without PIL.
import struct, zlib

def read(path):
    d = open(path, 'rb').read()
    i, idat, w = 8, b'', None
    while i < len(d):
        n = struct.unpack('>I', d[i:i + 4])[0]
        t = d[i + 4:i + 8]
        body = d[i + 8:i + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and ctype in (2, 6)
            bpp = 3 if ctype == 2 else 4
        elif t == b'IDAT':
            idat += body
        i += 12 + n
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[pos]; line = bytearray(raw[pos + 1:pos + 1 + stride]); pos += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pp = a + b - c; pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    px = [[tuple(r[x * bpp:x * bpp + 3]) + ((r[x * bpp + 3],) if bpp == 4 else (255,)) for x in range(w)] for r in rows]
    return w, h, px

def write(path, w, h, px, bg=None):
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            r, g, b, a = px[y][x]
            if bg is not None:
                al = a / 255
                row += bytes((int(r * al + bg * (1 - al)), int(g * al + bg * (1 - al)), int(b * al + bg * (1 - al))))
            else:
                row += bytes((r, g, b, a))
        rows.append(bytes(row))
    ctype = 2 if bg is not None else 6
    def chunk(t, data): return struct.pack('>I', len(data)) + t + data + struct.pack('>I', zlib.crc32(t + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, ctype, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)
