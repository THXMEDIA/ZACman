# Arles v2 – Auswertung der Renderings (Pillow + NumPy, keine Fremdbilder):
# Capsules, Kontaktbogen, Variantenvergleich, Farbsehschwaechen (Machado 2009), Strich-LOD-Flimmertest.
# Aufruf: python3 auswertung.py <renderordner> <zielordner>   (render_all.sh ruft das auf)
import os, sys, shutil, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

T, DST = sys.argv[1], sys.argv[2]
os.makedirs(DST, exist_ok=True)
N = os.path.join(T, "nacht", "arles_v2")
BL = os.path.join(T, "blau", "arles_v2", "blau")
CHORUS = "/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyrechorus-mediumitalic.otf"
INTER = "/usr/share/fonts/opentype/inter/Inter-%s.otf"
def F(p, s): return ImageFont.truetype(p, s)
def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
report = {}

# 1) Bilder kopieren
VIEWS = ["strasse", "totale", "forum", "arenes", "trophime", "theatre", "kai", "ausgang", "capsule"]
for v in VIEWS:
    shutil.copy(os.path.join(N, v + ".png"), os.path.join(DST, v + ".png"))
shutil.copy(os.path.join(T, "reduziert", "arles_v2", "strasse.png"), os.path.join(DST, "effekte_reduziert.png"))
for f in ("karte.png", "minimap.png", "karte_ascii.txt", "karte_pruefung.txt", "himmel_bake.png"):
    if os.path.exists(os.path.join(T, f)):
        shutil.copy(os.path.join(T, f), os.path.join(DST, f))
os.makedirs(os.path.join(DST, "blaue_stunde"), exist_ok=True)
for f in sorted(os.listdir(BL)):
    shutil.copy(os.path.join(BL, f), os.path.join(DST, "blaue_stunde", f))

# 2) Capsules (Titel wie v1: TeX Gyre Chorus, GUST Font License)
def text_outline(d, xy, text, font, fill, outline, w=4):
    x, y = xy
    for dx in range(-w, w + 1, 2):
        for dy in range(-w, w + 1, 2):
            d.text((x + dx, y + dy), text, font=font, fill=outline)
    d.text(xy, text, font=font, fill=fill)

def capsule(src_dir, dst_dir):
    src = Image.open(os.path.join(src_dir, "capsule.png")).convert("RGB")
    crop = src.crop((0, 40, 1280, 40 + 598)).resize((920, 430), Image.LANCZOS)
    d = ImageDraw.Draw(crop)
    text_outline(d, (40, 18), "ZAPmaniac", F(CHORUS, 104), rgb("#F6C945"), rgb("#141D4A"), 6)
    text_outline(d, (50, 128), "Explorer: Arles bei Nacht", F(CHORUS, 42), rgb("#FFF3B0"), rgb("#141D4A"), 3)
    crop.save(os.path.join(dst_dir, "capsule_920x430.png"))
    crop.resize((460, 215), Image.LANCZOS).save(os.path.join(dst_dir, "capsule_460x215.png"))
capsule(N, DST)
capsule(BL, os.path.join(DST, "blaue_stunde"))

# 3) Farbsehschwaechen: Machado, Oliveira, Fernandes (2009), Schweregrad 1.0, im linearen RGB
MACH = {
    "Protanopie": np.array([[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]),
    "Deuteranopie": np.array([[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]),
    "Tritanopie": np.array([[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]),
}
def to_lin(a): a = a / 255.0; return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
def to_srgb(a): a = np.clip(a, 0, 1); return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055) * 255.0
def sim(img, m):
    a = to_lin(np.asarray(img, dtype=np.float64))
    return Image.fromarray(to_srgb(a @ m.T).astype(np.uint8))
def lab(c):
    l = to_lin(np.array(c, dtype=np.float64))
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    x, y, z = M @ l / np.array([0.95047, 1.0, 1.08883])
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    return np.array([116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))])
def lum(c):
    l = to_lin(np.array(c, dtype=np.float64)); return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
