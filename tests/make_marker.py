# Run from the repo root: python -I tests/make_marker.py [preview.png] (dev-only; tests/ is not shipped).
# 3.2 world marker art (Tracker/WorldMarker.lua; user: "more polished and good looking", ideas from WaypointUI and a
# reference picture of a gold diamond under a light beam). Our own drawing, no art taken from any addon:
#   Textures/MarkerDiamond.tga (128x128): a gold diamond frame with a bevel (light top-left, dark bottom-right), a thin
#       dark outline, and a dark warm centre for the symbol.
#   Textures/MarkerGem.tga     (64x64):   a small faceted gem for "go here" (light gold; the code tints it).
#   Textures/MarkerBeam.tga    (32x256):  white light beam (the code tints it): a bright core in a soft halo, strong at
#       the bottom and gone at the top.
#   Textures/MarkerGlow.tga    (64x64):   white soft round glow (behind the diamond, and the spark that runs up the beam).
# 4x4 supersampling for the shapes.
import math, os, struct, sys

def mix(a, b, k): return tuple(x + (y - x) * k for x, y in zip(a, b))
def clamp(v, lo=0.0, hi=1.0): return max(lo, min(hi, v))

def write_tga(path, w, h, px):
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8 | 0x20))
        for r, g, b, a in px:
            f.write(bytes((int(round(clamp(b) * 255)), int(round(clamp(g) * 255)), int(round(clamp(r) * 255)),
                           int(round(clamp(a) * 255)))))
    print("wrote " + path)

def supersample(n, colour, ss=4):
    px = []
    for y in range(n):
        for x in range(n):
            acc, a = [0.0, 0.0, 0.0], 0.0
            for sy in range(ss):
                for sx in range(ss):
                    c = colour(x + (sx + 0.5) / ss, y + (sy + 0.5) / ss)
                    if c:
                        al = c[3] if len(c) > 3 else 1.0
                        acc[0] += c[0] * al; acc[1] += c[1] * al; acc[2] += c[2] * al; a += al
            px.append((acc[0] / a, acc[1] / a, acc[2] / a, a / (ss * ss)) if a else (0, 0, 0, 0))
    return px

# ---------------------------------------------------------------- the diamond
GOLD_LIGHT, GOLD_MID, GOLD_DARK = (1.00, 0.93, 0.62), (0.96, 0.74, 0.26), (0.62, 0.38, 0.08)
EDGE = (0.16, 0.08, 0.02)
CENTRE_IN, CENTRE_OUT = (0.30, 0.18, 0.07), (0.09, 0.05, 0.02)
D_N, D_C, D_R = 128, 64.0, 60.0          # size, centre, outer "radius" (|dx| + |dy|)
OUTLINE, FRAME, INNER_LINE = 3.0, 13.0, 2.2

def diamond(x, y):
    dx, dy = x - D_C, y - D_C
    r = abs(dx) + abs(dy)
    if r > D_R: return None
    if r > D_R - OUTLINE: return EDGE
    if r > D_R - OUTLINE - FRAME:
        # the frame: each of the four faces lit by a light from the top left
        k = (r - (D_R - OUTLINE - FRAME)) / FRAME          # 0 inner .. 1 outer edge of the frame
        if dx <= 0 and dy <= 0: base = GOLD_LIGHT          # top left
        elif dx > 0 and dy <= 0: base = mix(GOLD_LIGHT, GOLD_MID, 0.55)
        elif dx <= 0 and dy > 0: base = GOLD_MID
        else: base = GOLD_DARK                              # bottom right
        ridge = 1 - abs(k - 0.45) * 1.6                     # a raised middle line on the frame
        c = mix(base, (1.0, 0.98, 0.85), 0.35 * clamp(ridge))
        return mix(c, GOLD_DARK, 0.25 * clamp(1 - k * 3))   # a little darker where it meets the centre
    if r > D_R - OUTLINE - FRAME - INNER_LINE: return EDGE
    k = clamp(math.hypot(dx, dy + 6) / (D_R - OUTLINE - FRAME))
    return mix(CENTRE_IN, CENTRE_OUT, k)

