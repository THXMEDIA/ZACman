# Style-Tiles und Capsule-Mockups fuer die Explorer-Stil-Prototypen (Pillow, keine Fremdbilder).
# Aufruf: python3 tiles.py  (liest die Godot-Screenshots aus $OUT, schreibt daneben)
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

B = os.environ.get("OUT", "/tmp/claude-0/-home-claude/1aaa4092-a4a3-5e5c-b391-8d187e585776/scratchpad/explorer_shots")
INTER = "/usr/share/fonts/opentype/inter/Inter-%s.otf"
LORA = "/usr/share/fonts/truetype/google-fonts/Lora-Variable.ttf"
LORA_I = "/usr/share/fonts/truetype/google-fonts/Lora-Italic-Variable.ttf"
POPPINS = "/usr/share/fonts/truetype/google-fonts/Poppins-%s.ttf"
CHORUS = "/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyrechorus-mediumitalic.otf"
MONOB = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
JOST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "himmelsbrunn_kulisse", "fonts", "Jost-%s.ttf")  # 500-Medium, 700-Bold (SIL OFL)

def F(p, s):
    return ImageFont.truetype(p, s)

def rgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def noise_img(size, scale, seed):
    random.seed(seed)
    w, h = size
    small = Image.new("L", (max(2, w // scale), max(2, h // scale)))
    small.putdata([random.randint(0, 255) for _ in range(small.size[0] * small.size[1])])
    return small.resize(size, Image.BICUBIC)

# ---------- Stil-Primitive (Pillow) ----------
def wash_blob(img, box, col, paper, seed=1, alpha=0.85):
    """Aquarell-Lasur: weiche Form mit Randverdunkelung und Granulation."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    layer = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(layer)
    random.seed(seed)
    pts = []
    n = 14
    for i in range(n):
        a = i / n * 2 * math.pi
        r = 0.42 + random.uniform(-0.06, 0.06)
        pts.append((w / 2 + math.cos(a) * r * w, h / 2 + math.sin(a) * r * h))
    d.polygon(pts, fill=255)
    layer = layer.filter(ImageFilter.GaussianBlur(3))
    inner = layer.filter(ImageFilter.GaussianBlur(10))
    edge = ImageChops.subtract(layer, inner)  # Pigmentrand
    gran = noise_img((w, h), 6, seed)
    colimg = Image.new("RGB", (w, h), col)
    dark = tuple(int(c * 0.72) for c in col)
    colimg = Image.composite(Image.new("RGB", (w, h), dark), colimg, edge.point(lambda v: min(255, v * 3)))
    mask = ImageChops.multiply(layer, gran.point(lambda v: int(140 + v * 0.45)))
    mask = mask.point(lambda v: int(v * alpha))
    img.paste(colimg, (x0, y0), mask)

def ink_line(d, pts, col, width=3, seed=1):
    random.seed(seed)
    for i in range(len(pts) - 1):
        if random.random() < 0.18:
            continue  # Linie reisst ab
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        d.line([(xa + random.uniform(-1.5, 1.5), ya + random.uniform(-1.5, 1.5)), (xb, yb)], fill=col, width=width)

def impasto_rect(img, box, cols, angle_deg, seed=1, length=26, width=7):
    """Impasto-Striche: Zellen mit fester Richtung, dunkle Luecken, Glanzkante."""
    x0, y0, x1, y1 = box
    random.seed(seed)
    layer = Image.new("RGB", (x1 - x0, y1 - y0), tuple(int(c * 0.45) for c in cols[0]))
    d = ImageDraw.Draw(layer)
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    px, py = -dy, dx
    W, H = layer.size
    diag = int(math.hypot(W, H))
    for row in range(-diag // width, diag // width):
        off = random.uniform(0, length)
        for k in range(-diag // length - 1, diag // length + 1):
            s0 = k * length + off
            L = length * random.uniform(0.6, 1.3)
            cx = W / 2 + dx * s0 + px * row * width
            cy = H / 2 + dy * s0 + py * row * width
            col = random.choice(cols)
            col = tuple(min(255, int(c * random.uniform(0.8, 1.12))) for c in col)
            d.line([(cx, cy), (cx + dx * L * 0.9, cy + dy * L * 0.9)], fill=col, width=width - 2)
            hi = tuple(min(255, int(c * 1.25)) for c in col)
            d.line([(cx - px, cy - py), (cx + dx * L * 0.9 - px, cy + dy * L * 0.9 - py)], fill=hi, width=1)
    img.paste(layer, (x0, y0))

def halftone_rect(img, box, paper, ink, cov, cell=8, seed=0):
    """Ben-Day-Raster: Punktgroesse nach Deckung, 45 Grad gedreht."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    layer = Image.new("RGB", (W, H), paper)
    d = ImageDraw.Draw(layer)
    r = math.sqrt(max(cov, 0.0)) * 0.56 * cell
    if r > 0.3:
        step = cell
        for j in range(-H, H * 2, step):
            for i in range(-W, W * 2, step):
                # Rotation 45 Grad
                x = (i - j) * 0.7071 + W / 2
                y = (i + j) * 0.7071 + H / 2 - W / 2
                if -cell < x < W + cell and -cell < y < H + cell:
                    d.ellipse([x - r, y - r, x + r, y + r], fill=ink)
    img.paste(layer, (x0, y0))

def gradient_halftone(img, box, paper, ink, cell=8):
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    layer = Image.new("RGB", (W, H), paper)
    d = ImageDraw.Draw(layer)
    for j in range(-H, H * 2, cell):
        for i in range(-W, W * 2, cell):
            x = (i - j) * 0.7071 + W / 2
            y = (i + j) * 0.7071 + H / 2 - W / 2
            if -cell < x < W + cell and -cell < y < H + cell:
                cov = 1.0 - y / H
                r = math.sqrt(max(cov, 0)) * 0.56 * cell
                d.ellipse([x - r, y - r, x + r, y + r], fill=ink)
    img.paste(layer, (x0, y0))

def starburst(d, cx, cy, ro, ri, n, fill, outline, width=4):
    pts = []
    for i in range(n * 2):
        a = i / (n * 2) * 2 * math.pi
        r = ro if i % 2 == 0 else ri
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.75))
    d.polygon(pts, fill=fill, outline=outline, width=width)

def text_outline(d, xy, text, font, fill, outline, w=4):
    x, y = xy
    for ox in range(-w, w + 1, 2):
        for oy in range(-w, w + 1, 2):
            d.text((x + ox, y + oy), text, font=font, fill=outline)
    d.text((x, y), text, font=font, fill=fill)

# ---------- Richtungen ----------
DIRS = {
 "paris_aquarell": dict(
   title="A  AQUARELL-PARIS", city="PARIS · SEINE-UFER",
   idea="Tusche-Linie und Lasur auf Papier: Haussmann-Fassaden in Creme, lila Schatten, Zink-Daecher; Ferne verblasst ins Papierweiss.",
   bg="#F7F2E8", fg="#4A3B2E",
   pal=[("#F7F2E8","Papier (Himmel, Grundton)"),("#E6D2AC","Stein warm"),("#CDBCC9","Schatten lila"),("#7F8A99","Zink / Daecher"),
        ("#4E5C70","Fenster"),("#4A3B2E","Tusche Sepia"),("#7E9DB8","Seine"),("#8E4A52","Markisen Bordeaux"),
        ("#F5A623","Kugeln (exklusiv)"),("#1FA463","U-Bahn (exklusiv)")],
   fonts=[("Lora (SIL OFL 1.1, Google Fonts)", "Titel, Ortsnamen"), ("Inter (SIL OFL 1.1)", "UI, HUD")],
   shot="strasse.png"),
 "arles_sternennacht": dict(
   title="B  STERNENNACHT UEBER ARLES", city="ARLES · PLACE DU FORUM, NACHT",
   idea="Wirbelnder Nachthimmel aus animierten Stroemungslinien, Impasto-Striche auf allen Flaechen, Sterne und Gaslaternen als Halo-Scheiben.",
   bg="#141D4A", fg="#F6E9B8",
   pal=[("#1B2A6B","Himmel Ultramarin"),("#2F55A8","Himmel Kobalt (Strich)"),("#7FB2E5","Strich hell"),("#F6C945","Chromgelb (Sterne, Licht)"),
        ("#E8862A","Halo-Rand Orange"),("#4B4A86","Fassade Nachtviolett"),("#B88A3C","Fassade Ocker"),("#102520","Zypressen"),
        ("#FF4A1C","Kugeln Zinnober (exklusiv)"),("#39FF6A","U-Bahn (exklusiv)")],
   fonts=[("TeX Gyre Chorus (GUST Font License, frei) – Platzhalter; Empfehlung: Caveat Brush (SIL OFL)", "Titel, Ortsnamen"), ("Inter (SIL OFL 1.1)", "UI, HUD")],
   shot="strasse.png"),
 "himmelsbrunn_kulisse": dict(
   title="D  KULISSENSTADT HIMMELSBRUNN", city="HIMMELSBRUNN · KURHAUS-ACHSE",
   idea="Fiktiver Kurort als Modellbau: jede Strasse eine symmetrische Achse auf ein Kurhaus, Fassaden als Kulissen, Pastell, flaches Licht, Schilder.",
   bg="#FAEFD9", fg="#25365C",
   pal=[("#F2B5A0","Fassade Lachs"),("#E7A1AE","Fassade Altrosa"),("#BCA9D3","Fassade Lavendel"),("#A9C6DE","Fassade Puder"),("#F3D9A4","Fassade Vanille"),
        ("#8E2F3C","Zierleiste Bordeaux"),("#25365C","Zierleiste/Schild Navy"),("#6B4A63","Innenraum"),("#FFC20E","Kugeln (exklusiv)"),("#1AA85C","Standseilbahn (exklusiv)")],
   fonts=[("Jost Bold/Medium (SIL OFL 1.1, github.com/indestructible-type/Jost)", "Titel, Schilder, HUD – freie Alternative zu Futura")],
   shot="strasse.png"),
 "miami_popart": dict(
   title="C  DRUCKFARBEN-MIAMI", city="MIAMI · OCEAN DRIVE",
   idea="Vierfarbdruck: Papierweiss, Schwarz, Cyan, Rot – Toene nur aus Rasterpunkten, dicke Konturen, Art-Deco-Kaesten, eigene Comic-Elemente (ZAP!).",
   bg="#FFFDF5", fg="#111111",
   pal=[("#FFFDF5","Papier"),("#111111","Schwarz: Kontur, Raster"),("#00A3E0","Cyan: Himmel, Meer, Glas"),("#E4002B","Rot: Akzente, Rosa-Raster"),
        ("#FFD500","Gelb: Kugeln (exklusiv)"),("#00C853","Gruen: U-Bahn (exklusiv)")],
   fonts=[("Poppins Bold (SIL OFL 1.1, Google Fonts)", "Titel, Schilder"), ("Inter Black (SIL OFL 1.1)", "ZAP!, HUD"), ("Empfehlung Titel: Bangers (SIL OFL)", "")],
   shot="strasse.png"),
}

def tile(key, D):
    W, H = 1600, 1000
    img = Image.new("RGB", (W, H), rgb(D["bg"]))
    d = ImageDraw.Draw(img)
    fg = rgb(D["fg"])
    dim = tuple(int(c * 0.75 + rgb(D["bg"])[i] * 0.25) for i, c in enumerate(fg))
    if key == "paris_aquarell":
        # Papierkorn
        g = noise_img((W, H), 3, 5).point(lambda v: 235 + v // 12)
        img = ImageChops.multiply(img, Image.merge("RGB", (g, g, g)))
        d = ImageDraw.Draw(img)
        d.text((60, 40), D["title"], font=F(LORA, 54), fill=fg)
    elif key == "arles_sternennacht":
        d.text((60, 40), D["title"], font=F(CHORUS, 60), fill=fg)
    elif key == "himmelsbrunn_kulisse":
        d.text((60, 40), D["title"], font=F(JOST % "700-Bold", 52), fill=fg)
    else:
        text_outline(d, (60, 40), D["title"], F(POPPINS % "Bold", 54), rgb("#FFFDF5"), fg, 4)
    d.text((60, 112), D["idea"], font=F(INTER % "Regular", 22), fill=dim)
    # Palette
    x, y = 60, 170
    for i, (h, role) in enumerate(D["pal"]):
        cx = x + (i % 5) * 160; cy = y + (i // 5) * 150
        d.rectangle([cx, cy, cx + 136, cy + 84], fill=rgb(h), outline=fg if key == "miami_popart" else dim, width=3 if key == "miami_popart" else 1)
        d.text((cx, cy + 90), h.upper(), font=F(MONOB, 16), fill=fg)
        d.text((cx, cy + 110), role, font=F(INTER % "Regular", 12), fill=dim)
    # Beispielformen
    sx, sy = 60, 490
    d.text((sx, sy), "Beispielformen", font=F(INTER % "SemiBold", 18), fill=dim)
    if key == "paris_aquarell":
        wash_blob(img, (sx, sy + 30, sx + 220, sy + 170), rgb("#E6D2AC"), rgb(D["bg"]), 3)
        wash_blob(img, (sx + 240, sy + 30, sx + 460, sy + 170), rgb("#7E9DB8"), rgb(D["bg"]), 4)
        wash_blob(img, (sx + 480, sy + 30, sx + 700, sy + 170), rgb("#CDBCC9"), rgb(D["bg"]), 5)
        d = ImageDraw.Draw(img)
        ink_line(d, [(sx + 10, sy + 160), (sx + 60, sy + 40), (sx + 200, sy + 42), (sx + 210, sy + 165)], fg, 3, 7)
        ink_line(d, [(sx + 250, sy + 100), (sx + 450, sy + 95)], fg, 2, 8)
    elif key == "arles_sternennacht":
        impasto_rect(img, (sx, sy + 30, sx + 220, sy + 170), [rgb("#4B4A86"), rgb("#3C3B72"), rgb("#8A86C4")], 8, 3)
        impasto_rect(img, (sx + 240, sy + 30, sx + 460, sy + 170), [rgb("#2F55A8"), rgb("#1B2A6B"), rgb("#7FB2E5"), rgb("#F6C945")], -20, 4, 34, 6)
        impasto_rect(img, (sx + 480, sy + 30, sx + 700, sy + 170), [rgb("#B88A3C"), rgb("#9C7030"), rgb("#E0B45A")], 85, 5, 22, 7)
        d = ImageDraw.Draw(img)
        # Halo-Scheibe
        cx, cy = sx + 775, sy + 100
        for r, col in [(60, "#E8862A"), (52, "#F6C945"), (38, "#F6C945"), (24, "#FFF3B0")]:
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgb(col), outline=rgb("#C98A2E"), width=2)
    elif key == "himmelsbrunn_kulisse":
        # Frontale Fassaden-Ansicht (Aufriss), streng symmetrisch, mit Ausschnitten
        for hx, col in [(sx, "#F2B5A0"), (sx + 150, "#BCA9D3"), (sx + 300, "#F3D9A4")]:
            d.rectangle([hx, sy + 50, hx + 130, sy + 170], fill=rgb(col))
            for f in range(3):
                for k in range(3):
                    wx = hx + 14 + k * 40; wy = sy + 62 + f * 36
                    d.rectangle([wx, wy, wx + 22, wy + 24], fill=rgb("#6B4A63"))
                    d.rectangle([wx - 3, wy + 24, wx + 25, wy + 27], fill=rgb("#8E2F3C"))
            d.polygon([(hx, sy + 50), (hx + 65, sy + 22), (hx + 130, sy + 50)], fill=rgb(col))
            d.rectangle([hx - 3, sy + 46, hx + 133, sy + 51], fill=rgb("#8E2F3C"))
        # Schild + Markise
        d.rectangle([sx + 470, sy + 40, sx + 700, sy + 84], fill=rgb("#25365C"))
        d.text((sx + 498, sy + 46), "SCHIRMMACHER", font=F(JOST % "700-Bold", 24), fill=rgb("#FBF6EC"))
        for k in range(8):
            d.polygon([(sx + 470 + k * 29, sy + 94), (sx + 499 + k * 29, sy + 94), (sx + 495 + k * 29, sy + 140), (sx + 474 + k * 29, sy + 140)], fill=rgb("#F2B5A0") if k % 2 else rgb("#FBF6EC"))
        # Wegweiser
        d.rectangle([sx + 712, sy + 40, sx + 860, sy + 66], fill=rgb("#FBF6EC"), outline=rgb("#25365C"), width=2)
        d.polygon([(sx + 720, sy + 60), (sx + 728, sy + 46), (sx + 736, sy + 60)], fill=rgb("#1AA85C")); d.text((sx + 742, sy + 42), "SEILBAHN", font=F(JOST % "700-Bold", 18), fill=rgb("#1AA85C"))
        d.rectangle([sx + 712, sy + 72, sx + 860, sy + 98], fill=rgb("#FBF6EC"), outline=rgb("#25365C"), width=2)
        d.polygon([(sx + 720, sy + 92), (sx + 728, sy + 78), (sx + 736, sy + 92)], fill=rgb("#25365C")); d.text((sx + 742, sy + 74), "KURHAUS", font=F(JOST % "700-Bold", 18), fill=rgb("#25365C"))
        d.rectangle([sx + 783, sy + 98, sx + 789, sy + 170], fill=rgb("#25365C"))
    else:
        halftone_rect(img, (sx, sy + 30, sx + 220, sy + 170), rgb("#FFFDF5"), rgb("#00A3E0"), 0.25, 9)
        halftone_rect(img, (sx + 240, sy + 30, sx + 460, sy + 170), rgb("#FFFDF5"), rgb("#E4002B"), 0.3, 9)
        gradient_halftone(img, (sx + 480, sy + 30, sx + 700, sy + 170), rgb("#FFFDF5"), rgb("#00A3E0"), 9)
        d = ImageDraw.Draw(img)
        for bx in [(sx, sy + 30, sx + 220, sy + 170), (sx + 240, sy + 30, sx + 460, sy + 170), (sx + 480, sy + 30, sx + 700, sy + 170)]:
            d.rectangle(bx, outline=fg, width=5)
        starburst(d, sx + 775, sy + 100, 74, 50, 12, rgb("#E4002B"), fg, 5)
        text_outline(d, (sx + 728, sy + 78), "ZAP!", F(INTER % "Black", 40), rgb("#FFFDF5"), fg, 4)
    # Rollen: Kugel, U-Bahn-Marker, HUD-Chip
    rx, ry = 60, 700
    d.text((rx, ry), "Kugel · U-Bahn-Marker · HUD-Chip", font=F(INTER % "SemiBold", 18), fill=dim)
    kug = rgb(D["pal"][-2][0]); met = rgb(D["pal"][-1][0])
    for k in range(4):
        cx = rx + 40 + k * 60; cy = ry + 70
        d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=kug, outline=fg if key == "miami_popart" else None, width=4)
        core = tuple(min(255, int(c * 0.5 + 128)) for c in kug)
        if key != "miami_popart":
            d.ellipse([cx - 8, cy - 10, cx + 6, cy + 4], fill=core)
    # U-Bahn: gefuellte Flaeche + Schriftzug
    d.rectangle([rx + 300, ry + 35, rx + 440, ry + 110], fill=met, outline=fg if key == "miami_popart" else None, width=5)
    lab = "MÉTRO" if key in ("paris_aquarell", "arles_sternennacht") else ("METRO" if key == "miami_popart" else "SEILBAHN")
    fnt = F(LORA, 26) if key == "paris_aquarell" else (F(CHORUS, 30) if key == "arles_sternennacht" else (F(JOST % "700-Bold", 21) if key == "himmelsbrunn_kulisse" else F(POPPINS % "Bold", 26)))
    d.text((rx + 318, ry + 55), lab, font=fnt, fill=rgb(D["bg"]) if key != "arles_sternennacht" else rgb("#0B2A14"))
    # HUD-Chip
    chip_bg = {"paris_aquarell": rgb("#3A2F27"), "arles_sternennacht": rgb("#0E1540"), "himmelsbrunn_kulisse": rgb("#25365C")}.get(key, rgb("#111111"))
    d.rounded_rectangle([rx + 500, ry + 40, rx + 820, ry + 104], 14 if key != "miami_popart" else 0, fill=chip_bg, outline=fg if key == "miami_popart" else None, width=4)
    d.text((rx + 520, ry + 56), "EXPLORER", font=F(INTER % "Bold", 20), fill=rgb("#F7F2E8"))
    d.text((rx + 650, ry + 56), D["city"].split(" · ")[0], font=F(INTER % "Regular", 20), fill=kug)
    # Schrift
    ty = 840
    d.text((60, ty), "Schrift", font=F(INTER % "SemiBold", 18), fill=dim)
    if key == "paris_aquarell":
        d.text((60, ty + 24), "Paris, Seine-Ufer", font=F(LORA_I, 46), fill=fg)
    elif key == "arles_sternennacht":
        d.text((60, ty + 20), "Arles, Place du Forum", font=F(CHORUS, 54), fill=fg)
    elif key == "himmelsbrunn_kulisse":
        d.text((60, ty + 24), "KURHAUS HIMMELSBRUNN", font=F(JOST % "700-Bold", 46), fill=fg)
    else:
        text_outline(d, (60, ty + 24), "MIAMI OCEAN DRIVE", F(POPPINS % "Bold", 44), rgb("#FFFDF5"), fg, 4)
    yy = ty + 86
    for fname, use in D["fonts"]:
        d.text((60, yy), ("%s — %s" % (fname, use)) if use else fname, font=F(INTER % "Regular", 15), fill=fg)
        yy += 20
    # Szenenausschnitt
    sh = Image.open(os.path.join(B, key, D["shot"])).convert("RGB").resize((640, 360))
    img.paste(sh, (W - 640 - 60, H - 360 - 110))
    d = ImageDraw.Draw(img)
    if key == "miami_popart":
        d.rectangle([W - 640 - 60, H - 360 - 110, W - 60, H - 110], outline=fg, width=5)
    d.text((W - 640 - 60, H - 100), "Godot-4.3-Prototyp, Compatibility-Renderer (Software), 1280x720", font=F(INTER % "Regular", 14), fill=dim)
    img.save(os.path.join(B, key, "styletile.png"))

def capsule(key, D):
    src = Image.open(os.path.join(B, key, "capsule.png")).convert("RGB")
    # 1280x598 Ausschnitt im Verhaeltnis 460:215
    crop = src.crop((0, 60, 1280, 60 + 598)).resize((920, 430), Image.LANCZOS)
    d = ImageDraw.Draw(crop)
    W, H = crop.size
    if key == "paris_aquarell":
        # Papiervignette, Titel in Lora, Kugeln bleiben die einzigen satten Punkte
        vig = Image.new("L", (W, H), 0)
        ImageDraw.Draw(vig).rectangle([30, 30, W - 30, H - 30], fill=255)
        vig = vig.filter(ImageFilter.GaussianBlur(40))
        crop = Image.composite(crop, Image.new("RGB", (W, H), rgb("#F7F2E8")), vig)
        wash_blob(crop, (10, 0, 560, 190), rgb("#F7F2E8"), rgb("#F7F2E8"), 9, 0.92)
        d = ImageDraw.Draw(crop)
        d.text((44, 32), "ZAPmaniac", font=F(LORA, 86), fill=rgb("#4A3B2E"))
        d.text((48, 126), "Explorer: Paris", font=F(LORA_I, 34), fill=rgb("#6B5A60"))
    elif key == "himmelsbrunn_kulisse":
        # zentriert, symmetrisch: Titel in einer Navy-Tafel oben mittig
        f1 = F(JOST % "700-Bold", 70); f2 = F(JOST % "500-Medium", 28)
        tw = d.textlength("ZAPmaniac", font=f1)
        d.rectangle([W / 2 - tw / 2 - 30, 24, W / 2 + tw / 2 + 30, 128], fill=rgb("#25365C"))
        d.rectangle([W / 2 - tw / 2 - 22, 32, W / 2 + tw / 2 + 22, 120], outline=rgb("#F3D9A4"), width=2)
        d.text((W / 2 - tw / 2, 28), "ZAPmaniac", font=f1, fill=rgb("#FBF6EC"))
        t2 = "EXPLORER · HIMMELSBRUNN"
        tw2 = d.textlength(t2, font=f2)
        d.rectangle([W / 2 - tw2 / 2 - 14, 136, W / 2 + tw2 / 2 + 14, 176], fill=rgb("#FBF6EC"))
        d.text((W / 2 - tw2 / 2, 137), t2, font=f2, fill=rgb("#8E2F3C"))
    elif key == "arles_sternennacht":
        text_outline(d, (44, 26), "ZAPmaniac", F(CHORUS, 96), rgb("#F6C945"), rgb("#1B2A6B"), 6)
        d.text((52, 132), "Explorer: Arles bei Nacht", font=F(CHORUS, 40), fill=rgb("#F6E9B8"))
    else:
        starburst(d, 250, 110, 230, 150, 14, rgb("#E4002B"), rgb("#111111"), 6)
        text_outline(d, (90, 60), "ZAPmaniac", F(POPPINS % "Bold", 76), rgb("#FFFDF5"), rgb("#111111"), 6)
        text_outline(d, (610, 350), "EXPLORER: MIAMI", F(POPPINS % "Bold", 30), rgb("#FFFDF5"), rgb("#111111"), 4)
    crop.save(os.path.join(B, key, "capsule_920x430.png"))
    crop.resize((460, 215), Image.LANCZOS).save(os.path.join(B, key, "capsule_460x215.png"))

ONLY = os.environ.get("ONLY", "")
for k, D in DIRS.items():
    if ONLY and k not in ONLY.split(","):
        continue
    tile(k, D)
    capsule(k, D)
print("ok")