def sim_c(c, m):
    return tuple(to_srgb(m @ to_lin(np.array(c, dtype=np.float64))))

# gemessene Farben aus den Renderings (Mittel ueber eindeutige Pixel)
def measure(img, cond):
    a = np.asarray(img.convert("RGB")).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = cond(r, g, b)
    return tuple(int(v) for v in a[m].mean(axis=0)) if m.sum() > 50 else None
aus = Image.open(os.path.join(N, "ausgang.png")); kai = Image.open(os.path.join(N, "kai.png")); st = Image.open(os.path.join(N, "strasse.png"))
meas = {
    "Ausgang (Tuer, gerendert)": measure(aus, lambda r, g, b: (g > 200) & (g > r + 60) & (b > 120) & (r < 160)),
    "Kugel (gerendert)": measure(st, lambda r, g, b: (r > 220) & (g > 60) & (g < 150) & (b < 110)),
    "Laterne/Fenster (gerendert)": measure(st, lambda r, g, b: (r > 230) & (g > 190) & (b < 150)),
}
design = {
    "Kugel Zinnober #FF4A1C": rgb("#FF4A1C"), "Kugel-Kontur #3A0E06": rgb("#3A0E06"),
    "Chromgelb #F6C945": rgb("#F6C945"), "Laternenglas #FFE9A0": rgb("#FFE9A0"), "Halo-Rand Gold #D4A03A": rgb("#D4A03A"),
    "Spiegelung Gold #C99A3D": rgb("#C99A3D"), "Ausgang Minzgruen #3AF5C8": rgb("#3AF5C8"), "Himmel hell #7FB2E5": rgb("#7FB2E5"),
    "Zypresse #1E3F30": rgb("#1E3F30"), "Platane #34557A": rgb("#34557A"), "Pflaster #33456F": rgb("#33456F"),
    "Fassade Ocker #B88A3C": rgb("#B88A3C"), "Gelbes Haus #E2B34C": rgb("#E2B34C"),
}
for k, v in meas.items():
    if v: design[k] = v
pairs = [("Kugel Zinnober #FF4A1C", "Chromgelb #F6C945"), ("Kugel Zinnober #FF4A1C", "Laternenglas #FFE9A0"),
         ("Kugel Zinnober #FF4A1C", "Halo-Rand Gold #D4A03A"), ("Kugel Zinnober #FF4A1C", "Spiegelung Gold #C99A3D"),
         ("Kugel Zinnober #FF4A1C", "Pflaster #33456F"), ("Kugel Zinnober #FF4A1C", "Fassade Ocker #B88A3C"),
         ("Kugel (gerendert)", "Laterne/Fenster (gerendert)"),
         ("Ausgang Minzgruen #3AF5C8", "Zypresse #1E3F30"), ("Ausgang Minzgruen #3AF5C8", "Platane #34557A"), ("Ausgang Minzgruen #3AF5C8", "Chromgelb #F6C945"),
         ("Ausgang Minzgruen #3AF5C8", "Gelbes Haus #E2B34C"), ("Ausgang (Tuer, gerendert)", "Laterne/Fenster (gerendert)"),
         ("Ausgang Minzgruen #3AF5C8", "Kugel Zinnober #FF4A1C"), ("Ausgang Minzgruen #3AF5C8", "Himmel hell #7FB2E5")]
rows = []
for a, b in pairs:
    if a not in design or b not in design: continue
    ca, cb = design[a], design[b]
    row = {"paar": "%s / %s" % (a, b), "Normal": round(float(np.linalg.norm(lab(ca) - lab(cb))), 1)}
    for n, m in MACH.items():
        row[n] = round(float(np.linalg.norm(lab(sim_c(ca, m)) - lab(sim_c(cb, m)))), 1)
    la, lb = lum(ca), lum(cb)
    row["Kontrast (Helligkeit)"] = round((max(la, lb) + 0.05) / (min(la, lb) + 0.05), 2)
    rows.append(row)
