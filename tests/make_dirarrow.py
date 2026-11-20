# Run from the repo root: python tests/make_dirarrow.py [preview.png] (dev-only; tests/ is not shipped).
# Textures/DirArrow.tga (64x64, 32-bit): the small arrow after quest titles that points to the quest. Pointing up (Extras.lua
# turnTexture turns it by its texture coordinates). The Forever look of the waypoint arrow's pointer (Textures/arrow_gold.tga): a gold
# arrowhead split down the middle, light on the left and darker on the right, with a dark ridge line and a thin dark
# outline so it reads on any background. 4x4 supersampling.
import math, os, struct, sys

N, SS = 64, 4
LIGHT, DARK, RIDGE = (0.93, 0.80, 0.42), (0.75, 0.61, 0.24), (0.57, 0.50, 0.30)   # sampled from arrow_gold.tga
EDGE = (0.10, 0.08, 0.04)
# an arrowhead with a notch at the back, kept inside the image's inscribed circle (radius 32 less the outline): the game
# turns it by its texture coordinates, which shows only that circle at every angle
TIP, LEFT, RIGHT, NOTCH = (32, 9), (15, 50), (49, 50), (32, 41)
OUT = 2.2  # outline width

def side(p, a, b):
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])

def inside(p):
    # two triangles: tip-left-notch and tip-notch-right
    def tri(a, b, c):
        s1, s2, s3 = side(p, a, b), side(p, b, c), side(p, c, a)
        return (s1 >= 0 and s2 >= 0 and s3 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0)
    return tri(TIP, LEFT, NOTCH) or tri(TIP, NOTCH, RIGHT)

def seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / (ax * ax + ay * ay)))
    return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * ay)

EDGES = [(TIP, LEFT), (LEFT, NOTCH), (NOTCH, RIGHT), (RIGHT, TIP)]
pixels = []
for py in range(N):
    for px in range(N):
        acc = [0.0, 0.0, 0.0, 0.0]
        for sy in range(SS):
            for sx in range(SS):
                p = (px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                d = min(seg_dist(p, a, b) for a, b in EDGES)
                if inside(p):
                    if d < 1.2:
                        col = EDGE
                    elif abs(p[0] - 32) < 0.8 and p[1] < NOTCH[1]:
                        col = RIDGE
                    else:
                        col = LIGHT if p[0] < 32 else DARK
                        # a little lighter towards the tip, as lit from above
                        k = max(0, 1 - (p[1] - TIP[1]) / 40) * 0.25
                        col = tuple(c + (1 - c) * k for c in col)
                    al = 1.0
                elif d < OUT:
                    col, al = EDGE, 0.9
                else:
                    continue
                acc[0] += col[0] * al; acc[1] += col[1] * al; acc[2] += col[2] * al; acc[3] += al
        n = SS * SS
        pixels.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n) if acc[3] else (0, 0, 0, 0))

with open("Textures/DirArrow.tga", "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for r, g, b, a in pixels:
        f.write(bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(a * 255)))))
if len(sys.argv) > 1:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    big = [[tuple(int(round(v * 255)) for v in pixels[(y // 4) * N + x // 4]) for x in range(N * 4)] for y in range(N * 4)]
    png.write(sys.argv[1], N * 4, N * 4, big, bg=70)
print("wrote Textures/DirArrow.tga")
