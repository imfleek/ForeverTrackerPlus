# Run from the repo root: python tests/make_bar.py [preview.png] (dev-only; tests/ is not shipped).
# The objective progress bar in the look of the reputation frame's bars (user's reference:
# tests/art/repbar_reference.png, colours sampled from it): a thin dark outer line, a bronze metal border (lighter
# along the top), a thin dark inner line and a very dark brown inside (Textures/BarBG.tga); a green fill, brightest in
# the middle and darker towards the top and bottom so it looks round (Textures/BarFill<colour>.tga), inside the inner line.
# Both 128x32, 32-bit TGA; the fill is cropped with SetTexCoord to the progress (Extras.lua drawProgressBar).
import math, os, struct, sys

W, H, SS = 128, 32, 4
OUTER, BRONZE, INNER = 1.5, 3.0, 1.5        # widths of the rings, from the outside in
INSET = OUTER + BRONZE + INNER               # where the inside (and the fill) starts
# the bronze 3 texels on every side (user: the bottom line too thin, then "make both 3"; at half size in game the darker bottom
# bronze nearly vanished): the inside and the fill end this much higher
BOTTOM_EXTRA = 0.0

def in_rect(x, y, inset):
    # inside the box inset by `inset` on the left, top and right, and by inset + BOTTOM_EXTRA at the bottom
    return inset <= x <= W - inset and inset <= y <= H - inset - BOTTOM_EXTRA

DARK_EDGE = (0.10, 0.08, 0.06)
BRONZE_TOP, BRONZE_BOTTOM = (0.68, 0.60, 0.52), (0.49, 0.41, 0.32)   # (173,158,143) .. (125,104,81)
BRONZE_SIDE = (0.62, 0.54, 0.44)
INNER_LINE = (0.04, 0.04, 0.03)
INSIDE = (0.08, 0.04, 0.0)                                         # (20,10,0)
# the fills, edge (top and bottom) .. middle, sampled from the reputation bars (tests/art/repbar_*.png): Hated red,
# Neutral yellow, Friendly green; orange (no reference) between red and yellow; blue from the old progress bars
FILLS = {
    "Red": ((58, 23, 17), (110, 45, 34)),
    "Orange": ((60, 30, 0), (130, 64, 0)),
    "Yellow": ((50, 40, 0), (122, 97, 0)),
    "Green": ((0, 30, 5), (0, 87, 17)),
    "Blue": ((26, 61, 168), (51, 107, 235)),
}

def mix(a, b, k): return tuple(x + (y - x) * k for x, y in zip(a, b))

def edge_dist(x, y):
    # distance to the nearest outer edge, with the corners rounded a little
    dx, dy = min(x, W - x), min(y, H - y)
    r = 2.0
    if dx < r and dy < r:
        return r - math.hypot(r - dx, r - dy)
    return min(dx, dy)

def bg(x, y):
    d = edge_dist(x, y)
    if d < 0: return None
    if d < OUTER: return DARK_EDGE + (1.0,)
    if in_rect(x, y, INSET): return INSIDE + (1.0,)
    if in_rect(x, y, OUTER + BRONZE): return INNER_LINE + (1.0,)
    top = y < H / 2
    vertical = min(x, W - x) > min(y, H - y)        # on the top / bottom edge rather than a side
    col = (BRONZE_TOP if top else BRONZE_BOTTOM) if vertical else BRONZE_SIDE
    return col + (1.0,)

def make_fill(edge, middle):
    edge, middle = tuple(c / 255 for c in edge), tuple(c / 255 for c in middle)
    def fill(x, y):
        if not in_rect(x, y, INSET): return None
        k = (y - INSET) / (H - 2 * INSET - BOTTOM_EXTRA)                     # 0 at the top of the inside, 1 at the bottom
        k = max(0.0, min(1.0, k))
        shade = math.sin(k * math.pi) ** 0.6                   # bright in the middle, darker at the top and bottom
        return mix(edge, middle, shade) + (1.0,)
    return fill

def render(fn):
    px = []
    for py in range(H):
        for x in range(W):
            acc, n = [0.0, 0.0, 0.0, 0.0], SS * SS
            for sy in range(SS):
                for sx in range(SS):
                    c = fn(x + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    if c:
                        acc[0] += c[0] * c[3]; acc[1] += c[1] * c[3]; acc[2] += c[2] * c[3]; acc[3] += c[3]
            px.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n) if acc[3] else (0, 0, 0, 0))
    return px

def tga(path, px):
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8 | 0x20))
        for r, g, b, a in px:
            f.write(bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(a * 255)))))

bgpx = render(bg)
tga("Textures/BarBG.tga", bgpx)
fills = {}
for name, (edge, middle) in FILLS.items():
    fills[name] = render(make_fill(edge, middle))
    tga("Textures/BarFill%s.tga" % name, fills[name])
fillpx = fills["Green"]

if len(sys.argv) > 1:  # preview: the bar at 40 %, 2x, on the reference's grey
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    cut = int(W * 0.4)
    out = []
    for y in range(H * 2):
        row = []
        for x in range(W * 2):
            i = (y // 2) * W + x // 2
            r, g, b, a = bgpx[i]
            if x // 2 < cut and fillpx[i][3] > 0:
                fr, fg, fb, fa = fillpx[i]
                r, g, b = r + (fr - r) * fa, g + (fg - g) * fa, b + (fb - b) * fa
                a = max(a, fa)
            row.append((int(r * 255), int(g * 255), int(b * 255), int(a * 255)))
        out.append(row)
    png.write(sys.argv[1], W * 2, H * 2, out, bg=72)
print("wrote Textures/BarBG.tga, BarFillRed/Orange/Yellow/Green/Blue.tga")
