# Richtung J v2: erzeugt ./prints (nicht eingecheckt) –
#  1. prozedurale Pappe wie v1 (tools/pappe_pbr.py)
#  2. eigene Zeichnungen (Pillow): Schneidematte, Stahllineal, Bleistift-Anriss auf der Grundplatte
#  3. unscharfe Hintergruende aus den CC0-HDRIs in ./scans (Raum hinter dem Modell, "ausser Fokus")
import os, subprocess, sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "prints")
os.makedirs(OUT, exist_ok=True)
FORCE = os.environ.get("FORCE")
if not os.path.exists(os.path.join(OUT, "prints.png")) or FORCE:
    subprocess.check_call([sys.executable, os.path.join(HERE, "..", "tools", "pappe_pbr.py"), OUT])
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTC = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"
rs = np.random.RandomState(100)

def F(s, p=FONT):
    return ImageFont.truetype(p, s)

# ------------------------------------------------ Schneidematte A0 (120 x 90 cm = 120 x 90 m im Modell)
# Neutrales Schiefergrau (kein Gruen: Gruen ist dem Ausgang vorbehalten), helles 1-cm-Raster,
# 5-cm-Linien kraeftiger, Zahlen am Rand, Winkelhilfen. Kein Hersteller, kein Logo.
def mat():
    PX = 20                      # px pro cm
    W, H = 90 * PX, 120 * PX     # x = 90 cm, y(Bild) = 120 cm
    img = Image.new("RGB", (W, H), (52, 57, 58))
    a = np.asarray(img).astype(np.float32)
    n = rs.randn(H // 4, W // 4)
    n = np.asarray(Image.fromarray(((n - n.min()) / (n.max() - n.min()) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32) / 255
    a *= (0.94 + 0.08 * n)[..., None]
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    lc = (92, 98, 97)
    for i in range(0, 91):
        x = i * PX
        d.line([(x, 0), (x, H)], fill=lc if i % 5 else (128, 134, 131), width=1)
    for j in range(0, 121):
        y = j * PX
        d.line([(0, y), (W, y)], fill=lc if j % 5 else (128, 134, 131), width=1)
    # Winkelhilfen 45/60 Grad in einer Ecke
    for ang in (30, 45, 60):
        t = math.radians(ang)
        d.line([(0, H), (W * 0.6 * math.cos(t) * 1.4, H - W * 0.6 * math.sin(t) * 1.4)], fill=(120, 126, 124), width=1)
    f = F(14)
    for i in range(1, 90):
        d.text((i * PX + 2, 2), str(i), font=f, fill=(150, 156, 152))
    for j in range(1, 120):
        d.text((3, j * PX + 2), str(j), font=f, fill=(150, 156, 152))
    # Schnittspuren: feine helle Kratzer, wo frueher geschnitten wurde
    for _ in range(140):
        x0, y0 = rs.randint(0, W), rs.randint(0, H)
        L = rs.randint(40, 500); t = rs.choice([0, math.pi / 2, rs.rand() * math.pi])
        d.line([(x0, y0), (x0 + L * math.cos(t), y0 + L * math.sin(t))], fill=(88, 94, 95), width=1)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(os.path.join(OUT, "matte.png"))

# ------------------------------------------------ Stahllineal 60 cm (Skala in mm, Zahlen je cm)
def ruler():
    PX = 24
    W, H = 62 * PX, 3 * PX * 2
    img = Image.new("RGB", (W, H), (178, 182, 186))
    a = np.asarray(img).astype(np.float32)
    brush = rs.randn(1, W).repeat(H, 0) * 0.5 + rs.randn(H, W) * 2.0
    from scipy.ndimage import uniform_filter
    a += uniform_filter(brush, 7)[..., None] * 3
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    f = F(22, FONTC)
    for mm in range(0, 601):
        x = PX + mm * PX / 10
        h = 0.45 * H if mm % 10 == 0 else (0.3 * H if mm % 5 == 0 else 0.18 * H)
        d.line([(x, 0), (x, h)], fill=(25, 25, 28), width=2 if mm % 10 == 0 else 1)
        if mm % 10 == 0 and mm > 0:
            s = str(mm // 10)
            d.text((x - d.textlength(s, font=f) / 2, 0.5 * H), s, font=f, fill=(25, 25, 28))
    img.save(os.path.join(OUT, "lineal.png"))

# ------------------------------------------------ Bleistift-Anriss auf der Grundplatte (Strasse)
# Ein Streifen 6 m x 72 m (Kai bis Fassade); Grafit im Alpha. Masslinien, Achsen, Hausbreiten,
# Notizen des Modellbauers, radierte Stellen. Bild: x = Breite (6 m), y = Laenge (72 m).
def pencil(seed, name):
    r = np.random.RandomState(seed)
    PXM = 34
    W, H = int(6 * PXM), int(72 * PXM)
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    def line(p0, p1, a=150, w=2, wob=1.0):
        n = max(2, int(math.dist(p0, p1) / 20))
        pts = [(p0[0] + (p1[0] - p0[0]) * i / n + r.randn() * wob * 0.3, p0[1] + (p1[1] - p0[1]) * i / n + r.randn() * wob * 0.3) for i in range(n + 1)]
        d.line(pts, fill=int(a * (0.75 + 0.25 * r.rand())), width=w)
    # Fluchtlinie der Fassaden (doppelt angesetzt) und Kaikante
    line((W - 14, 0), (W - 13, H), 170, 2)
    line((W - 18, int(H * 0.3)), (W - 18, int(H * 0.75)), 110, 1)
    line((10, 0), (11, H), 120, 2)
    # Hausbreiten: Querstriche mit Massen
    y = 40
    f = F(26, FONTC)
    while y < H - 60:
        line((W - 70, y), (W - 2, y), 160, 2)
        line((W - 52, y - 12), (W - 30, y + 12), 150, 2)  # Masspfeil-Schraegstrich
        wm = r.uniform(5.0, 7.2)
        if r.rand() < 0.7:
            txt = ("%.1f" % (wm * 10)).replace(".", ",")
            tim = Image.new("L", (110, 34), 0)
            ImageDraw.Draw(tim).text((2, 0), txt, font=f, fill=int(150 + 60 * r.rand()))
            tim = tim.rotate(90, expand=True)
            img.paste(tim, (W - 64, int(y + wm * PXM * 0.5 - 50)), tim)
        y += int(wm * PXM)
    # Achse/Mittellinie strichpunktiert
    x = int(W * 0.45)
    yy = 0
    while yy < H:
        line((x, yy), (x, yy + 60), 110, 1); line((x, yy + 75), (x, yy + 81), 110, 1)
        yy += 96
    # Notizen
    notes = ["Kai", "Gracht 1:100", "Bäume alle 8 m", "Nadeln = Weg", "Brücke", "Leim!", "Ecke nachschneiden", "Tram hier"]
    for k in range(9):
        t = notes[r.randint(len(notes))]
        tim = Image.new("L", (360, 40), 0)
        ImageDraw.Draw(tim).text((2, 2), t, font=F(28, FONTC), fill=int(130 + 70 * r.rand()))
        tim = tim.rotate(90 + r.uniform(-4, 4), expand=True)
        img.paste(tim, (int(W * r.uniform(0.15, 0.5)), int(r.uniform(0.05, 0.9) * H)), tim)
    # Radierte Stellen: Grafit verwischt (weiche, schwache Flecken)
    a = np.asarray(img).astype(np.float32)
    for k in range(10):
        cx, cy = r.randint(0, W), r.randint(0, H)
        rr = r.randint(30, 90)
        yy, xx = np.ogrid[:H, :W]
        m = np.exp(-(((xx - cx) / rr) ** 2 + ((yy - cy) / (rr * 2.2)) ** 2))
        a = a * (1 - 0.7 * m) + 28 * m
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    img.save(os.path.join(OUT, name))

# ------------------------------------------------ HDRI-Hintergruende (unscharf = Raum ausser Fokus)
def read_hdr(path):
    import re
    data = open(path, "rb").read()
    i = data.index(b"\n\n") + 2
    j = data.index(b"\n", i)
    m = re.match(r"-Y (\d+) \+X (\d+)", data[i:j].decode())
    H, W = int(m[1]), int(m[2])
    p = j + 1
    img = np.zeros((H, W, 4), np.uint8)
    for y in range(H):
        if data[p] == 2 and data[p + 1] == 2:
            p += 4
            for c in range(4):
                x = 0
                while x < W:
                    n = data[p]; p += 1
                    if n > 128:
                        n -= 128; img[y, x:x + n, c] = data[p]; p += 1
                    else:
                        img[y, x:x + n, c] = np.frombuffer(data[p:p + n], np.uint8); p += n
                    x += n
        else:
            img[y] = np.frombuffer(data[p:p + W * 4], np.uint8).reshape(W, 4); p += W * 4
    e = img[..., 3].astype(np.int32)
    return img[..., :3].astype(np.float32) * np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)[..., None]

def write_hdr(path, a):
    a = np.maximum(a, 0).astype(np.float64)
    mx = a.max(-1)
    m, e = np.frexp(mx)
    sc = np.where(mx > 1e-32, m * 256.0 / np.maximum(mx, 1e-32), 0.0)
    rgbe = np.zeros(a.shape[:2] + (4,), np.uint8)
    rgbe[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(mx > 1e-32, e + 128, 0).astype(np.uint8)
    with open(path, "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % a.shape[:2])
        f.write(rgbe.tobytes())

def hdr_blur():
    from scipy.ndimage import gaussian_filter
    # Variante -> Raum: atelier = Tageslicht-Loft, abend/nacht = warmes Interieur, studio = Fotostudio
    for v, src in (("atelier", "tag"), ("abend", "warm"), ("studio", "studio"), ("nacht", "warm")):
        o = os.path.join(OUT, "hdri_%s_unscharf.hdr" % v)
        if os.path.exists(o) and not FORCE:
            continue
        a = read_hdr(os.path.join(HERE, "scans", "hdri_%s.hdr" % src))
        a = a.reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2, 3).mean((1, 3))   # 512x256
        # Glanzlichter etwas kappen, dann weich (Tiefenunschaerfe eines Makroobjektivs)
        lum = a.mean(-1, keepdims=True)
        a = a / (1 + np.maximum(lum - 2.5, 0) / 2.5)
        b = np.stack([gaussian_filter(a[..., k], (5, 5), mode=("nearest", "wrap")) for k in range(3)], -1)
        # Raumfarben zuruecknehmen (der Hintergrund soll nicht mit Kugel-Blau/Ausgang-Gruen konkurrieren)
        sat = {"atelier": 0.5, "abend": 0.6, "studio": 0.5, "nacht": 0.7}[v]
        l = b.mean(-1, keepdims=True)
        b = l + (b - l) * sat
        write_hdr(o, b.astype(np.float32))

if FORCE or not os.path.exists(os.path.join(OUT, "anriss_b.png")):
    mat(); ruler(); pencil(3, "anriss_a.png"); pencil(8, "anriss_b.png")
hdr_blur()
