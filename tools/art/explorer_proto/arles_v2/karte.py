# Arles-Explorer – Kartenskizze v2: prueft karte.json (Erreichbarkeit, kuerzester Weg, Sackgassen
# auf Wahrzeichen, Kugelspur) und zeichnet ASCII, karte.png und minimap.png (Pillow).
# Aufruf: python3 karte.py [ausgabeordner]   (Art Director, 04.10.2026 – NICHT Spielcode)
import json, os, sys
from collections import deque
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
K = json.load(open(os.path.join(HERE, "karte.json")))
R, C = K["rows"], K["cols"]
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE

open_ = [[False] * C for _ in range(R)]
for s in K["streets"]:
    for r in range(s["r0"], s["r1"] + 1):
        for c in range(s["c0"], s["c1"] + 1):
            open_[r][c] = True
# Arena-Innenflaeche ist Block (Ring-Rechtecke ueberdecken sie nicht, aber sicherheitshalber)
for L in K["landmarks"]:
    for r in range(L["r0"], L["r1"] + 1):
        for c in range(L["c0"], L["c1"] + 1):
            if L.get("gate") and open_[r][c]:
                continue
            open_[r][c] = False
lm_at = {}
for L in K["landmarks"]:
    for r in range(L["r0"], L["r1"] + 1):
        for c in range(L["c0"], L["c1"] + 1):
            if not open_[r][c]:
                lm_at[(r, c)] = L["id"]

def nb(r, c):
    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        rr, cc = r + dr, c + dc
        if 0 <= rr < R and 0 <= cc < C:
            yield rr, cc

S = tuple(K["start"]); X = tuple(K["exit"])
assert open_[S[0]][S[1]] and open_[X[0]][X[1]], "Start/Ausgang muessen Strasse sein"

def bfs(allowed):
    dist = {S: 0}; prev = {}
    q = deque([S])
    while q:
        p = q.popleft()
        for n in nb(*p):
            if allowed(n) and n not in dist:
                dist[n] = dist[p] + 1; prev[n] = p; q.append(n)
    return dist, prev

dist, _ = bfs(lambda n: open_[n[0]][n[1]])
n_open = sum(map(sum, open_))
assert len(dist) == n_open, "nicht alle Strassenzellen erreichbar: %d/%d" % (len(dist), n_open)
best_any = dist[X]

# Kugelspur: alle Trail-Linien (Zellen auf Strassen)
trail = set()
for t in K["trail_lines"]:
    for i in range(t["from"], t["to"] + 1):
        cell = (t["row"], i) if "row" in t else (i, t["col"])
        assert open_[cell[0]][cell[1]], "Spur auf Block: %s" % (cell,)
        trail.add(cell)
# Weg der Kugeln = kuerzester Weg im Spurnetz (so laeuft der Spieler, wenn er den Kugeln folgt)
tdist, prev = bfs(lambda n: n in trail)
assert X in tdist, "Ausgang nicht ueber die Kugelspur erreichbar"
path = [X]
while path[-1] != S:
    path.append(prev[path[-1]])
path.reverse()
for e in K["must_ends"]:
    assert tuple(e) in tdist, "must_end nicht im Spurnetz: %s" % (e,)

def street_of(cell):
    return [s["id"] for s in K["streets"] if s["r0"] <= cell[0] <= s["r1"] and s["c0"] <= cell[1] <= s["c1"]]
streets_on_path = []
for p in path:
    for sid in street_of(p):
        if sid not in streets_on_path:
            streets_on_path.append(sid)
# Wahrzeichen mit Fassade an einer Strasse des Weges (sichtbar beim Durchlaufen)
seen = []
for sid in streets_on_path:
    st = [z for z in K["streets"] if z["id"] == sid][0]
    for r in range(st["r0"] - 1, st["r1"] + 2):
        for c in range(st["c0"] - 1, st["c1"] + 2):
            lid = lm_at.get((r, c))
            if lid and lid not in seen:
                seen.append(lid)
