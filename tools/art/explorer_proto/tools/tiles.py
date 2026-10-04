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

# ---------- Nachtrag 04.10.2026: Richtungen E–G (Kabuki × Pappausschnitt) ----------
PROTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SERIFJP = os.path.join(PROTO, "kabuki_buehne", "fonts", "NotoSerifJP-Black-Subset.otf")
SANSJP = os.path.join(PROTO, "pappkarton", "fonts", "NotoSansJP-Black-Subset.otf")
def PR(k, f): return Image.open(os.path.join(PROTO, k, "prints", f)).convert("RGBA")

DIRS2 = {
 "kabuki_buehne": dict(
   title="E  BÜHNENSTADT SHIBAI-MACHI", city="SHIBAI-MACHI · HANAMICHI",
   idea="Die Stadt ist eine Kabuki-Bühne: Hinoki-Boden, Hanamichi als Hauptstraße, gemalte Schiebekulissen, Streifenvorhang, Kirschzweig-Borten, Kuromaku-Nacht.",
   bg="#0E0B0A", fg="#F2ECE0",
   pal=[("#0E0B0A","Kuromaku (Himmel = Nacht)"),("#D9B884","Hinoki-Bühnenboden"),("#F2ECE0","Gofun-Weiß (Putz, Papier)"),("#6B4A2E","Holzgitter"),
        ("#B4542A","Kaki (Vorhang)"),("#3A5034","Moegi gedeckt (Vorhang)"),("#C1272D","Beni (Held, Laternenband)"),("#2B3A67","Ai (Gegenspieler)"),
        ("#FFC629","Kugeln Blattgold (exklusiv)"),("#29E36B","Ausgang/Versenkung (exklusiv)")],
   fonts=[("Noto Serif CJK JP Black (SIL OFL 1.1, Subset) — Schilder (Ausgang, Hanamichi, Laternen), Titel", ""), ("Inter (SIL OFL 1.1) — HUD", "")],
   font=SERIFJP),
 "pappkarton": dict(
   title="F  PAPPSTADT DANBORU-CHO", city="DANBORU-CHO · KARTONGASSE",
   idea="Die Stadt aus Versandkartons: Wellpappe mit Wellen-Schnittkanten, Klebeband, Druckreste („Diese Seite oben“), Marker-Masken, Aufsteller, Drehbühne als Pappscheibe.",
   bg="#98714A", fg="#201A16",
   pal=[("#98714A","Kraft (Karton)"),("#A88158","Kraft hell"),("#7C5A39","Kraft dunkel / Rahmen"),("#6E6558","Graupappe (Fahrbahn)"),
        ("#201A16","Druckfarbe / Marker"),("#B02824","Druckrot / Marker"),("#5E93C6","Plakatfarbe Himmel"),("#B4542A","Plakatfarbe Kaki"),
        ("#FFD21A","Kugeln Papiergelb (exklusiv)"),("#22C25E","Ausgang grüner Karton (exklusiv)")],
   fonts=[("Noto Sans CJK JP Black (SIL OFL 1.1, Subset) — Druckreste, Schablonen-Ausgangsschild", ""), ("Noto Serif CJK JP Black (OFL) — Marker-Schilder · Inter — HUD", "")],
   font=SANSJP),
 "aizuri_popup": dict(
   title="G  AIZURI-POP-UP · BILDERBUCHSTADT", city="BILDERBUCH · SEITE 12",
   idea="Ein aufgeschlagenes Theater-Bilderbuch: Straße im Falz, Häuser als Pop-up-Holzschnitte in Preußischblau, die beim Näherkommen aufklappen.",
   bg="#F3EEE2", fg="#1E3A6E",
   pal=[("#F3EEE2","Washi-Papier"),("#CFE0EE","Ai 4 (Weg, Nebel)"),("#8DB0D6","Ai 3"),("#3F6CA8","Ai 2"),("#1E3A6E","Ai 1 / Bokashi-Himmel"),
        ("#1C1A1E","Sumi-Konturplatte"),("#C8384B","Beni (sparsamer Akzent)"),("#24304F","Einband"),
        ("#FFC714","Kugeln Blattgold (exklusiv)"),("#22C460","Lesebändchen/Ausgang (exklusiv)")],
   fonts=[("Noto Serif CJK JP Black/Bold (SIL OFL 1.1, Subset) — Kartusche, Ausgangsschild, Titel", ""), ("Inter (SIL OFL 1.1) — HUD", "")],
   font=SERIFJP),
}

