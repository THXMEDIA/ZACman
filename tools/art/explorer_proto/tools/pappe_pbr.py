# Prozedurale PBR-Texturen fuer "fotorealistische Wellpappe" (Richtungen I-K, Art Director,
# Nachtrag 04.10.2026). NICHT Spielcode, keine Fremdbilder, keine Scans: alles aus Rauschen,
# Geometrie und eigenen Zeichnungen (numpy + Pillow).
#
# Aufruf: python3 pappe_pbr.py <ausgabeordner>
# Schreibt (OpenGL-Normalen, Y+ wie Godot erwartet):
#   liner_albedo/normal/rough.png   Deckpapier (Kraftliner) 1024 px = 0,512 m, kachelbar.
#                                    Wellen (C-Welle, 8 mm) laufen senkrecht im Bild, zeichnen
#                                    sich als feine Rippen ab ("Waschbrett").
#   crumple_albedo/normal.png       zerknittertes Packpapier (periodisches Voronoi-Facettenfeld
#                                    in zwei Oktaven, aufgehellte Knickgrate), kachelbar.
#   tape_normal.png                 Klebeband-Falten (laengs gestreckt), kachelbar.
#   prints.png                      Druck-/Marker-Atlas 4x4 (eigene Piktogramme, Handschrift-
#                                    Etiketten), Tinte im Alpha.
import os, sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "prints"
os.makedirs(OUT, exist_ok=True)
N = 1024
rs = np.random.RandomState(7)

def save(a, name, mode=None):
    a = np.clip(a, 0, 1)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), mode).save(os.path.join(OUT, name))

def fnoise(n, beta, seed, aniso=(1.0, 1.0)):
    """Periodisches 1/f^beta-Rauschen (FFT), normiert auf 0..1. aniso streckt die Frequenzen."""
    r = np.random.RandomState(seed)
    w = r.randn(n, n)
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = f ** (-beta)
    amp[0, 0] = 0.0
    a = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    a -= a.min(); a /= a.max()
    return a

def band(n, lo, hi, seed, aniso=(1.0, 1.0)):
    """Bandpass-Rauschen (Perioden zwischen n/hi und n/lo Pixeln)."""
    r = np.random.RandomState(seed)
    w = r.randn(n, n)
    fx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    fy = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    m = np.exp(-((np.log(f + 1e-6) - math.log(math.sqrt(lo * hi))) ** 2) / (2 * (math.log(hi / lo) / 2.5) ** 2))
    a = np.real(np.fft.ifft2(np.fft.fft2(w) * m))
    a = (a - a.mean()) / (a.std() + 1e-9)
    return a

def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nx, ny, nz = -dx, dy, np.ones_like(h)  # OpenGL: Y+ = Bild nach oben
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5], -1)

def tiled_draw(n, draw_fn, mode="L", bg=0):
    """Zeichnet auf 3x3-Leinwand und schneidet die Mitte aus -> nahtlos kachelbar."""
    big = Image.new(mode, (n * 3, n * 3), bg)
    d = ImageDraw.Draw(big)
    draw_fn(d, n)
    return big.crop((n, n, 2 * n, 2 * n))

# ---------------------------------------------------------------- Kraftliner
PX_PER_MM = N / 512.0          # 2 px/mm
FLUTE_MM = 8.0                 # C-Welle
x = np.arange(N)[None, :].repeat(N, 0).astype(np.float64)
y = np.arange(N)[:, None].repeat(N, 1).astype(np.float64)

# Wellen-Abzeichnung: nicht perfekt sinusfoermig, leicht schwankende Phase (Wellpappe ist nie exakt)
phase_wob = band(N, 1, 4, 11) * 0.35
flute = np.cos((x / (FLUTE_MM * PX_PER_MM)) * 2 * math.pi + phase_wob)
flute_ridge = np.power(0.5 + 0.5 * flute, 1.6)          # Grat schmaler als Tal (Liner liegt auf den Spitzen)
wash = flute_ridge * (0.55 + 0.45 * fnoise(N, 1.2, 12))  # Abzeichnung ungleich stark