# Strassenenden: worauf schaut die Mittellinie am Ende?
dead = []
for st in K["streets"]:
    h, w = st["r1"] - st["r0"] + 1, st["c1"] - st["c0"] + 1
    if h > w:
        cc = (st["c0"] + st["c1"]) // 2
        ends = [((st["r0"], cc), (st["r0"] - 1, cc)), ((st["r1"], cc), (st["r1"] + 1, cc))]
    else:
        rr = (st["r0"] + st["r1"]) // 2
        ends = [((rr, st["c0"]), (rr, st["c0"] - 1)), ((rr, st["c1"]), (rr, st["c1"] + 1))]
    for cell, ahead in ends:
        if 0 <= ahead[0] < R and 0 <= ahead[1] < C and not open_[ahead[0]][ahead[1]]:
            dead.append((st["id"], lm_at.get(ahead, "Rhone/Bruestung" if ahead[1] == 0 else "Hausfassade")))
ch = {"maison_jaune": "Y", "porte_cavalerie": "P", "remparts": "M", "arenes": "A", "thermes": "T", "cafe": "K",
      "colonnes_forum": "c", "hotel_de_ville": "H", "saint_trophime": "S", "theatre_antique": "V", "grand_prieure": "G"}
lines = []
lines.append("     " + "".join(str(c // 10) for c in range(C)))
lines.append("     " + "".join(str(c % 10) for c in range(C)))
pathset = set(path)
for r in range(R):
    row = ""
    for c in range(C):
        if (r, c) == S: row += "@"
        elif (r, c) == X: row += "X"
        elif open_[r][c]:
            row += "o" if (r, c) in pathset else ("·" if (r, c) in trail else " ")
        elif (r, c) in lm_at: row += ch[lm_at[(r, c)]]
        elif c == K["parapet"]["col"] and K["parapet"]["r0"] <= r <= K["parapet"]["r1"]: row += "≈"
        else: row += "#"
    lines.append("%3d  %s" % (r, row))
ascii_ = "\n".join(lines)
print(ascii_)
print()
print("Strassenzellen:", n_open, "| Kugelspur-Zellen (alle Linien):", len(trail))
print("Weg entlang der Kugeln Start->Ausgang: %d Zellen = %d m (~%.0f s bei 4,4 m/s); kuerzester Weg ueberhaupt: %d Zellen" % (len(path) - 1, (len(path) - 1) * 2, (len(path) - 1) * 2 / 4.4, best_any))
print("Strassen am Weg:", " > ".join(streets_on_path))
print("Wahrzeichen am Weg (Reihenfolge):", ", ".join(seen))
print("Strassenenden -> Blickpunkt:", "; ".join("%s->%s" % (d[0], d[1]) for d in dead))
off = [p for p in path if p not in trail]
print("Weg-Zellen ohne Kugelspur:", len(off))
open(os.path.join(OUT, "karte_ascii.txt"), "w").write(ascii_ + "\n")

# Bilder: karte.png (Skizze mit Namen) und minimap.png (Spiel-Minimap: dunkle Strassen, helle Bloecke)
def img(scale, minimap):
    W, H = C * scale, R * scale
    im = Image.new("RGB", (W, H), (226, 214, 186) if minimap else (40, 46, 92))
    d = ImageDraw.Draw(im)
    for r in range(R):
        for c in range(C):
            x0, y0 = c * scale, r * scale
            if open_[r][c]:
                col = (27, 34, 70) if minimap else (58, 77, 122)
            elif (r, c) in lm_at:
                col = (246, 201, 69) if not minimap else (200, 168, 110)
            elif c == 0 and K["parapet"]["r0"] <= r <= K["parapet"]["r1"]:
                col = (60, 90, 150) if not minimap else (120, 140, 170)
            else:
                col = (226, 214, 186) if minimap else (75, 74, 134)
            d.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=col)
    for (r, c) in trail:
        cx, cy = c * scale + scale / 2, r * scale + scale / 2
        rr = scale * (0.22 if minimap else 0.18)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 74, 28), outline=(58, 14, 6))
    xr, xc = X
    d.rectangle([xc * scale - scale * 0.2, xr * scale - scale * 0.2, xc * scale + scale * 1.2, xr * scale + scale * 1.2], fill=(58, 245, 200), outline=(8, 48, 40), width=max(1, scale // 6))
    sr, sc = S
    d.polygon([(sc * scale + scale, sr * scale), (sc * scale + scale, sr * scale + scale), (sc * scale - scale * 0.2, sr * scale + scale / 2)], fill=(255, 255, 255), outline=(0, 0, 0))
    if not minimap:
        f = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", int(scale * 0.62))
        for p in path:
            cx, cy = p[1] * scale + scale / 2, p[0] * scale + scale / 2
            d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=(255, 255, 255))
        labels = {"maison_jaune": "Gelbes Haus · AUSGANG", "porte_cavalerie": "Porte de la Cavalerie", "remparts": "Mauerturm",
                  "arenes": "Arènes", "thermes": "Thermen", "cafe": "Caféterrasse", "colonnes_forum": "Säulen",
                  "hotel_de_ville": "Hôtel de Ville", "saint_trophime": "St-Trophime", "theatre_antique": "Théâtre antique",
                  "grand_prieure": "Grand Prieuré"}
        for L in K["landmarks"]:
            x, y = L["c0"] * scale + 2, L["r0"] * scale + 1
            if L["id"] == "arenes": x, y = (L["c0"] + 3) * scale, (L["r0"] + 6) * scale
            if L["id"] == "hotel_de_ville": x, y = 2, (L["r1"] + 1) * scale + 30
            if L["id"] == "grand_prieure": y = (L["r1"] + 1) * scale + 2
            if L["id"] == "saint_trophime": x = (L["c1"] + 1) * scale + 4
            if L["id"] == "colonnes_forum": y = (L["r0"] - 1) * scale
            d.text((x, y), labels[L["id"]], font=f, fill=(255, 255, 255), stroke_width=3, stroke_fill=(10, 14, 40))
        for s, t in (("quai", "Kai / Rhône"), ("rue_forum", "Rue du Forum"), ("place_forum", "Place du Forum"), ("rue_calade", "Rue de la Calade"),
                     ("place_lamartine", "Place Lamartine"), ("place_republique", "Pl. de la République"), ("rue_cavalerie", "R. Cavalerie")):
            st = [z for z in K["streets"] if z["id"] == s][0]
            x, y = st["c0"] * scale + 4, st["r1"] * scale + 2
            if s == "quai": x, y = 2, 24 * scale
            if s == "rue_cavalerie": x, y = (st["c1"] + 1) * scale + 3, 6 * scale
            if s == "place_forum": x, y = (st["c0"] + 1) * scale, (st["r0"] + 1) * scale
            d.text((x, y), t, font=f, fill=(246, 201, 69), stroke_width=3, stroke_fill=(10, 14, 40))
        d.text((W - 14 * scale, H - scale * 1.4), "1 Zelle = 2 m · N oben", font=f, fill=(255, 255, 255), stroke_width=3, stroke_fill=(10, 14, 40))
    return im

img(22, False).save(os.path.join(OUT, "karte.png"))
img(6, True).resize((C * 6, R * 6)).save(os.path.join(OUT, "minimap.png"))
# Gelaende-Raster fuer den Godot-Prototyp: weiss = Strasse
g = Image.new("L", (C, R), 0)
for r in range(R):
    for c in range(C):
        if open_[r][c]:
            g.putpixel((c, r), 255)
g.save(os.path.join(HERE, "raster.png"))
json.dump({"path": path, "trail": sorted(trail)}, open(os.path.join(HERE, "spur.json"), "w"))