def tile2(key, D):
    W, Hh = 1600, 1000
    img = Image.new("RGB", (W, Hh), rgb(D["bg"]))
    if key == "pappkarton":
        g = noise_img((W, Hh), 2, 3).point(lambda v: 225 + v // 9)
        img = ImageChops.multiply(img, Image.merge("RGB", (g, g, g)))
    d = ImageDraw.Draw(img)
    fg = rgb(D["fg"]); bg = rgb(D["bg"])
    dim = tuple(int(c * 0.75 + bg[i] * 0.25) for i, c in enumerate(fg))
    d.text((60, 36), D["title"], font=F(D["font"], 52), fill=fg)
    d.text((60, 112), D["idea"], font=F(INTER % "Regular", 20), fill=dim)
    x, y = 60, 170
    for i, (h, role) in enumerate(D["pal"]):
        cx = x + (i % 5) * 160; cy = y + (i // 5) * 150
        d.rectangle([cx, cy, cx + 136, cy + 84], fill=rgb(h), outline=dim, width=2)
        d.text((cx, cy + 90), h.upper(), font=F(MONOB, 16), fill=fg)
        d.text((cx, cy + 110), role, font=F(INTER % "Regular", 12), fill=dim)
    sx, sy = 60, 490
    d.text((sx, sy), "Beispielformen", font=F(INTER % "SemiBold", 18), fill=dim)
    if key == "kabuki_buehne":
        # Vorhangstreifen mit Falten
        for i in range(220):
            k = (i // 24) % 3
            col = [rgb("#1A1714"), rgb("#B4542A"), rgb("#3A5034")][k]
            f = 0.8 + 0.2 * (0.5 + 0.5 * math.sin(i / 3.8))
            d.line([(sx + i, sy + 30), (sx + i, sy + 170)], fill=tuple(int(c * f) for c in col))
        # Hinoki-Dielen
        for j in range(7):
            col = tuple(int(c * (0.88 + 0.16 * ((j * 37) % 7) / 7)) for c in rgb("#D9B884"))
            d.rectangle([sx + 240 + j * 31, sy + 30, sx + 268 + j * 31, sy + 170], fill=col)
        img.paste(PR(key, "laterne.png").resize((70, 140)), (sx + 480, sy + 30), PR(key, "laterne.png").resize((70, 140)))
        fb = PR(key, "fahne_held.png").resize((60, 210)).crop((0, 0, 60, 140))
        img.paste(fb, (sx + 570, sy + 30))
        ts = PR(key, "tsurieda.png").resize((180, 90))
        img.paste(ts, (sx + 650, sy + 30), ts)
    elif key == "pappkarton":
        # Querschnitt Wellpappe: zwei Liner, Welle dazwischen
        bx0, by0, bx1, by1 = sx, sy + 40, sx + 300, sy + 150
        d.rectangle([bx0, by0, bx1, by1], fill=(60, 40, 24))
        d.rectangle([bx0, by0, bx1, by0 + 12], fill=rgb("#B28A5E")); d.rectangle([bx0, by1 - 12, bx1, by1], fill=rgb("#B28A5E"))
        pts = [(bx0 + t, (by0 + by1) / 2 + 40 * math.sin(t / 300 * 2 * math.pi * 6)) for t in range(0, 301, 2)]
        d.line(pts, fill=rgb("#C49A6A"), width=7)
        # Klebeband
        tp = Image.new("RGBA", (260, 50), (184, 135, 62, 185)); img.paste(tp, (sx + 330, sy + 70), tp)
        d.text((sx + 330, sy + 126), "Klebeband (transparent)", font=F(INTER % "Regular", 13), fill=dim)
        t = PR(key, "tenchi.png").resize((200, 100)); img.paste(t, (sx + 620, sy + 40), t)
        f2 = PR(key, "gesicht_held.png").resize((96, 120)); img.paste(f2, (sx + 840, sy + 34), f2)
    else:
        # Bokashi-Verlauf, Passerversatz-Demo, Wellendruck, Pop-up-Falzschema
        for yy in range(140):
            t = yy / 140
            c = tuple(int(a * (1 - t) + b * t) for a, b in zip(rgb("#1E3A6E"), rgb("#F3EEE2")))
            d.line([(sx, sy + 30 + yy), (sx + 200, sy + 30 + yy)], fill=c)
        d.rectangle([sx + 236, sy + 44, sx + 356, sy + 164], fill=rgb("#3F6CA8"))
        d.rectangle([sx + 230, sy + 40, sx + 350, sy + 160], outline=rgb("#1C1A1E"), width=5)
        d.text((sx + 230, sy + 168), "Konturplatte + Versatz", font=F(INTER % "Regular", 12), fill=dim)
        w = PR(key, "wellen.png").resize((260, 92)); img.paste(w, (sx + 390, sy + 50), w)
        # Falzschema: liegend -> stehend
        ox, oy = sx + 700, sy + 160
        for a, col in [(5, "#CFE0EE"), (40, "#8DB0D6"), (90, "#1E3A6E")]:
            r = math.radians(a)
            d.line([(ox, oy), (ox + 120 * math.cos(r), oy - 120 * math.sin(r))], fill=rgb(col), width=8)
        d.line([(ox - 40, oy), (ox + 170, oy)], fill=fg, width=3)
        d.text((ox - 40, oy + 6), "klappt beim Näherkommen auf", font=F(INTER % "Regular", 12), fill=dim)
    rx, ry = 60, 700
    d.text((rx, ry), "Kugel · Ausgang · HUD-Chip", font=F(INTER % "SemiBold", 18), fill=dim)
    kug = rgb(D["pal"][-2][0]); met = rgb(D["pal"][-1][0])
    for k in range(4):
        cx = rx + 40 + k * 60; cy = ry + 70
        d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=kug, outline=rgb("#1C1A1E") if key == "aizuri_popup" else None, width=3)
        d.ellipse([cx - 8, cy - 10, cx + 6, cy + 4], fill=tuple(min(255, int(c * 0.5 + 128)) for c in kug))
    d.rectangle([rx + 300, ry + 35, rx + 440, ry + 110], fill=met, outline=rgb("#1A1714"), width=4)
    d.text((rx + 322, ry + 40), "出口", font=F(D["font"], 48), fill=(255, 255, 255))
    chip = {"kabuki_buehne": rgb("#1A1714"), "pappkarton": rgb("#201A16"), "aizuri_popup": rgb("#1E3A6E")}[key]
    d.rounded_rectangle([rx + 500, ry + 40, rx + 840, ry + 104], 14, fill=chip, outline=dim if key == "kabuki_buehne" else None, width=2)
    d.text((rx + 520, ry + 56), "EXPLORER", font=F(INTER % "Bold", 20), fill=rgb("#F3EEE2"))
    d.text((rx + 650, ry + 56), D["city"].split(" · ")[0][:14], font=F(INTER % "Regular", 20), fill=kug)
    ty = 840
    d.text((60, ty), "Schrift", font=F(INTER % "SemiBold", 18), fill=dim)
    sample = {"kabuki_buehne": "花道 · 大入 · Shibai-machi", "pappkarton": "天地無用 · 段ボール町", "aizuri_popup": "芝居絵本 · Bilderbuch"}[key]
    d.text((60, ty + 22), sample, font=F(D["font"], 46), fill=fg)
    yy = ty + 90
    for fname, use in D["fonts"]:
        d.text((60, yy), fname, font=F(INTER % "Regular", 15), fill=fg); yy += 20
    sh = Image.open(os.path.join(B, key, "strasse.png")).convert("RGB").resize((640, 360))
    img.paste(sh, (W - 640 - 60, Hh - 360 - 110))
    d.text((W - 640 - 60, Hh - 100), "Godot-4.3-Prototyp, Compatibility-Renderer (Software), 1280x720", font=F(INTER % "Regular", 14), fill=dim)
    img.save(os.path.join(B, key, "styletile.png"))

def capsule2(key, D):
    src = Image.open(os.path.join(B, key, "capsule.png")).convert("RGB")
    crop = src.crop((0, 60, 1280, 60 + 598)).resize((920, 430), Image.LANCZOS)
    d = ImageDraw.Draw(crop)
    W, Hh = crop.size
    if key == "kabuki_buehne":
        # Titel auf schwarzer Vorhangbahn, darunter Kaki-Linie; Ortsname senkrecht rechts
        band = Image.new("RGBA", (560, 122), (14, 11, 10, 228)); crop.paste(band, (0, 0), band)
        d = ImageDraw.Draw(crop)
        d.rectangle([0, 122, 560, 128], fill=rgb("#B4542A"))
        d.text((30, 0), "ZAPmaniac", font=F(SERIFJP, 76), fill=rgb("#F2ECE0"))
        d.text((34, 88), "EXPLORER · BÜHNENSTADT", font=F(INTER % "SemiBold", 22), fill=rgb("#FFC629"))
        f = F(SERIFJP, 60)
        for i, ch in enumerate("花道"):
            d.text((W - 92, 10 + i * 66), ch, font=f, fill=rgb("#F2ECE0"))
    elif key == "pappkarton":
        # Titel als Schablonendruck auf einem Klebebandstreifen ueber dem Bild
        tp = Image.new("RGBA", (640, 130), (196, 150, 80, 215))
        crop.paste(tp, (30, 26), tp)
        d = ImageDraw.Draw(crop)
        d.text((52, 22), "ZAPmaniac", font=F(SANSJP, 92), fill=rgb("#201A16"))
        d.rectangle([30, 166, 420, 206], fill=rgb("#201A16"))
        d.text((42, 166), "EXPLORER · 段ボール町", font=F(SANSJP, 28), fill=rgb("#F2EBDD"))
    else:
        # Titel in einer Bilderbuch-Kartusche (Papier, Beni-Rahmen), oben mittig
        f1 = F(SERIFJP, 76)
        tw = d.textlength("ZAPmaniac", font=f1)
        d.rectangle([W / 2 - tw / 2 - 28, 18, W / 2 + tw / 2 + 28, 132], fill=rgb("#F3EEE2"), outline=rgb("#1C1A1E"), width=5)
        d.rectangle([W / 2 - tw / 2 - 18, 28, W / 2 + tw / 2 + 18, 122], outline=rgb("#C8384B"), width=3)
        d.text((W / 2 - tw / 2, 18), "ZAPmaniac", font=f1, fill=rgb("#1E3A6E"))
        t2 = "EXPLORER · 芝居絵本"
        f2 = F(SERIFJP, 28); tw2 = d.textlength(t2, font=f2)
        d.rectangle([W / 2 - tw2 / 2 - 12, 140, W / 2 + tw2 / 2 + 12, 180], fill=rgb("#1E3A6E"))
        d.text((W / 2 - tw2 / 2, 140), t2, font=f2, fill=rgb("#F3EEE2"))
    crop.save(os.path.join(B, key, "capsule_920x430.png"))
    crop.resize((460, 215), Image.LANCZOS).save(os.path.join(B, key, "capsule_460x215.png"))

for k, D in DIRS2.items():
    if ONLY and k not in ONLY.split(","):
        continue
    if not os.path.exists(os.path.join(B, k, "strasse.png")):
        continue
    tile2(k, D)
    capsule2(k, D)
print("ok")

# ---------- Nachtrag 04.10.2026: Richtungen I–K (Papp-Fotorealismus) ----------
# Style-Tiles zeigen die echten PBR-Texturen (tools/pappe_pbr.py) statt gemalter Muster.
FCOND = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
DIRS3 = {
 "pappe_buehne": dict(
   title="I  KARTONBÜHNE · STADT IN EINEM AKT", city="KARTONBÜHNE",
   idea="Eine Kleinstadt-Gasse als Bühnenbild aus echten Umzugskartons auf schwarzer Bühne: harte warme Scheinwerfer, Dunst, Packpapier glüht in den Fenstern.",
   bg="#0B0806", fg="#E9D9C2", shot="strasse.png", label="Bühnenschwarz · Kraft · Packpapier-Glühen",
   pal=[("#050403","Bühnenschwarz (Himmel, Nebel)"),("#C9A47A","Kraft im Licht"),("#A98157","Kraft (Albedo)"),("#6E4E33","Kraft im Schatten"),
        ("#C29A6A","Packpapier"),("#B88A52","Klebeband (glänzend)"),("#FFB85C","Glühen hinter Papier"),("#1A1612","Druck / Edding"),
        ("#2E6BFF","Kugeln: Glasmurmel Kobalt (exklusiv)"),("#1FA855","Ausgang: grüner Karton + Licht (exklusiv)")]),
 "pappe_miniatur": dict(
   title="J  PAPPMODELL AMSTERDAM · 1:100", city="AMSTERDAM 1:100",
   idea="Ein Architekturmodell aus Wellpappe auf Ameisenhöhe: Häuser in echter Größe, Material 100-fach – meterhohe Wellen in jeder Schnittkante. Tageslicht aus dem Atelierfenster.",
   bg="#E9E3D8", fg="#2B2118", shot="strasse.png", label="Atelierlicht · Wellen-Schnittkante · Lackwasser",
   pal=[("#E9E3D8","Atelierhimmel / Dunst"),("#C9A47A","Kraft im Licht"),("#A98157","Kraft (Albedo)"),("#5B412B","Wellenhohlraum / Schatten"),
        ("#1A120B","Lackwasser (Gracht)"),("#6E5139","Arbeitstisch"),("#D9A21E","Riesen-Bleistift (Wahrzeichen)"),("#E8E2D6","Kaffeebecher (Wahrzeichen)"),
        ("#2E6BFF","Kugeln: Glaskopf-Stecknadeln (exklusiv)"),("#1FA855","Ausgang: grüne Papp-Tram (exklusiv)")]),
 "pappe_wohnung": dict(
   title="K  UMZUGSWOHNUNG · ABENDS", city="UMZUGSWOHNUNG",
   idea="Eine Altbauwohnung am Umzugsabend, alles aus Pappe: Kartonstapel sind die Gänge, Edding-Etiketten die Wegweiser, Möbel die Wahrzeichen, Abendsonne glüht durchs Packpapier.",
   bg="#1A120C", fg="#EAD8BF", shot="strasse.png", label="Abendsonne · Edding · Pappmöbel",
   pal=[("#1A120C","Raumschatten"),("#C9A47A","Kraft im Licht"),("#A98157","Kraft (Albedo)"),("#B8946A","Wandplatten"),
        ("#C29A6A","Packpapier-Vorhang"),("#FF9A3C","Abendsonne durch Papier"),("#1A1612","Edding-Etikett"),("#B88A52","Klebeband"),
        ("#2E6BFF","Kugeln: Glasmurmeln (exklusiv)"),("#1FA855","Ausgang: grüne Wohnungstür (exklusiv)")]),
}

def stencil_text(img, xy, text, size, fill, bridge_col, seed=1):
    """Schablonenschrift: Buchstaben mit ausgesparten Stegen (eigene Umsetzung, Systemfont)."""
    f = F(FCOND, size)
    d = ImageDraw.Draw(img)
    x, y = xy
    random.seed(seed)
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        w = f.getlength(ch)
        if ch.strip() and ch not in "Iil1.:·-":
            bx = x + w * 0.5 + random.uniform(-1, 1)
            d.rectangle([bx - size * 0.035, y + size * 0.1, bx + size * 0.035, y + size * 1.1], fill=bridge_col)
        x += w + size * 0.02
    return x

def marker_text_img(img, xy, text, size, fill, seed=1, rot=0.0):
    layer = Image.new("L", img.size, 0)
    ld = ImageDraw.Draw(layer)
    f = F(FCOND, size)
    x, y = xy
    random.seed(seed)
    for ch in text:
        g = Image.new("L", (size * 2, size * 2), 0)
        ImageDraw.Draw(g).text((size // 2, size // 3), ch, font=f, fill=255)
        g = g.rotate(random.uniform(-8, 8) + rot, resample=Image.BICUBIC)
        layer.paste(255, (int(x) - size // 2, int(y + random.uniform(-3, 3)) - size // 3), g)
        x += f.getlength(ch) * random.uniform(0.93, 1.04)
    layer = layer.filter(ImageFilter.GaussianBlur(1.4)).point(lambda v: 255 if v > 100 else int(v * 1.8))
    img.paste(Image.new("RGB", img.size, fill), (0, 0), layer)

def tex_swatch(img, path, box, scale=1.0, tint=None):
    t = Image.open(path).convert("RGB")
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    crop = t.crop((0, 0, int(w / scale), int(h / scale))).resize((w, h), Image.LANCZOS)
    if tint:
        crop = ImageChops.multiply(crop, Image.new("RGB", (w, h), tint))
    img.paste(crop, (x0, y0))

def flute_section(d, box, fg, bg, n=7):
    x0, y0, x1, y1 = box
    lin = (y1 - y0) * 0.12
    d.rectangle([x0, y0, x1, y1], fill=(40, 26, 15))
    d.rectangle([x0, y0, x1, y0 + lin], fill=fg); d.rectangle([x0, y1 - lin, x1, y1], fill=fg)
    pts = []
    for i in range(0, x1 - x0 + 1, 2):
        pts.append((x0 + i, (y0 + y1) / 2 + ((y1 - y0) / 2 - lin - 4) * math.sin(i / (x1 - x0) * n * 2 * math.pi)))
    d.line(pts, fill=fg, width=max(3, int((y1 - y0) * 0.06)))

def tile3(key, D):
    W, Hh = 1600, 1000
    img = Image.new("RGB", (W, Hh), rgb(D["bg"]))
    d = ImageDraw.Draw(img)
    fg = rgb(D["fg"]); bg = rgb(D["bg"])
    dim = tuple(int(c * 0.72 + bg[i] * 0.28) for i, c in enumerate(fg))
    d.text((60, 36), D["title"], font=F(INTER % "Bold", 46), fill=fg)
    import textwrap
    for li, line in enumerate(textwrap.wrap(D["idea"], 150)):
        d.text((60, 100 + li * 24), line, font=F(INTER % "Regular", 18), fill=dim)
    x, y = 60, 160
    for i, (h, role) in enumerate(D["pal"]):
        cx = x + (i % 5) * 160; cy = y + (i // 5) * 140
        d.rectangle([cx, cy, cx + 136, cy + 74], fill=rgb(h), outline=dim, width=2)
        d.text((cx, cy + 80), h.upper(), font=F(MONOB, 15), fill=fg)
        for li, line in enumerate(textwrap.wrap(role, 24)[:2]):
            d.text((cx, cy + 99 + li * 14), line, font=F(INTER % "Regular", 11), fill=dim)
    pr = os.path.join(PROTO, key, "prints")
    sx, sy = 60, 460
    d.text((sx, sy), "Material (prozedurales PBR, keine Scans): Liner · Packpapier · Wellen-Querschnitt · Klebeband · Edding", font=F(INTER % "SemiBold", 16), fill=dim)
    tex_swatch(img, os.path.join(pr, "liner_albedo.png"), (sx, sy + 30, sx + 170, sy + 200), 0.5)
    tex_swatch(img, os.path.join(pr, "crumple_albedo.png"), (sx + 185, sy + 30, sx + 355, sy + 200), 0.5)
    nm = Image.open(os.path.join(pr, "crumple_normal.png")).convert("L").crop((0, 0, 340, 340)).resize((170, 170))
    lit = Image.merge("RGB", [nm.point(lambda v: int(v * 0.95))] * 3)
    img.paste(ImageChops.multiply(lit, Image.new("RGB", (170, 170), rgb("#E8B070"))), (sx + 370, sy + 30))
    flute_section(d, (sx + 555, sy + 70, sx + 780, sy + 160), rgb("#C9A47A"), bg)
    tex_swatch(img, os.path.join(pr, "liner_albedo.png"), (sx + 800, sy + 70, sx + 990, sy + 160), 0.6)
    tp = Image.new("RGBA", (190, 46), (150, 100, 45, 150)); img.paste(tp, (sx + 800, sy + 92), tp)
    d.line([(sx + 800, sy + 96), (sx + 990, sy + 96)], fill=(240, 220, 190), width=2)
    for (lx, lab) in [(sx, "Kraftliner"), (sx + 185, "Packpapier"), (sx + 370, "Knitter (Normal)"), (sx + 555, "Welle im Schnitt"), (sx + 800, "Klebeband")]:
        d.text((lx, sy + 206), lab, font=F(INTER % "Regular", 12), fill=dim)
    # Kugel, Ausgang, HUD
    rx, ry = 60, 720
    d.text((rx, ry), "Kugel · Ausgang · HUD-Chip", font=F(INTER % "SemiBold", 18), fill=dim)
    for k in range(4):
        cx = rx + 40 + k * 62; cy = ry + 70
        for r in range(26, 0, -1):
            t = r / 26
            col = tuple(int(a * t + b * (1 - t)) for a, b in zip(rgb("#173A9E"), rgb("#CFE0FF")))
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
        d.ellipse([cx - 12, cy - 16, cx - 4, cy - 8], fill=(255, 255, 255))
    gx = rx + 300
    d.rectangle([gx, ry + 34, gx + 170, ry + 112], fill=rgb("#1FA855"), outline=rgb("#0E5A2C"), width=4)
    d.text((gx + 14, ry + 54), "AUSGANG", font=F(FCOND, 26), fill=(240, 255, 240))
    d.rounded_rectangle([rx + 500, ry + 40, rx + 860, ry + 104], 14, fill=rgb("#1A1612"))
    d.text((rx + 520, ry + 56), "EXPLORER", font=F(INTER % "Bold", 20), fill=rgb("#EAD8BF"))
    d.text((rx + 650, ry + 56), D["city"][:15], font=F(INTER % "Regular", 20), fill=rgb("#7FA6FF"))
    ty = 860
    d.text((60, ty), "Schrift", font=F(INTER % "SemiBold", 18), fill=dim)
    stencil_text(img, (60, ty + 26), "ZAPMANIAC", 44, fg, bg)
    marker_text_img(img, (380, ty + 34), "KÜCHE · BÜCHER", 36, fg, 7)
    d.text((60, ty + 86), "Empfehlung fürs Spiel: Allerta Stencil (SIL OFL) für Druck/Schablone · Permanent Marker (Apache 2.0) für Edding · Inter (OFL) für HUD", font=F(INTER % "Regular", 13), fill=dim)
    d.text((60, ty + 106), "Im Muster: DejaVu Sans Condensed als Platzhalter (Stege bzw. Strich-Zittern per Skript)", font=F(INTER % "Regular", 13), fill=dim)
    sh = Image.open(os.path.join(B, key, D["shot"])).convert("RGB").resize((640, 360))
    img.paste(sh, (W - 640 - 60, 160))
    d.text((W - 640 - 60, 528), "Godot-4.3-Prototyp, Compatibility (Software-GL), 1280x720 – " + D["label"], font=F(INTER % "Regular", 13), fill=dim)
    img.save(os.path.join(B, key, "styletile.png"))

def capsule3(key, D):
    src = Image.open(os.path.join(B, key, "capsule.png")).convert("RGB")
    crop = src.crop((0, 60, 1280, 60 + 598)).resize((920, 430), Image.LANCZOS)
    W, Hh = crop.size
    pr = os.path.join(PROTO, key, "prints")
    liner = Image.open(os.path.join(pr, "liner_albedo.png")).convert("RGB")
    if key == "pappe_buehne":
        # Titel als Schablonendruck auf einem Kartonstreifen, oben links, Lichtkante
        lab = liner.crop((0, 0, 600, 150)).resize((560, 132))
        lab = ImageChops.multiply(lab, Image.new("RGB", lab.size, (255, 236, 205)))
        crop.paste(lab, (28, 24))
        stencil_text(crop, (48, 24), "ZAPmaniac", 92, rgb("#15110E"), (205, 170, 128))
        dd = ImageDraw.Draw(crop)
        dd.rectangle([28, 156, 420, 196], fill=rgb("#15110E"))
        dd.text((40, 158), "EXPLORER · KARTONBÜHNE", font=F(INTER % "Bold", 25), fill=rgb("#E9D9C2"))
    elif key == "pappe_miniatur":
        # Modellbau-Etikett: weisses Schild mit Bleistift-Massstab, mittig oben
        dd = ImageDraw.Draw(crop)
        L0, R0 = 24, 444
        dd.rectangle([L0, 22, R0, 168], fill=(244, 240, 230), outline=(90, 80, 70), width=2)
        f1 = F(INTER % "Bold", 74)
        tw = dd.textlength("ZAPmaniac", font=f1)
        dd.text(((L0 + R0) / 2 - tw / 2, 26), "ZAPmaniac", font=f1, fill=rgb("#2B2118"))
        t2 = "EXPLORER · AMSTERDAM  M 1:100"
        f2 = F(INTER % "Medium", 22); tw2 = dd.textlength(t2, font=f2)
        dd.text(((L0 + R0) / 2 - tw2 / 2, 122), t2, font=f2, fill=rgb("#5B4A3A"))
        dd.line([(L0 + 30, 116), (R0 - 30, 116)], fill=(150, 140, 128), width=2)
    else:
        # Edding auf Klebeband quer ueber dem Bild
        tp = Image.new("RGBA", (600, 120), (200, 152, 92, 205))
        crop.paste(tp, (24, 30), tp)
        marker_text_img(crop, (46, 46), "ZAPmaniac", 84, rgb("#15110E"), 3)
        dd = ImageDraw.Draw(crop)
        dd.text((50, 156), "EXPLORER · UMZUGSWOHNUNG", font=F(INTER % "Bold", 25), fill=rgb("#EAD8BF"))
    crop.save(os.path.join(B, key, "capsule_920x430.png"))
    crop.resize((460, 215), Image.LANCZOS).save(os.path.join(B, key, "capsule_460x215.png"))

for k, D in DIRS3.items():
    if ONLY and k not in ONLY.split(","):
        continue
    if not os.path.exists(os.path.join(B, k, "strasse.png")):
        continue
    tile3(k, D)
    capsule3(k, D)
print("ok3")
