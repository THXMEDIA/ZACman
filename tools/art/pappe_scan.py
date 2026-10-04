# Foto-Ebene der Explorer-Stadt Amsterdam (Richtung J v2 "Pappmodell Amsterdam", Art Director,
# 04.10.2026; uebernommen aus tools/art/explorer_proto/tools/pappe_scan.py, Branch art/explorer-stile).
#
# Baut aus ECHTEN, frei lizenzierten Fotoscans (CC0, Quellen siehe docs/art/lizenzen.md) die
# Texturen unter godot/textures/amsterdam/. Die Originale liegen NICHT im Repo; eingecheckt sind
# nur die hier erzeugten Ableitungen.
#
# Aufruf:
#   python3 tools/art/pappe_scan.py <quellordner> <zielordner> [1k|2k|4k]
#   (Ziel im Spiel: godot/textures/amsterdam; Austausch-Anleitung in docs/design/amsterdam-explorer.md)
# Die Aufloesung (Standard 1k) waehlt die Quelldateien und die Groesse der Ausgabe (1024/2048/4096 px);
# die Ausschnitt-Koordinaten im Karton-Atlas skalieren mit.
# Erwartet im Quellordner (Dateinamen wie beim Anbieter, <res> = 1k/2k/4k):
#   cardboard_box_01_diff_<res>.jpg, cardboard_box_01_nor_gl_<res>.jpg, cardboard_box_01_arm_<res>.jpg
#       Poly Haven "Cardboard Box 01" (Rahul Chaudhary), CC0 – https://polyhaven.com/a/cardboard_box_01
#   Wood095_diffuse.jpg, Wood095_normal.jpg, Wood095_roughness.jpg
#       ambientCG "Wood095" (Lennart Demes), CC0 – https://ambientcg.com/view?id=Wood095
#   photo_studio_loft_hall_2k.hdr, comfy_cafe_2k.hdr, studio_small_05_1k.hdr
#       Poly Haven HDRIs, CC0 – https://polyhaven.com/hdris
#
# Schreibt:
#   kraft_foto_albedo.jpg / _normal.jpg / _rough.jpg   1024 px, kachelbar: Patchwork ("Texture
#       Bombing") aus sauberen Flaechen des Karton-Scans – echte Flecken, Knicke, Abrieb, Farbstreuung.
#       Die Grossbeleuchtung des Scans wird herausgerechnet (Division durch starke Unschaerfe).
#   tape_foto_albedo.jpg / _normal.jpg                  512x128, Klebeband-Streifen aus dem Scan
#       (Band ueber Karton, laengs kachelbar).
#   holz_albedo.jpg / _normal.jpg / _rough.jpg          Tischplatte (Wood095, unveraendert, 1024x512).
#   hdri_tag/warm/studio.hdr                            1024x512 Umgebungen (2K-Dateien halbiert).
import os, sys, math
import numpy as np
from PIL import Image, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
RES = sys.argv[3] if len(sys.argv) > 3 else "1k"
K = {"1k": 1, "2k": 2, "4k": 4}[RES]   # Massstab der Atlas-Koordinaten (gemessen am 1K-Scan)
os.makedirs(OUT, exist_ok=True)
rs = np.random.RandomState(1675)

def load(n):
    return np.asarray(Image.open(os.path.join(SRC, n)).convert("RGB")).astype(np.float32) / 255.0

def rot45(a):
    """Atlas des Scans liegt diagonal: 45 Grad gegen den Uhrzeigersinn drehen (wie PIL rotate)."""
    im = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))
    return np.asarray(im.rotate(45, resample=Image.BICUBIC, expand=True)).astype(np.float32) / 255.0

def rot_normal(n, deg):
    """Normalmap-Bild drehen: auch die XY-Vektoren mitdrehen (OpenGL, Y+ = oben)."""
    r = rot45(n)
    v = r * 2.0 - 1.0
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    x = v[..., 0] * c - v[..., 1] * s
    y = v[..., 0] * s + v[..., 1] * c
    out = np.stack([x, y, v[..., 2]], -1)
    out /= np.linalg.norm(out, axis=-1, keepdims=True) + 1e-6
    return out * 0.5 + 0.5

