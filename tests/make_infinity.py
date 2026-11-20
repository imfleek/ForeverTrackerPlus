# Run from the repo root: python tests/make_infinity.py Textures/Infinity.tga [preview.png] (dev-only; tests/ is not shipped).
# Draws Textures/Infinity.tga (64x64, 32-bit, uncompressed): the cyan infinity sign of the user's reference picture
# (tests/art/infinity_reference.png) with no background; a thin dark outline (as the elite skull has) keeps it readable
# on light and dark backgrounds. 4x4 supersampling for smooth edges.
import math, os, struct, sys

N, SS = 64, 4
out = sys.argv[1]

# the infinity curve (lemniscate of Bernoulli), as many points, filling most of the square
pts = []
a = 24.0  # the sign plus its outline fits inside the 64 px square, with a pixel to spare
for i in range(2400):
    t = 2 * math.pi * i / 2400
    s = math.sin(t)
    d = 1 + s * s
    pts.append((32 + a * math.cos(t) / d, 32 + a * s * math.cos(t) / d))

def curve_dist(x, y):
    best = 1e9
    for px, py in pts:
        dx, dy = x - px, y - py
        dd = dx * dx + dy * dy
        if dd < best:
            best = dd
    return math.sqrt(best)

CYAN = (0.27, 0.87, 0.97)   # the sign
CORE = (0.62, 0.96, 1.0)    # a lighter line along its middle (the reference's glow)
DARK = (0.03, 0.06, 0.08)   # the outline
STROKE, OUTLINE = 4.2, 1.6  # half widths

pixels = []
for py in range(N):
    for px in range(N):
        acc = [0.0, 0.0, 0.0, 0.0]  # premultiplied
        for sy in range(SS):
            for sx in range(SS):
                d = curve_dist(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                if d < STROKE:
                    k = 1 - d / STROKE
                    col = [c + (cc - c) * k * k for c, cc in zip(CYAN, CORE)]
                    al = 1.0
                elif d < STROKE + OUTLINE:
                    col, al = DARK, 0.85
                else:
                    continue
                acc[0] += col[0] * al; acc[1] += col[1] * al; acc[2] += col[2] * al; acc[3] += al
        n = SS * SS
        alpha = acc[3] / n
        if alpha > 0:
            pixels.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], alpha))
        else:
            pixels.append((0, 0, 0, 0))

with open(out, "wb") as f:
    # TGA header: uncompressed true colour, 64x64, 32 bpp, 8 alpha bits, top-left origin (bit 5)
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for r, g, b, al in pixels:
        f.write(bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(al * 255)))))

if len(sys.argv) > 2:  # a 4x preview on grey, for checking by eye
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import png
    big = [[tuple(int(round(v * 255)) for v in pixels[(y // 4) * N + x // 4]) for x in range(N * 4)] for y in range(N * 4)]
    png.write(sys.argv[2], N * 4, N * 4, big, bg=70)
print("wrote", out)