report["farbsehen"] = rows
report["gemessen"] = meas
with open(os.path.join(DST, "farbsehen.txt"), "w") as fh:
    fh.write("Farbabstand CIE76 (ΔE) normal und simuliert (Machado 2009, Schweregrad 1,0); Kontrast = WCAG-Helligkeitsverhaeltnis\n")
    fh.write("gemessen aus den Renderings: %s\n\n" % json.dumps(meas, ensure_ascii=False))
    fh.write("%-70s %7s %7s %7s %7s %8s\n" % ("Paar", "normal", "Prot", "Deut", "Trit", "Kontrast"))
    for r in rows:
        fh.write("%-70s %7.1f %7.1f %7.1f %7.1f %8.2f\n" % (r["paar"], r["Normal"], r["Protanopie"], r["Deuteranopie"], r["Tritanopie"], r["Kontrast (Helligkeit)"]))
# Bildtafel: Kai und Ausgang je normal + 3 Simulationen
tiles = []
for name, img in (("kai", kai), ("ausgang", aus)):
    im = img.convert("RGB").resize((480, 270))
    tiles.append((name + " · normal", im))
    for n, m in MACH.items():
        tiles.append((name + " · " + n, sim(im, m)))
S = Image.new("RGB", (4 * 480, 2 * 270 + 2 * 26), (12, 14, 30)); D = ImageDraw.Draw(S)
for i, (t, im) in enumerate(tiles):
    x, y = (i % 4) * 480, (i // 4) * (270 + 26)
    S.paste(im, (x, y + 26)); D.text((x + 8, y + 4), t, font=F(INTER % "SemiBold", 17), fill=(255, 255, 255))
S.save(os.path.join(DST, "farbsehen.png"))

# 4) Strich-LOD: Flimmer-Index = mittlere Pixelaenderung zwischen zwei Lauf-Frames (7 cm) im fernen
#    Bildbereich (Fluchtpunkt-Umgebung ohne Kugelspur). Plus Hochfrequenz-Energie (Laplace).
L = os.path.join(T, "lod", "arles_v2")
def load(n): return np.asarray(Image.open(os.path.join(L, n)).convert("L")).astype(float)
box = (slice(150, 430), slice(330, 950))
def lap(a):
    return np.abs(4 * a[1:-1, 1:-1] - a[:-2, 1:-1] - a[2:, 1:-1] - a[1:-1, :-2] - a[1:-1, 2:]).mean()
lodres = {}
for Lv in ("1", "0"):
    a, b = load("lod%s_z63.00.png" % Lv), load("lod%s_z62.93.png" % Lv)
    ra, rb = a[box], b[box]
    mask = np.ones_like(ra, dtype=bool); mask[:, 270:350] = False     # Kugelspur in der Bildmitte ausnehmen
    fa, fb = a[200:335, 500:800], b[200:335, 500:800]     # nur Ferne (Platz, Café, ~30–40 m)
    fm = np.ones_like(fa, dtype=bool); fm[:, 120:180] = False
    lodres["LOD an" if Lv == "1" else "LOD aus"] = {"flimmer_gesamt": round(float(np.abs(ra - rb)[mask].mean()), 2),
        "flimmer_fern": round(float(np.abs(fa - fb)[fm].mean()), 2), "hochfrequenz_fern": round(float(lap(fa)), 2)}
report["lod"] = lodres
# Bild: Ausschnitte LOD aus / an und Differenzbilder
def crop(n): return Image.open(os.path.join(L, n)).convert("RGB").crop((330, 150, 950, 430))
def diffimg(n1, n2):
    a = np.asarray(crop(n1)).astype(int); b = np.asarray(crop(n2)).astype(int)
    d = np.clip(np.abs(a - b).sum(axis=2) * 3, 0, 255).astype(np.uint8)
    return Image.fromarray(d).convert("RGB")
P = Image.new("RGB", (2 * 620, 2 * 280 + 60), (12, 14, 30)); D = ImageDraw.Draw(P)
P.paste(crop("lod0_z63.00.png"), (0, 30)); P.paste(crop("lod1_z63.00.png"), (620, 30))
P.paste(diffimg("lod0_z63.00.png", "lod0_z62.93.png"), (0, 340)); P.paste(diffimg("lod1_z63.00.png", "lod1_z62.93.png"), (620, 340))
f = F(INTER % "SemiBold", 17)
D.text((8, 6), "LOD aus (Impasto bis zum Horizont)", font=f, fill=(255, 255, 255))
D.text((628, 6), "LOD an (14–28 m Uebergang zu grossen Tupfern, Pixel-Filter)", font=f, fill=(255, 255, 255))
D.text((8, 316), "7 cm Laufen: Flimmern gesamt %.1f · fern %.1f" % (lodres["LOD aus"]["flimmer_gesamt"], lodres["LOD aus"]["flimmer_fern"]), font=f, fill=(255, 255, 255))
D.text((628, 316), "7 cm Laufen: Flimmern gesamt %.1f · fern %.1f" % (lodres["LOD an"]["flimmer_gesamt"], lodres["LOD an"]["flimmer_fern"]), font=f, fill=(255, 255, 255))
P.save(os.path.join(DST, "lod_vergleich.png"))

# 5) Varianten-Vergleich und Kontaktbogen
def lab_img(path, w, h, text):
    im = Image.open(path).convert("RGB").resize((w, h), Image.LANCZOS)
    d = ImageDraw.Draw(im); d.rectangle([0, 0, w, 24], fill=(10, 12, 30)); d.text((8, 3), text, font=F(INTER % "SemiBold", 15), fill=(255, 255, 255))
    return im
Vv = Image.new("RGB", (2 * 640, 3 * 360), (0, 0, 0))
for i, v in enumerate(("strasse", "kai", "capsule")):
    Vv.paste(lab_img(os.path.join(N, v + ".png"), 640, 360, "tiefe Nacht · " + v), (0, i * 360))
    Vv.paste(lab_img(os.path.join(BL, v + ".png"), 640, 360, "blaue Stunde · " + v), (640, i * 360))
Vv.save(os.path.join(DST, "vergleich_nacht_blau.png"))
items = [(os.path.join(DST, v + ".png"), v) for v in ["strasse", "totale", "forum", "arenes", "trophime", "theatre", "kai", "ausgang"]]
items += [(os.path.join(DST, "effekte_reduziert.png"), "effekte reduziert"), (os.path.join(DST, "capsule_920x430.png"), "capsule 920x430"),
          (os.path.join(DST, "karte.png"), "karte (Skizze)"), (os.path.join(DST, "blaue_stunde", "strasse.png"), "Variante blaue Stunde")]
W, H = 560, 315
U = Image.new("RGB", (3 * W, 4 * H + 60), (14, 18, 46)); D = ImageDraw.Draw(U)
D.text((14, 12), "ZAPmaniac · Explorer Arles v2 – Sternennacht, echte Orte stilisiert (Art Director, 04.10.2026, Software-Renderer)", font=F(INTER % "SemiBold", 22), fill=rgb("#F6C945"))
for i, (p, t) in enumerate(items):
    im = Image.open(p).convert("RGB")
    im.thumbnail((W, H), Image.LANCZOS)
    tile = Image.new("RGB", (W, H), (8, 10, 26)); tile.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
    d = ImageDraw.Draw(tile); d.rectangle([0, 0, W, 22], fill=(10, 12, 30)); d.text((8, 2), t, font=F(INTER % "SemiBold", 15), fill=(255, 255, 255))
    U.paste(tile, ((i % 3) * W, 60 + (i // 3) * H))
U.save(os.path.join(DST, "uebersicht.png"))
json.dump(report, open(os.path.join(DST, "auswertung.json"), "w"), ensure_ascii=False, indent=1)
print(json.dumps(report, ensure_ascii=False, indent=1))