def blur(a, r):
    from scipy.ndimage import gaussian_filter
    return np.stack([gaussian_filter(a[..., k], r, mode="nearest") for k in range(a.shape[2])], -1)

def save(a, name, q=92):
    im = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))
    if name.endswith(".jpg"):
        im.save(os.path.join(OUT, name), quality=q, subsampling=0)
    else:
        im.save(os.path.join(OUT, name))

# ------------------------------------------------------------------ Karton-Scan
diff = rot45(load("cardboard_box_01_diff_%s.jpg" % RES))
nor = rot_normal(load("cardboard_box_01_nor_gl_%s.jpg" % RES), 45.0)
arm = rot45(load("cardboard_box_01_arm_%s.jpg" % RES))

# Beleuchtung/Grossverlauf des Scans herausrechnen, Detail und Farbe behalten
lin = diff ** 2.2
low = blur(lin, 45 * K)
mean = lin[590 * K:690 * K, 1005 * K:1240 * K].reshape(-1, 3).mean(0)
flat = lin / np.maximum(low, 1e-3) * mean
flat = 0.75 * flat + 0.25 * lin * (mean / np.maximum(low.reshape(-1, 3).mean(0), 1e-3))

# Saubere Flaechen im gedrehten Atlas (x0, y0, x1, y1), Gewicht. Ohne Schrift, Symbole, Risse.
PATCHES = [
    ((1005, 585, 1115, 695), 2.0),   # rechte Seitenwand oben, links der weissen Kante
    ((1132, 585, 1240, 695), 2.0),   # ... rechts davon
    ((1005, 790, 1115, 905), 2.0),   # rechte Seitenwand unten
    ((1132, 790, 1240, 905), 2.0),
    ((740, 312, 845, 430), 1.5),     # Deckelklappe, Knicke
    ((925, 312, 1015, 430), 1.0),
    ((745, 458, 1010, 545), 2.0),    # Klappe mit Knickfalten
    ((830, 935, 970, 1050), 1.2),    # untere Klappe
    ((195, 560, 315, 870), 0.8),     # abgegriffene Flanke (grauer, Abrieb)
]
TAPE = [(605, 697, 722, 778), (872, 697, 995, 778)]
PATCHES = [(tuple(v * K for v in box), w) for box, w in PATCHES]
TAPE = [tuple(v * K for v in box) for box in TAPE]

N = 1024 * K
alb = np.zeros((N, N, 3), np.float32) + mean
nrm = np.zeros((N, N, 3), np.float32) + np.array([0.5, 0.5, 1.0])
rgh = np.zeros((N, N), np.float32) + 0.85
cov = np.zeros((N, N), np.float32)
wsum = sum(w for _, w in PATCHES)

def feather(h, w, f):
    y = np.minimum(np.arange(h), np.arange(h)[::-1])[:, None]
    x = np.minimum(np.arange(w), np.arange(w)[::-1])[None, :]
    return np.clip(np.minimum(x, y) / f, 0, 1) ** 1.5

for it in range(420):
    pick = rs.rand() * wsum
    for (box, w) in PATCHES:
        pick -= w
        if pick <= 0:
            break
    x0, y0, x1, y1 = box
    pw = min(x1 - x0, rs.randint(80, 160) * K)
    ph = min(y1 - y0, rs.randint(80, 160) * K)
    sx = rs.randint(x0, x1 - pw + 1)
    sy = rs.randint(y0, y1 - ph + 1)
    pa = flat[sy:sy + ph, sx:sx + pw].copy()
    pn = nor[sy:sy + ph, sx:sx + pw].copy()
    pr = arm[sy:sy + ph, sx:sx + pw, 1].copy()
    if rs.rand() < 0.5:   # 180 Grad (Wellenrichtung bleibt senkrecht)
        pa = pa[::-1, ::-1]; pr = pr[::-1, ::-1]
        pn = pn[::-1, ::-1].copy(); pn[..., 0] = 1.0 - pn[..., 0]; pn[..., 1] = 1.0 - pn[..., 1]
    # Patches auf den Gesamtmittelwert ziehen (sonst Flickenteppich), Rest Streuung behalten
    pm = pa.reshape(-1, 3).mean(0)
    pa = pa * (0.55 + 0.45 * (mean / np.maximum(pm, 1e-4))) / (0.55 + 0.45)
    pa *= 0.93 + 0.14 * rs.rand()
    m = feather(ph, pw, 18.0 * K)
    # bevorzugt dort setzen, wo noch wenig bedeckt ist
    best = None
    for _ in range(6):
        tx, ty = rs.randint(0, N), rs.randint(0, N)
        ys = (np.arange(ph) + ty) % N
        xs = (np.arange(pw) + tx) % N
        c = cov[np.ix_(ys, xs)].mean()
        if best is None or c < best[0]:
            best = (c, ys, xs)
    _, ys, xs = best
    ix = np.ix_(ys, xs)
    mm = m[..., None]
    alb[ix] = alb[ix] * (1 - mm) + pa * mm
    nrm[ix] = nrm[ix] * (1 - mm) + pn * mm
    rgh[ix] = rgh[ix] * (1 - m) + pr * m
    cov[ix] = np.maximum(cov[ix], m)

