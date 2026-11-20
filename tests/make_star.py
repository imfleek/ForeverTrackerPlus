# Run from the repo root: python tests/make_star.py [preview.png] (dev-only; tests/ is not shipped).
# Textures/Star.tga (64x64, 32-bit): the star for raid attunement quests, in the look of the friends list's favourite
# star (user; the game's small atlas "friendslist-favorite" was blurry when drawn at the icons' size): a five-pointed
# gold star, lighter at the top and warmer at the bottom, with a thin dark outline so it reads on any background.
# The star fills the image as the other icons fill theirs (centred, about 94 % tall). 4x4 supersampling.
import math, os, struct, sys

N, SS = 64, 4
TOP, BOTTOM = (1.00, 0.90, 0.40), (0.95, 0.60, 0.10)   # the gold, top to bottom
HIGHLIGHT = (1.00, 0.97, 0.75)                          # a soft light in the upper middle
EDGE = (0.22, 0.12, 0.02)
OUT = 2.6                                               # outline width, in pixels of the 64
R_OUT, R_IN = 29.0, 12.2                                # the points' and the notches' radius
CX = 32.0
# vertically centred on its own extent (a star's top point reaches further than its bottom points)
CY = 32.0 + (R_OUT - R_OUT * math.cos(math.radians(36))) / 2

pts = []
for i in range(10):
    a = math.radians(-90 + i * 36)
    r = R_OUT if i % 2 == 0 else R_IN
    pts.append((CX + r * math.cos(a), CY + r * math.sin(a)))
edges = [(pts[i], pts[(i + 1) % 10]) for i in range(10)]

def inside(p):
    # even-odd crossing test
    x, y = p
    c = False
    for (x1, y1), (x2, y2) in edges:
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c

def seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / (ax * ax + ay * ay)))
    return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * ay)

def mix(a, b, k): return tuple(x + (y - x) * k for x, y in zip(a, b))

def colour(p):
    d = min(seg_dist(p, a, b) for a, b in edges)
    if inside(p):
        if d < OUT * 0.5: return EDGE
        k = max(0.0, min(1.0, (p[1] - (CY - R_OUT)) / (2 * R_OUT)))
        c = mix(TOP, BOTTOM, k)
        h = max(0.0, 1 - math.hypot(p[0] - CX, p[1] - (CY - 6)) / 14)
        return mix(c, HIGHLIGHT, 0.5 * h * h)
    if d < OUT * 0.5 + OUT * 0.5: return EDGE
    return None

px = []
for y in range(N):
    for x in range(N):
        acc, a = [0.0, 0.0, 0.0], 0
        for sy in range(SS):
            for sx in range(SS):
                c = colour((x + (sx + 0.5) / SS, y + (sy + 0.5) / SS))
                if c:
                    acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; a += 1
        px.append((acc[0] / a, acc[1] / a, acc[2] / a, a / (SS * SS)) if a else (0, 0, 0, 0))

with open("Textures/Star.tga", "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for r, g, b, a in px:
        f.write(bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(a * 255)))))

if len(sys.argv) > 1:  # preview at 4x on dark grey
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    rows = []
    for y in range(N * 4):
        rows.append([tuple(int(v * 255) for v in px[(y // 4) * N + x // 4]) for x in range(N * 4)])
    png.write(sys.argv[1], N * 4, N * 4, rows, bg=60)
print("wrote Textures/Star.tga")
