# Run from the repo root: python tests/make_rxparrow.py [preview.png] (dev-only; tests/ is not shipped).
# Textures/RxpArrow.tga (64x64, 32-bit): the Arrow section's icon in /qt (3.2, user: "replace the Arrow icon with
# RestedXP's arrow icon"). Our own drawing in that look: a rounded arrowhead with a notch at the back, split down the
# middle, purple on the left and blue on the right, a thin dark line around it and a light outline outside that.
# 4x4 supersampling.
import math, os, struct, sys

N, SS = 64, 4
PURPLE, BLUE = (0.33, 0.20, 0.70), (0.02, 0.52, 0.94)
DARK, LIGHT = (0.09, 0.10, 0.20), (0.84, 0.89, 1.00)
TIP, LEFT, NOTCH, RIGHT = (32, 9), (12, 52), (32, 41), (52, 52)
POLY = [TIP, LEFT, NOTCH, RIGHT]
ROUND, DARK_W, LIGHT_W = 1.5, 1.6, 2.6  # the fill reaches ROUND past the polygon (round corners), then the two lines

def seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / (ax * ax + ay * ay)))
    return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * ay)

def inside(p):
    # even-odd rule
    c = False
    for i in range(len(POLY)):
        a, b = POLY[i], POLY[(i + 1) % len(POLY)]
        if (a[1] > p[1]) != (b[1] > p[1]):
            x = a[0] + (p[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if p[0] < x:
                c = not c
    return c

def sd(p):
    d = min(seg_dist(p, POLY[i], POLY[(i + 1) % len(POLY)]) for i in range(len(POLY)))
    return -d if inside(p) else d

pixels = []
for py in range(N):
    for px in range(N):
        acc = [0.0, 0.0, 0.0, 0.0]
        for sy in range(SS):
            for sx in range(SS):
                p = (px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                d = sd(p)
                if d <= ROUND:
                    col = PURPLE if p[0] < 32 else BLUE
                    # a little lighter towards the tip
                    k = max(0, 1 - (p[1] - TIP[1]) / 44) * 0.12
                    col = tuple(c + (1 - c) * k for c in col)
                elif d <= ROUND + DARK_W:
                    col = DARK
                elif d <= ROUND + DARK_W + LIGHT_W:
                    col = LIGHT
                else:
                    continue
                acc[0] += col[0]; acc[1] += col[1]; acc[2] += col[2]; acc[3] += 1
        n = SS * SS
        pixels.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n) if acc[3] else (0, 0, 0, 0))

with open("Textures/RxpArrow.tga", "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for r, g, b, a in pixels:
        f.write(bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(a * 255)))))
if len(sys.argv) > 1:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    big = [[tuple(int(round(v * 255)) for v in pixels[(y // 4) * N + x // 4]) for x in range(N * 4)] for y in range(N * 4)]
    png.write(sys.argv[1], N * 4, N * 4, big, bg=40)
print("wrote Textures/RxpArrow.tga")
