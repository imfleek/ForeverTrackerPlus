# Run from the repo root: python tests/make_silverstar.py [preview.png] (dev-only; tests/ is not shipped).
# Textures/SilverStar.tga (64x64, 32-bit): the star on a rare's portrait in the dungeon card (R106-90), from the user's
# reference picture tests/art/star_reference.png (a brushed-silver star with a dark navy outline on black). The black
# background is removed: a flood fill of the near-black pixels from the picture's edges (the star's own dark outline is
# a little lighter and bluer, so it stays), with a soft edge where it meets the background; then cropped to the star,
# centred in a square and scaled to 64x64 (premultiplied area sampling).
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png

SRC = "tests/art/star_reference.png"
OUT = "Textures/SilverStar.tga"
N = 64
BLACK = 24     # max channel at or below this, joined to the edges: background
SOFT = 44      # up to this, next to the background: partly see-through (the anti-aliased rim)

w, h, px = png.read(SRC)
mx = [[max(px[y][x][:3]) for x in range(w)] for y in range(h)]

bg = [[False] * w for _ in range(h)]
stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
while stack:
    x, y = stack.pop()
    if x < 0 or y < 0 or x >= w or y >= h or bg[y][x] or mx[y][x] > BLACK:
        continue
    bg[y][x] = True
    stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]

def alpha(x, y):
    if bg[y][x]: return 0.0
    m = mx[y][x]
    if m < SOFT:
        near = any(0 <= x + dx < w and 0 <= y + dy < h and bg[y + dy][x + dx]
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if near: return max(0.0, (m - BLACK) / (SOFT - BLACK))
    return 1.0

# the star's box, made square and centred
xs = [x for y in range(h) for x in range(w) if not bg[y][x]]
ys = [y for y in range(h) for x in range(w) if not bg[y][x]]
x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
side = max(x1 - x0, y1 - y0) + 4
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
sx0, sy0 = cx - side / 2, cy - side / 2

out = []
step = side / N
for oy in range(N):
    for ox in range(N):
        acc = [0.0, 0.0, 0.0, 0.0]
        n = 0
        ya, yb = sy0 + oy * step, sy0 + (oy + 1) * step
        xa, xb = sx0 + ox * step, sx0 + (ox + 1) * step
        for y in range(int(ya), int(yb) + 1):
            for x in range(int(xa), int(xb) + 1):
                n += 1
                if 0 <= x < w and 0 <= y < h:
                    a = alpha(x, y)
                    r, g, b = px[y][x][:3]
                    acc[0] += r * a; acc[1] += g * a; acc[2] += b * a; acc[3] += a
        if acc[3] > 0:
            out.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n * 255))
        else:
            out.append((0, 0, 0, 0))

with open(OUT, "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for r, g, b, a in out:
        f.write(bytes((int(round(b)), int(round(g)), int(round(r)), int(round(a)))))

if len(sys.argv) > 1:  # preview at 4x on mid grey
    rows = []
    for y in range(N * 4):
        rows.append([tuple(int(round(v)) for v in out[(y // 4) * N + x // 4]) for x in range(N * 4)])
    png.write(sys.argv[1], N * 4, N * 4, rows, bg=110)
print("wrote " + OUT)
