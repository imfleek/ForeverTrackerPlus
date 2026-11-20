# Run from the repo root: python tests/make_skull.py tests/art/skull_reference.png Textures/Skull.tga (dev-only).
# Textures/Skull.tga from the user's reference picture (a white cartoon skull on a dark square): the dark square is
# removed (flood fill of the near-black background from the picture's edges, so the skull's own dark eyes and nose
# stay), a thin dark outline is drawn back around the skull so it reads on any background, and the result is centred
# and scaled to 64x64 (premultiplied area sampling). Run: python make_skull.py <reference.png> <out.tga> [preview.png]
import sys, struct, math
sys.path.insert(0, __import__('os').path.dirname(__file__))
import png

src, out = sys.argv[1], sys.argv[2]
w, h, px = png.read(src)
lum = [[max(px[y][x][:3]) for x in range(w)] for y in range(h)]

# 1. the background: near-black pixels connected to the border
DARK = 48
bg = [[False] * w for _ in range(h)]
stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
while stack:
    x, y = stack.pop()
    if x < 0 or y < 0 or x >= w or y >= h or bg[y][x] or lum[y][x] > DARK:
        continue
    bg[y][x] = True
    stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]

# 2. the skull: everything else; a soft edge where it meets the background (darker fringe pixels fade out)
rgba = [[(0, 0, 0, 0)] * w for _ in range(h)]
for y in range(h):
    for x in range(w):
        if bg[y][x]:
            continue
        r, g, b, _ = px[y][x]
        touches = any(0 <= x + dx < w and 0 <= y + dy < h and bg[y + dy][x + dx]
                      for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        a = 255
        if touches:
            a = int(min(255, max(0, (lum[y][x] - DARK) * 255 / 90)))
        rgba[y][x] = (r, g, b, a)

# 3. a thin dark outline back around the skull (distance to the nearest opaque pixel)
OUT = 1.6
solid = [(x, y) for y in range(h) for x in range(w) if rgba[y][x][3] > 128]
solidset = set(solid)
final = [row[:] for row in rgba]
for y in range(h):
    for x in range(w):
        if rgba[y][x][3] > 128:
            continue
        best = 9
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if (x + dx, y + dy) in solidset:
                    best = min(best, math.hypot(dx, dy))
        if best <= OUT + 0.5:
            k = max(0.0, min(1.0, OUT + 0.5 - best))
            r, g, b, a = rgba[y][x]
            oa = int(230 * k)
            if oa > a:
                final[y][x] = (10, 10, 12, oa)

# 4. crop to the skull, centre in a square, scale to 64x64
xs = [x for y in range(h) for x in range(w) if final[y][x][3] > 0]
ys = [y for y in range(h) for x in range(w) if final[y][x][3] > 0]
x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
side = max(x1 - x0, y1 - y0) + 2
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
N = 64
res = []
for oy in range(N):
    row = []
    for ox in range(N):
        # the source square this output pixel covers, sampled 4x4 (premultiplied)
        acc = [0.0, 0.0, 0.0, 0.0]
        for sy in range(4):
            for sx in range(4):
                fx = cx - side / 2 + (ox + (sx + 0.5) / 4) * side / N
                fy = cy - side / 2 + (oy + (sy + 0.5) / 4) * side / N
                ix, iy = int(math.floor(fx)), int(math.floor(fy))
                if 0 <= ix < w and 0 <= iy < h:
                    r, g, b, a = final[iy][ix]
                    al = a / 255
                    acc[0] += r * al; acc[1] += g * al; acc[2] += b * al; acc[3] += al
        if acc[3] > 0:
            row.append((int(acc[0] / acc[3]), int(acc[1] / acc[3]), int(acc[2] / acc[3]), int(255 * acc[3] / 16)))
        else:
            row.append((0, 0, 0, 0))
    res.append(row)

with open(out, 'wb') as f:
    f.write(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for row in res:
        for r, g, b, a in row:
            f.write(bytes((b, g, r, a)))
if len(sys.argv) > 3:
    big = [[res[y // 4][x // 4] for x in range(N * 4)] for y in range(N * 4)]
    png.write(sys.argv[3], N * 4, N * 4, big, bg=70)
print('wrote', out)
