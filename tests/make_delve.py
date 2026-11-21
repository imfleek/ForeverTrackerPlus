# Run from the repo root: python tests/make_delve.py [preview.png] (dev-only; tests/ is not shipped).
# The dungeon card's art, in the look of Blizzard's Delves card in the objective tracker (user's reference: a dark
# brown rounded card with a thin bronze edge, and a dark banner with a gold edge and a notched bottom at its top right):
#   Textures/DelveCard.tga   64x64: the card, drawn in nine slices (corners CORNER texels: Dungeon.lua CARD_CORNER)
#   Textures/DelveBanner.tga 32x48: the banner that shows the party's size
# 4x4 supersampling, 32-bit TGA.
import math, os, struct, sys

SS = 4

def mix(a, b, k): return tuple(x + (y - x) * k for x, y in zip(a, b))

def render(w, h, fn):
    px = []
    for y in range(h):
        for x in range(w):
            acc, n = [0.0, 0.0, 0.0, 0.0], SS * SS
            for sy in range(SS):
                for sx in range(SS):
                    c = fn(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    if c:
                        acc[0] += c[0] * c[3]; acc[1] += c[1] * c[3]; acc[2] += c[2] * c[3]; acc[3] += c[3]
            px.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n) if acc[3] else (0, 0, 0, 0))
    return px

def tga(path, w, h, px):
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8 | 0x20))
        for r, g, b, a in px:
            f.write(bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(a * 255)))))

# --- the card: 64x64, rounded corners (radius 7), a dark outer line, a bronze edge, a dark brown inside a little
# lighter at the top; the middle is even so the nine-slice middle can stretch
CW = 64
RADIUS = 7.0
OUTER, EDGE = 1.0, 1.5
DARK = (0.04, 0.03, 0.02)
BRONZE = (0.55, 0.42, 0.24)
INSIDE_TOP, INSIDE = (0.16, 0.115, 0.08), (0.10, 0.075, 0.055)

def rounded_dist(x, y, w, h, r):
    # distance inside the rounded rectangle's edge (negative outside)
    dx, dy = min(x, w - x), min(y, h - y)
    if dx < r and dy < r:
        return r - math.hypot(r - dx, r - dy)
    return min(dx, dy)

def card(x, y):
    d = rounded_dist(x, y, CW, CW, RADIUS)
    if d < 0: return None
    if d < OUTER: return DARK + (0.95,)
    if d < OUTER + EDGE: return BRONZE + (1.0,)
    # the top 16 texels lighter (the top slice); the even middle below
    k = min(max((y - 3) / 13.0, 0.0), 1.0)
    return mix(INSIDE_TOP, INSIDE, k) + (0.92,)

# --- the banner: 32x64, a straight top, a V notch at the bottom, a gold edge and a dark outer line
BW, BH = 32, 48
NOTCH = 7.0
MAROON_TOP, MAROON = (0.30, 0.14, 0.09), (0.20, 0.09, 0.06)
GOLD = (0.86, 0.66, 0.26)

def banner_inside(x, y, inset):
    if x < 2 + inset or x > BW - 2 - inset or y < inset: return False
    # the bottom edge: from the sides at BH - NOTCH down... a V cut upwards in the middle
    bottom_side = BH - 1 - inset
    cut = (BH - 1 - NOTCH) + abs(x - BW / 2) / (BW / 2 - 2) * NOTCH - inset * 1.4
    return y <= min(bottom_side, cut)

def banner(x, y):
    if not banner_inside(x, y, 0): return None
    if not banner_inside(x, y, 1.0): return DARK + (1.0,)
    if not banner_inside(x, y, 3.0): return GOLD + (1.0,)
    if not banner_inside(x, y, 4.0): return DARK + (1.0,)
    return mix(MAROON_TOP, MAROON, min(y / BH, 1.0)) + (1.0,)

cardpx = render(CW, CW, card)
tga("Textures/DelveCard.tga", CW, CW, cardpx)
bannerpx = render(BW, BH, banner)
tga("Textures/DelveBanner.tga", BW, BH, bannerpx)

# --- the eye (R106-89): 32x32, open (DungeonJournal's part of the card shown) and closed (hidden); light gold lines
# with a dark outline, as the card's other small icons
EW = 32
EYE = (0.95, 0.82, 0.45)
IRIS = (0.55, 0.40, 0.18)

def lid(x, top):
    # the almond's upper (top=True) or lower lid height at x: a parabola from the corners (4 and 28) to the middle
    t = (x - 16) / 12.0
    if abs(t) > 1: return None
    h = 9.0 * (1 - t * t)
    return 16 - h if top else 16 + h

def eye_open(x, y):
    up, down = lid(x, True), lid(x, False)
    if up is None: return None
    d_up, d_down = abs(y - up), abs(y - down)
    edge = min(d_up, d_down)
    r = math.hypot(x - 16, y - 16)
    if edge < 1.2: return EYE + (1.0,)
    if edge < 2.2: return DARK + (1.0,)
    if up < y < down:
        if r < 3.0: return DARK + (1.0,)      # the pupil
        if r < 6.0: return IRIS + (1.0,)
        if r < 7.0: return DARK + (1.0,)
    return None

def eye_closed(x, y):
    # the lower lid as a curve, with three short lashes under it
    down = lid(x, False)
    if down is not None:
        down -= 4
        d = abs(y - down)
        if d < 1.2: return EYE + (1.0,)
        if d < 2.2: return DARK + (1.0,)
    for lx in (10, 16, 22):
        base = lid(lx, False) - 4
        dx = (lx - 16) / 4.0
        # a short stroke from the lid downwards, leaning out
        t = max(0.0, min(1.0, (y - base) / 5.0))
        cx = lx + dx * t
        if base <= y <= base + 5 and abs(x - cx) < 1.0: return EYE + (1.0,)
    return None

tga("Textures/EyeOpen.tga", EW, EW, render(EW, EW, eye_open))
tga("Textures/EyeClosed.tga", EW, EW, render(EW, EW, eye_closed))

if len(sys.argv) > 1:  # preview: the card stretched to 260x96 in nine slices, the banner on it, 2x, on dark grey
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    W, H, C = 260, 96, 16
    def card_at(x, y):
        def src(v, size, out):
            if v < C: return v
            if v >= out - C: return size - (out - v)
            return C + (v - C) * (size - 2 * C) / max(out - 2 * C, 1)
        sx, sy = int(src(x, CW, W)), int(src(y, CW, H))
        return cardpx[min(sy, CW - 1) * CW + min(sx, CW - 1)]
    rows = []
    for y in range(H * 2):
        row = []
        for x in range(W * 2):
            r, g, b, a = card_at(x // 2, y // 2)
            bx, by = x // 2 - (W - 10 - BW + 4), y // 2 + 2
            if 0 <= bx < BW and 0 <= by < BH and by < BH:
                br, bg_, bb, ba = bannerpx[by * BW + bx]
                r, g, b = r + (br - r) * ba, g + (bg_ - g) * ba, b + (bb - b) * ba
                a = max(a, ba)
            row.append((int(r * 255), int(g * 255), int(b * 255), int(a * 255)))
        rows.append(row)
    png.write(sys.argv[1], W * 2, H * 2, rows, bg=40)
print("wrote Textures/DelveCard.tga, DelveBanner.tga, EyeOpen.tga, EyeClosed.tga")