nv = nrm * 2 - 1
nv /= np.linalg.norm(nv, axis=-1, keepdims=True) + 1e-6
save(np.clip(alb, 0, 1) ** (1 / 2.2), "kraft_foto_albedo.jpg")
save(nv * 0.5 + 0.5, "kraft_foto_normal.jpg", 95)
save(np.repeat(rgh[..., None], 3, -1), "kraft_foto_rough.jpg")
print("kraft mean sRGB", (mean ** (1 / 2.2) * 255).astype(int), "coverage", float((cov > 0.5).mean()))

# ------------------------------------------------------------------ Klebeband-Streifen
parts_a, parts_n = [], []
for (x0, y0, x1, y1) in TAPE:
    parts_a.append(diff[y0:y1, x0:x1])
    parts_n.append(nor[y0:y1, x0:x1])
ta = np.concatenate(parts_a, 1)
tn = np.concatenate(parts_n, 1)
th, tw = ta.shape[:2]
# laengs kachelbar: Enden ueberblenden
ov = 40 * K
blend = np.linspace(0, 1, ov)[None, :, None]
ta2 = ta[:, ov:].copy(); tn2 = tn[:, ov:].copy()
ta2[:, -ov:] = ta[:, -ov:] * (1 - blend) + ta[:, :ov] * blend
tn2[:, -ov:] = tn[:, -ov:] * (1 - blend) + tn[:, :ov] * blend
ti = Image.fromarray((np.clip(ta2, 0, 1) * 255).astype(np.uint8)).resize((512 * K, 128 * K), Image.LANCZOS)
tni = Image.fromarray((np.clip(tn2, 0, 1) * 255).astype(np.uint8)).resize((512 * K, 128 * K), Image.LANCZOS)
ti.save(os.path.join(OUT, "tape_foto_albedo.jpg"), quality=92)
tni.save(os.path.join(OUT, "tape_foto_normal.jpg"), quality=95)

# ------------------------------------------------------------------ Holz (Tischplatte)
for n, o in [("Wood095_diffuse.jpg", "holz_albedo.jpg"), ("Wood095_normal.jpg", "holz_normal.jpg"), ("Wood095_roughness.jpg", "holz_rough.jpg")]:
    Image.open(os.path.join(SRC, n)).convert("RGB").save(os.path.join(OUT, o), quality=92)

# ------------------------------------------------------------------ HDRIs (RGBE lesen/schreiben)
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
    H, W = a.shape[:2]
    with open(path, "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (H, W))
        f.write(rgbe.tobytes())   # unkomprimierte Zeilen (von Godot gelesen)

# Im Spiel wird nur hdri_warm (Abendlook) gebraucht; fehlende HDRIs werden uebersprungen.
for n, o in [("photo_studio_loft_hall_2k.hdr", "hdri_tag.hdr"), ("comfy_cafe_2k.hdr", "hdri_warm.hdr"),
             ("studio_small_05_1k.hdr", "hdri_studio.hdr")]:
    if not os.path.exists(os.path.join(SRC, n)):
        continue
    a = read_hdr(os.path.join(SRC, n))
    if a.shape[1] > 1024 * K:
        a = a.reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2, 3).mean((1, 3))
    write_hdr(os.path.join(OUT, o), a)
    print(o, a.shape, float(a.mean()))