# Fasern: tausende kurze Striche, Maschinenrichtung leicht bevorzugt (senkrecht zu den Wellen)
def fibers(d, n):
    r = random.Random(5)
    for i in range(52000):
        cx, cy = r.uniform(0, n), r.uniform(0, n)
        L = r.uniform(2.0, 13.0) * (2.2 if r.random() < 0.04 else 1.0)
        a = r.gauss(math.pi / 2, 0.55) if r.random() < 0.75 else r.uniform(0, math.pi)
        dx, dy = math.cos(a) * L / 2, math.sin(a) * L / 2
        v = r.choice([0, 0, 1, 1, 1, 2])
        col = 60 if v == 0 else (200 if v == 1 else 255)   # dunkle, helle, sehr helle Faser
        xs = [n] + ([2 * n] if cx < 16 else []) + ([0] if cx > n - 16 else [])
        ys = [n] + ([2 * n] if cy < 16 else []) + ([0] if cy > n - 16 else [])
        for ox in xs:
            for oy in ys:
                d.line([(ox + cx - dx, oy + cy - dy), (ox + cx + dx, oy + cy + dy)], fill=col, width=1)
fib = np.asarray(tiled_draw(N, fibers, "L", 128), dtype=np.float64) / 255.0
fib = np.asarray(Image.fromarray((fib * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float64) / 255.0
fibd = fib - 0.5                                           # -0.27..+0.5: dunkle und helle Fasern

# Rindenpunkte / Einschluesse (Recycling-Kraft): kleine dunkle Punkte, wenige
def specks(d, n):
    r = random.Random(9)
    for i in range(260):
        cx, cy = r.uniform(0, n), r.uniform(0, n)
        s = r.uniform(0.5, 1.5)
        for ox in (0, n, 2 * n):
            for oy in (0, n, 2 * n):
                d.ellipse([ox + cx - s, oy + cy - s * r.uniform(0.6, 1.4), ox + cx + s, oy + cy + s], fill=255)
spk = np.asarray(tiled_draw(N, specks, "L", 0), dtype=np.float64) / 255.0
spk = np.asarray(Image.fromarray((spk * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float64) / 255.0

mott_lo = fnoise(N, 1.9, 21)      # Wolkigkeit (Formation) gross
mott_hi = band(N, 20, 90, 22)     # Formation fein
base = np.array([0.665, 0.530, 0.385])   # Kraft-Albedo linear-ish (sRGB ~ #A78158)
val = 1.0 + 0.07 * (mott_lo - 0.5) + 0.025 * mott_hi + 0.13 * fibd - 0.035 * wash - 0.22 * spk
hue = 0.03 * (fnoise(N, 2.2, 23) - 0.5)   # leichte Farbschwankung rotbraun <-> gelbbraun
alb = np.stack([base[0] * (val + hue), base[1] * val, base[2] * (val - hue * 1.2)], -1)
save(alb, "liner_albedo.png")

h = 0.9 * wash + 0.20 * fib + 0.15 * band(N, 40, 160, 24) + 0.06 * mott_lo - 0.25 * spk
save(normal_from_height(h, 2.2), "liner_normal.png")
rough = 0.80 + 0.08 * (fib - 0.5) - 0.05 * wash + 0.04 * mott_hi * 0.3
save(rough, "liner_rough.png")

# ---------------------------------------------------------------- Packpapier zerknittert
def voronoi_facets(n, cells, seed, tilt):
    """Periodische Voronoi-Facetten: jede Zelle ist eine schraeg liegende Ebene -> Hoehenfeld + Gratmaske."""
    r = np.random.RandomState(seed)
    pts = r.rand(cells, 2) * n
    gx = r.randn(cells) * tilt; gy = r.randn(cells) * tilt; c0 = r.randn(cells) * tilt * n * 0.05
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    best = np.full((n, n), 1e9, np.float32); second = np.full((n, n), 1e9, np.float32)
    idx = np.zeros((n, n), np.int32)
    for i in range(cells):
        dx = xx - pts[i, 0]; dx -= n * np.round(dx / n)
        dy = yy - pts[i, 1]; dy -= n * np.round(dy / n)
        dd = np.sqrt(dx * dx + dy * dy)
        m1 = dd < best
        second = np.where(m1, best, np.minimum(second, dd))
        idx = np.where(m1, i, idx)
        best = np.where(m1, dd, best)
    # Hoehe: Ebene der Zelle, relativ zum Zellpunkt
    px = pts[idx, 0]; py = pts[idx, 1]
    dx = xx - px; dx -= n * np.round(dx / n)
    dy = yy - py; dy -= n * np.round(dy / n)
    hgt = gx[idx] * dx + gy[idx] * dy + c0[idx]
    edge = second - best                      # 0 auf dem Grat
    return hgt, edge

h1, e1 = voronoi_facets(N, 70, 31, 0.10)
h2, e2 = voronoi_facets(N, 380, 32, 0.07)
ridge = np.exp(-e1 / 2.0) + 0.6 * np.exp(-e2 / 1.4)     # Knickgrate
hc = h1 * 0.6 + h2 * 0.35 + 3.0 * band(N, 30, 200, 33) + 2.0 * ridge
save(normal_from_height(hc, 0.9), "crumple_normal.png")
pbase = np.array([0.70, 0.55, 0.38])
pv = 1.0 + 0.05 * (fnoise(N, 1.8, 34) - 0.5) + 0.06 * fibd + 0.10 * np.clip(ridge, 0, 1.2) - 0.2 * spk
palb = np.stack([pbase[0] * pv, pbase[1] * pv, pbase[2] * pv * 0.99], -1)
save(palb, "crumple_albedo.png")

# ---------------------------------------------------------------- Klebeband-Falten
tn = band(N, 2, 12, 41, aniso=(1.0, 0.12)) * 0.6 + band(N, 10, 60, 42, aniso=(1.0, 0.25)) * 0.25
tn += 0.8 * np.exp(-np.abs(band(N, 3, 9, 43, aniso=(1.0, 0.08))) * 6)   # einzelne Langfalten
save(normal_from_height(tn, 1.4), "tape_normal.png")

# ---------------------------------------------------------------- Druck-/Marker-Atlas (4x4 Zellen a 256 px)
A = Image.new("L", (1024, 1024), 0)
d = ImageDraw.Draw(A)
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FC = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"

def cell(i):
    return (i % 4) * 256, (i // 4) * 256

def marker_text(i, text, size, seed):
    """Edding-Handschrift-Anmutung: Buchstaben einzeln gedreht/versetzt, Strich gerundet."""
    ox, oy = cell(i)
    r = random.Random(seed)
    layer = Image.new("L", (256, 256), 0)
    f = ImageFont.truetype(FC, size)
    xx = 14
    yb = 128 - size // 2 + r.randint(-6, 6)
    for ch in text:
        g = Image.new("L", (size * 2, size * 2), 0)
        ImageDraw.Draw(g).text((size // 2, size // 3), ch, font=f, fill=255)
        g = g.rotate(r.uniform(-9, 9), resample=Image.BICUBIC)
        layer.paste(255, (int(xx) - size // 2, yb + r.randint(-3, 3) - size // 3), g)
        xx += f.getlength(ch) * r.uniform(0.92, 1.05)
    layer = layer.filter(ImageFilter.GaussianBlur(1.6)).point(lambda v: 255 if v > 110 else int(v * 1.6))
    # Marker deckt nicht ueberall gleich (Faser trinkt Tinte)
    A.paste(layer, (ox, oy), layer)

# 0: eigenes "oben"-Zeichen: zwei schlanke Pfeile ohne Rahmen (eigene Form, kein ISO-780-Nachbau)
ox, oy = cell(0)
for k in (0, 1):
    cx = ox + 92 + k * 72
    d.polygon([(cx, oy + 40), (cx + 30, oy + 92), (cx + 11, oy + 92), (cx + 11, oy + 200), (cx - 11, oy + 200), (cx - 11, oy + 92), (cx - 30, oy + 92)], fill=255)
# 1: Gestempeltes Rechteckfeld mit Fantasie-Text (Hersteller-Stempel ohne Marke)
ox, oy = cell(1)
d.rectangle([ox + 20, oy + 60, ox + 236, oy + 196], outline=255, width=7)
d.text((ox + 36, oy + 74), "KARTON 3W", font=ImageFont.truetype(FB, 26), fill=255)
d.text((ox + 36, oy + 112), "C-WELLE  BC", font=ImageFont.truetype(FC, 22), fill=255)
d.text((ox + 36, oy + 146), "40 x 30 x 30", font=ImageFont.truetype(FC, 24), fill=255)
# 2: Glas-Symbol eigener Form (Kelch als Strichzeichnung)
ox, oy = cell(2)
d.arc([ox + 78, oy + 30, ox + 178, oy + 140], 0, 180, fill=255, width=14)
d.line([(ox + 78, oy + 84), (ox + 78, oy + 40)], fill=255, width=14); d.line([(ox + 178, oy + 84), (ox + 178, oy + 40)], fill=255, width=14)
d.line([(ox + 128, oy + 140), (ox + 128, oy + 206)], fill=255, width=14)
d.line([(ox + 92, oy + 210), (ox + 164, oy + 210)], fill=255, width=14)
# 3: Recyclingfreier Fantasie-Strichcode-Streifen (keine echte Kodierung)
ox, oy = cell(3)
r = random.Random(3); xx = ox + 24
while xx < ox + 232:
    w = r.choice([3, 3, 5, 8]); d.rectangle([xx, oy + 90, xx + w, oy + 170], fill=255); xx += w + r.choice([3, 4, 6])
# 4-11: Umzugs-Handschrift
for i, (t, s) in enumerate([("BÜCHER", 46), ("KÜCHE", 52), ("BAD", 64), ("WINTER", 46), ("DIVERSES", 38), ("OBEN!", 54), ("GLAS", 60), ("FLUR", 60)]):
    marker_text(4 + i, t, s, 100 + i)
# 12: Pfeil von Hand
ox, oy = cell(12)
d.line([(ox + 30, oy + 140), (ox + 200, oy + 118)], fill=255, width=12)
d.line([(ox + 200, oy + 118), (ox + 160, oy + 86)], fill=255, width=12); d.line([(ox + 200, oy + 118), (ox + 168, oy + 158)], fill=255, width=12)
# 13: Kreuz (durchgestrichen) – alter Inhalt
ox, oy = cell(13)
d.line([(ox + 30, oy + 60), (ox + 220, oy + 190)], fill=255, width=10); d.line([(ox + 40, oy + 190), (ox + 214, oy + 70)], fill=255, width=10)
# 14: Nummernkreis "7"
ox, oy = cell(14)
d.ellipse([ox + 50, oy + 50, ox + 206, oy + 206], outline=255, width=11)
d.text((ox + 98, oy + 70), "7", font=ImageFont.truetype(FB, 96), fill=255)
# 15: Bleistift-Massangabe (duenn, fuer Modellbau J)
ox, oy = cell(15)
d.line([(ox + 20, oy + 128), (ox + 236, oy + 128)], fill=170, width=3)
d.line([(ox + 20, oy + 110), (ox + 20, oy + 146)], fill=170, width=3); d.line([(ox + 236, oy + 110), (ox + 236, oy + 146)], fill=170, width=3)
d.text((ox + 96, oy + 88), "42", font=ImageFont.truetype(FC, 34), fill=170)

# Druck nie voll deckend: Wellen-Abzeichnung und Faserstruktur fressen Tinte
wear = (fnoise(1024, 2.0, 51) * 0.35 + 0.72)
a = np.asarray(A, dtype=np.float64) / 255.0 * np.clip(wear, 0, 1)
save(a, "prints.png")
print("pappe_pbr ok ->", OUT)
