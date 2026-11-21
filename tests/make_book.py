# Run from the repo root: python tests/make_book.py [preview.png] (dev-only; tests/ is not shipped).
# Textures/Book.tga (64x64, 32-bit): the dungeon card's DungeonJournal button (R106-98), a closed leather book in the
# look of the game's INV_Misc_Book_09 icon but on a see-through background (user: the game icon's dark square showed
# around it). Brown leather cover with a darker spine and two gold bands, gold corner caps and a gold diamond in the
# middle; cream pages show at the right and the bottom; a thin dark outline so it reads on any background.
# 4x4 supersampling.
import math, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

N, SS = 64, 4
OUT = 2.2                                      # outline width
COVER = (9.0, 6.0, 50.0, 53.0)                 # x0, y0, x1, y1
PAGES = (13.0, 10.0, 55.0, 58.0)
R_COVER, R_PAGES = 4.0, 3.0
SPINE_W = 7.0
EDGE = (0.16, 0.08, 0.03)
LEATHER_TOP, LEATHER_BOTTOM = (0.62, 0.34, 0.16), (0.40, 0.19, 0.08)
SPINE_TOP, SPINE_BOTTOM = (0.42, 0.21, 0.09), (0.27, 0.12, 0.05)
GOLD_LIGHT, GOLD_DARK = (1.00, 0.86, 0.42), (0.78, 0.55, 0.16)
PAPER, PAPER_LINE = (0.95, 0.90, 0.76), (0.74, 0.66, 0.50)

def rrect_dist(x, y, r, rad):
    # signed distance to a rounded rectangle (negative inside)
    x0, y0, x1, y1 = r
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - rad, (y1 - y0) / 2 - rad
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    out = math.hypot(max(qx, 0), max(qy, 0))
    return out + min(max(qx, qy), 0) - rad

def mix(a, b, k): return tuple(p + (q - p) * k for p, q in zip(a, b))

def colour(x, y):
    dc = rrect_dist(x, y, COVER, R_COVER)
    dp = rrect_dist(x, y, PAGES, R_PAGES)
    d = min(dc, dp)
    if d > 0:
        return None
    if d > -OUT:
        return EDGE
    x0, y0, x1, y1 = COVER
    if dc <= 0:
        if dc > -OUT - 0.2:                     # the cover's own edge, over the pages
            return EDGE
        t = (y - y0) / (y1 - y0)
        # gold corner caps on the right
        cs = 10.0
        if (x1 - x) + (y - y0) < cs or (x1 - x) + (y1 - y) < cs:
            return mix(GOLD_LIGHT, GOLD_DARK, t)
        # the spine with two gold bands
        if x < x0 + SPINE_W + OUT:
            if abs(y - (y0 + 11)) < 2.2 or abs(y - (y1 - 11)) < 2.2:
                return mix(GOLD_LIGHT, GOLD_DARK, t)
            if x > x0 + SPINE_W + OUT - 1.4:
                return EDGE
            return mix(SPINE_TOP, SPINE_BOTTOM, t)
        # the diamond in the middle
        cx, cy = (x0 + SPINE_W + x1) / 2 + 1, (y0 + y1) / 2
        dd = abs(x - cx) + abs(y - cy)
        if dd < 9.0:
            if dd > 7.2:
                return EDGE
            if dd < 3.0:
                return mix((0.55, 0.12, 0.08), (0.35, 0.06, 0.04), t)  # a small red stone
            return mix(GOLD_LIGHT, GOLD_DARK, (y - cy + 9) / 18)
        base = mix(LEATHER_TOP, LEATHER_BOTTOM, t)
        # a soft light on the upper left of the cover
        k = max(0.0, 1 - math.hypot(x - (x0 + 18), y - (y0 + 10)) / 26) * 0.18
        return mix(base, (1, 0.85, 0.65), k)
    # the pages: lines along the edges
    px0, py0, px1, py1 = PAGES
    if x > x1 - 1:                              # right edge: vertical lines
        line = int(x) % 2 == 0
    else:                                       # bottom edge: horizontal lines
        line = int(y) % 2 == 0
    return PAPER_LINE if line else PAPER

out = []
for oy in range(N):
    for ox in range(N):
        acc = [0.0, 0.0, 0.0]
        n = 0
        for sy in range(SS):
            for sx in range(SS):
                c = colour(ox + (sx + 0.5) / SS, oy + (sy + 0.5) / SS)
                if c:
                    n += 1
                    acc = [a + b for a, b in zip(acc, c)]
        if n:
            out.append(tuple(v / n * 255 for v in acc) + (n / (SS * SS) * 255,))
        else:
            out.append((0, 0, 0, 0))

with open("Textures/Book.tga", "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for r, g, b, a in out:
        f.write(bytes((int(round(b)), int(round(g)), int(round(r)), int(round(a)))))

if len(sys.argv) > 1:  # preview at 4x on mid grey
    import png
    rows = [[tuple(int(round(v)) for v in out[(y // 4) * N + x // 4]) for x in range(N * 4)] for y in range(N * 4)]
    png.write(sys.argv[1], N * 4, N * 4, rows, bg=110)
print("wrote Textures/Book.tga")
