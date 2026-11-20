# Run from the repo root: python tests/make_forever.py [preview.png] (dev-only; tests/ is not shipped).
# Textures/ForeverW.tga (64x64, 32-bit) from the user's picture (tests/art/forever_reference.png: the WoW Forever "W"
# emblem on a transparent background), the icon for quests added in WoW Forever:
#   1. the white bleeding cleaned: every pixel near the edge (semi-transparent ones and the light outer ring) gets the
#      colour of the nearest solid pixel further inside, its transparency kept, so the edge stays smooth without a
#      white halo;
#   2. a thin dark outline around it (as the elite skull and the infinity sign have), so it reads on any background;
#   3. cropped to the emblem, centred in a square and scaled to 64x64 (premultiplied area sampling).
import math, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "art", "forever_reference.png")
w, h, px = png.read(SRC)
EDGE_BAND = 3  # pixels within this distance of transparency are edge pixels

# distance (in steps) of every pixel to the nearest not-fully-opaque pixel, by breadth-first search
INF = 10 ** 9
dist = [[INF] * w for _ in range(h)]
queue = []
for y in range(h):
    for x in range(w):
        if px[y][x][3] < 255:
            dist[y][x] = 0
            queue.append((x, y))
head = 0
while head < len(queue):
    x, y = queue[head]; head += 1
    d = dist[y][x] + 1
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < w and 0 <= ny < h and dist[ny][nx] > d:
            dist[ny][nx] = d
            queue.append((nx, ny))

# 1. the core (solid, away from the edge) colour spread outward over the edge band (breadth-first from the core)
color = [[None] * w for _ in range(h)]
queue = []
for y in range(h):
    for x in range(w):
        if dist[y][x] > EDGE_BAND:
            color[y][x] = px[y][x][:3]
            queue.append((x, y))
head = 0
while head < len(queue):
    x, y = queue[head]; head += 1
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < w and 0 <= ny < h and color[ny][nx] is None and px[ny][nx][3] > 0:
            color[ny][nx] = color[y][x]
            queue.append((nx, ny))
clean = [[(0, 0, 0, 0)] * w for _ in range(h)]
for y in range(h):
    for x in range(w):
        a = px[y][x][3]
        if a > 0:
            c = color[y][x] or px[y][x][:3]
            clean[y][x] = (c[0], c[1], c[2], a)

# 3. crop to the emblem, centre it in a square with room for the outline
xs = [x for y in range(h) for x in range(w) if clean[y][x][3] > 0]
ys = [y for y in range(h) for x in range(w) if clean[y][x][3] > 0]
x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
N, PAD = 64, 3  # output size; the outline's room at 64 px
side = max(x1 - x0, y1 - y0) * N / (N - 2 * PAD)
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
SS = 6
small = []
for oy in range(N):
    row = []
    for ox in range(N):
        acc = [0.0, 0.0, 0.0, 0.0]
        for sy in range(SS):
            for sx in range(SS):
                fx = cx - side / 2 + (ox + (sx + 0.5) / SS) * side / N
                fy = cy - side / 2 + (oy + (sy + 0.5) / SS) * side / N
                ix, iy = int(math.floor(fx)), int(math.floor(fy))
                if 0 <= ix < w and 0 <= iy < h:
                    r, g, b, a = clean[iy][ix]
                    al = a / 255
                    acc[0] += r * al; acc[1] += g * al; acc[2] += b * al; acc[3] += al
        n = SS * SS
        row.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3] / n) if acc[3] else (0, 0, 0, 0.0))
    small.append(row)

# 2. the thin dark outline (at 64 px): dark where the emblem is not, by its distance to the emblem
OUT = 1.6
DARK = (12, 14, 18)
final = []
for y in range(N):
    row = []
    for x in range(N):
        r, g, b, a = small[y][x]
        best = 0.0
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                nx, ny = x + dx, y + dy
                if 0 <= nx < N and 0 <= ny < N:
                    d = math.hypot(dx, dy)
                    if d <= OUT + 0.5:
                        best = max(best, small[ny][nx][3] * max(0.0, min(1.0, OUT + 0.5 - d)))
        oa = 0.85 * best
        # the emblem over its outline
        out_a = a + oa * (1 - a)
        if out_a > 0:
            rr = (r * a + DARK[0] * oa * (1 - a)) / out_a
            gg = (g * a + DARK[1] * oa * (1 - a)) / out_a
            bb = (b * a + DARK[2] * oa * (1 - a)) / out_a
            row.append((int(round(rr)), int(round(gg)), int(round(bb)), int(round(out_a * 255))))
        else:
            row.append((0, 0, 0, 0))
    final.append(row)

with open("Textures/ForeverW.tga", "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for row in final:
        for r, g, b, a in row:
            f.write(bytes((b, g, r, a)))
if len(sys.argv) > 1:
    big = [[final[y // 4][x // 4] for x in range(N * 4)] for y in range(N * 4)]
    png.write(sys.argv[1], N * 4, N * 4, big, bg=45)
    # the cleaned full-size picture too, on a dark background, to check the edges
    png.write(sys.argv[1].replace(".png", "_full.png"), w, h, clean, bg=45)
print("wrote Textures/ForeverW.tga")