# ---------------------------------------------------------------- the gem
G_N, G_C, G_R = 64, 32.0, 29.0

def gem(x, y):
    dx, dy = x - G_C, y - G_C
    r = abs(dx) + abs(dy)
    if r > G_R: return None
    if r > G_R - 2.4: return EDGE
    # four facets meeting at a point a little above the middle
    if dx <= 0 and dy <= 0: c = (1.00, 0.97, 0.80)
    elif dx > 0 and dy <= 0: c = (0.98, 0.85, 0.50)
    elif dx <= 0 and dy > 0: c = (0.92, 0.70, 0.28)
    else: c = (0.70, 0.46, 0.12)
    shine = clamp(1 - math.hypot(dx + 8, dy + 8) / 10)
    return mix(c, (1, 1, 1), 0.6 * shine * shine)

# ---------------------------------------------------------------- the beam and the glow (no supersampling: smooth)
B_W, B_H = 32, 256

def beam():
    px = []
    for y in range(B_H):
        t = y / (B_H - 1)                                   # 0 top .. 1 bottom
        fade = t ** 1.6
        for x in range(B_W):
            d = abs(x + 0.5 - B_W / 2)
            core = math.exp(-(d / 2.0) ** 2)
            halo = 0.45 * math.exp(-(d / 6.5) ** 2)
            edge = clamp((B_W / 2 - d) / 3)                 # nothing at the left and right edges
            px.append((1, 1, 1, clamp(core + halo) * fade * edge))
    return px

GL_N = 64

def glow():
    px = []
    for y in range(GL_N):
        for x in range(GL_N):
            d = math.hypot(x + 0.5 - GL_N / 2, y + 0.5 - GL_N / 2) / (GL_N / 2)
            a = clamp(math.exp(-(d / 0.45) ** 2) - 0.02 * d) * clamp((1 - d) * 6)
            px.append((1, 1, 1, a))
    return px

D_PX, G_PX, B_PX, GL_PX = supersample(D_N, diamond), supersample(G_N, gem), beam(), glow()
write_tga("Textures/MarkerDiamond.tga", D_N, D_N, D_PX)
write_tga("Textures/MarkerGem.tga", G_N, G_N, G_PX)
write_tga("Textures/MarkerBeam.tga", B_W, B_H, B_PX)
write_tga("Textures/MarkerGlow.tga", GL_N, GL_N, GL_PX)

if len(sys.argv) > 1:  # a preview of the whole marker, as the code puts it together, on a dusky background
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    W, H = 240, 360
    img = [[[0.20 + 0.10 * y / H, 0.12 + 0.05 * y / H, 0.16, 1.0] for x in range(W)] for y in range(H)]

    def put(src, sw, sh, cx, bottom, dw, dh, tint=(1, 1, 1), add=False, alpha=1.0):
        for y in range(dh):
            for x in range(dw):
                sx, sy = int(x * sw / dw), int(y * sh / dh)
                r, g, b, a = src[sy * sw + sx]
                a *= alpha
                X, Y = cx - dw // 2 + x, bottom - dh + y
                if 0 <= X < W and 0 <= Y < H and a > 0:
                    p = img[Y][X]
                    c = (r * tint[0], g * tint[1], b * tint[2])
                    for i in range(3):
                        p[i] = min(1, p[i] + c[i] * a) if add else p[i] * (1 - a) + c[i] * a

    cx, cy = W // 2, 230
    gold = (1, 0.80, 0.35)
    put(B_PX, B_W, B_H, cx, cy, 26, 210, gold, add=True, alpha=0.85)
    put(GL_PX, GL_N, GL_N, cx, cy + 40, 80, 80, gold, add=True, alpha=0.6)
    put(D_PX, D_N, D_N, cx, cy + 20, 40, 40)
    put(G_PX, G_N, G_N, cx, cy + 8, 16, 16)
    rows = [[tuple(int(clamp(v) * 255) for v in img[y][x][:3]) + (255,) for x in range(W)] for y in range(H)]
    png.write(sys.argv[1], W, H, rows)
    print("wrote " + sys.argv[1])
