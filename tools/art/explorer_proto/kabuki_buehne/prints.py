# Richtung E "Buehnenstadt Shibai-machi": gemalte Kulissen-Texturen (Pillow, eigene Entwuerfe,
# keine Fremdbilder, keine Familienwappen, keine Kumadori bekannter Rollen).
# Aufruf: python3 prints.py -> prints/*.png
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

H = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(H, "prints")
os.makedirs(OUT, exist_ok=True)
SERIF = os.path.join(H, "fonts", "NotoSerifJP-Black-Subset.otf")
def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
P = dict(sumi="#1A1714", gofun="#F2ECE0", hinoki="#D9B884", wood="#6B4A2E", wood_d="#3B281A", kaki="#B4542A",
         moegi="#45603F", ai="#2B3A67", asagi="#5E8FA8", beni="#C1272D", sakura="#F2B8C6", roof="#3A3A42", shoji="#EFE6D2")

def vtext(d, x, y, txt, font, fill, step=None):
    step = step or font.size * 1.02
    for i, ch in enumerate(txt):
        w = d.textlength(ch, font=font)
        d.text((x - w / 2, y + i * step), ch, font=font, fill=fill)

def paper_grain(img, amt=10, seed=1):
    random.seed(seed)
    n = Image.effect_noise(img.size, 40).convert("L").filter(ImageFilter.GaussianBlur(0.6))
    g = Image.merge("RGB", (n, n, n))
    return Image.blend(img, Image.composite(img, g, Image.new("L", img.size, 255 - amt)), 0.5)

# 1) Laterne (Chochin): Papier, rote Baender, schwarzes 大入 senkrecht
def lantern():
    W, Hh = 256, 512
    im = Image.new("RGB", (W, Hh), rgb(P["gofun"]))
    d = ImageDraw.Draw(im)
    for y in range(0, Hh, 18):
        d.line([(0, y), (W, y)], fill=(222, 212, 192), width=2)  # Rippen
    d.rectangle([0, 0, W, 54], fill=rgb(P["beni"])); d.rectangle([0, Hh - 54, W, Hh], fill=rgb(P["beni"]))
    d.rectangle([0, 54, W, 60], fill=rgb(P["sumi"])); d.rectangle([0, Hh - 60, W, Hh - 54], fill=rgb(P["sumi"]))
    vtext(d, W / 2, 92, "大入", ImageFont.truetype(SERIF, 150), rgb(P["sumi"]), 160)
    im.save(os.path.join(OUT, "laterne.png"))

# 2) Nobori-Fahne mit eigener, abstrakter Buehnenmaske (rote Linien = Held, blaue = Gegenspieler)
def mask_banner(name, line_col, bg):
    W, Hh = 256, 900
    im = Image.new("RGB", (W, Hh), rgb(bg))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 18, Hh], fill=rgb(P["sumi"]))  # Stangenhuelse
    # Gesicht (eigene Form): weisses Oval
    cx, cy = W / 2 + 8, 300
    d.ellipse([cx - 90, cy - 125, cx + 90, cy + 125], fill=rgb(P["gofun"]), outline=rgb(P["sumi"]), width=6)
    lc = rgb(line_col)
    # eigene, abstrakte Linien: je Seite ein aufsteigender Bogen von der Braue, ein Haken am Kinn
    for s in (-1, 1):
        pts = [(cx + s * (18 + t * 0.9), cy - 20 - t * 1.1 + 0.004 * t * t) for t in range(0, 80, 4)]
        d.line(pts, fill=lc, width=14, joint="curve")
        d.line([(cx + s * 30, cy + 70), (cx + s * 62, cy + 52), (cx + s * 72, cy + 20)], fill=lc, width=10, joint="curve")
        # Augen als schwarze Mandeln
        d.ellipse([cx + s * 40 - 20, cy - 12, cx + s * 40 + 20, cy + 4], fill=rgb(P["sumi"]))
    d.line([(cx - 22, cy + 88), (cx + 22, cy + 88)], fill=rgb(P["sumi"]), width=8)
    vtext(d, W / 2 + 8, 470, "芝居町", ImageFont.truetype(SERIF, 112), rgb(P["sumi"]) if bg != P["sumi"] else rgb(P["gofun"]), 128)
    paper_grain(im, 14).save(os.path.join(OUT, name))

# 3) Machiya-Kulisse: gemaltes Buehnenhaus (Holzgitter unten, Putz oben, Tuschekonturen)
def machiya(name, seed, wall, noren):
    random.seed(seed)
    W, Hh = 1024, 768  # entspricht 8 m x 6 m
    im = Image.new("RGB", (W, Hh), rgb(wall))
    d = ImageDraw.Draw(im)
    S = P["sumi"]
    # Obergeschoss: Putz mit Mushiko-Fenstern (Schlitze)
    for k in range(3):
        x0 = 120 + k * 290
        d.rectangle([x0, 140, x0 + 200, 260], fill=rgb(P["wood_d"]), outline=rgb(S), width=6)
        for j in range(9):
            d.rectangle([x0 + 12 + j * 21, 150, x0 + 22 + j * 21, 250], fill=rgb(wall))
    # Zwischendach (Hisashi) als Band mit Ziegelwellen
    d.rectangle([0, 300, W, 360], fill=rgb(P["roof"]), outline=rgb(S), width=6)
    for x in range(0, W, 32):
        d.arc([x, 296, x + 32, 336], 0, 180, fill=(90, 90, 100), width=4)
    # Erdgeschoss: Koshi-Gitter (Holz) + Noren in der Mitte
    d.rectangle([0, 360, W, Hh], fill=rgb(P["wood"]), outline=rgb(S), width=6)
    for x in range(10, W, 22):
        d.rectangle([x, 380, x + 9, Hh - 10], fill=rgb(P["wood_d"]))
    d.rectangle([W / 2 - 170, 360, W / 2 + 170, Hh], fill=rgb(P["wood_d"]))
    for k in range(4):  # Noren in 4 Bahnen, eigenes Muster: weisser Querstreifen
        x0 = W / 2 - 166 + k * 84
        d.rectangle([x0, 362, x0 + 78, 560], fill=rgb(noren), outline=rgb(S), width=3)
        d.rectangle([x0, 520, x0 + 78, 536], fill=rgb(P["gofun"]))
    d.text((W / 2 - 40, 400), "幕", font=ImageFont.truetype(SERIF, 88), fill=rgb(P["gofun"]))
    # Pfosten (Tuschekonturen bewusst kraeftig, gemalte Buehnenarchitektur)
    for x in (0, W / 2 - 176, W / 2 + 170, W - 14):
        d.rectangle([x, 300, x + 14, Hh], fill=rgb(P["wood_d"]), outline=rgb(S), width=3)
    d.rectangle([0, 0, W - 1, Hh - 1], outline=rgb(S), width=10)
    # gemalte Schattenkante unten (Buehnenmalerei, kein Licht)
    for i in range(30):
        d.line([(0, Hh - i), (W, Hh - i)], fill=tuple(int(c * (0.7 + i / 100)) for c in rgb(P["wood_d"])), width=1)
    paper_grain(im, 18, seed).save(os.path.join(OUT, name))

# 4) Dachkulisse (Kawara) als Textur fuer das Dach-Profil
def roof():
    W, Hh = 512, 256
    im = Image.new("RGB", (W, Hh), rgb(P["roof"]))
    d = ImageDraw.Draw(im)
    for y in range(0, Hh, 26):
        for x in range(-16 if (y // 26) % 2 else 0, W, 32):
            d.arc([x, y - 12, x + 32, y + 22], 0, 180, fill=(92, 92, 104), width=5)
    im.save(os.path.join(OUT, "dach.png"))

# 5) Ausgangsschild 出口 (gruen exklusiv) – Lackrahmen, weisse Schrift
def exit_sign():
    W, Hh = 512, 256
    im = Image.new("RGB", (W, Hh), (30, 214, 96))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W - 1, Hh - 1], outline=rgb(P["sumi"]), width=14)
    f = ImageFont.truetype(SERIF, 150)
    d.text((40, 30), "出口", font=f, fill=(255, 255, 255))
    d.text((370, 80), "EXIT", font=ImageFont.truetype(SERIF, 52), fill=(255, 255, 255))
    d.polygon([(380, 170), (470, 170), (470, 150), (500, 190), (470, 230), (470, 210), (380, 210)], fill=(255, 255, 255))
    im.save(os.path.join(OUT, "ausgang.png"))

# 6) Hanamichi-Schild (Holz, schwarz)
def sign_hanamichi():
    W, Hh = 512, 160
    im = Image.new("RGB", (W, Hh), rgb(P["hinoki"]))
    d = ImageDraw.Draw(im)
    for y in range(0, Hh, 7):
        d.line([(0, y + random.randint(-1, 1)), (W, y)], fill=(200, 166, 112), width=1)
    d.rectangle([0, 0, W - 1, Hh - 1], outline=rgb(P["sumi"]), width=10)
    d.text((40, 6), "花道", font=ImageFont.truetype(SERIF, 120), fill=rgb(P["sumi"]))
    d.text((300, 50), "HANAMICHI", font=ImageFont.truetype(SERIF, 34), fill=rgb(P["sumi"]))
    im.save(os.path.join(OUT, "schild_hanamichi.png"))

# 7) gemalter Prospekt am Achsenende: Kiefer auf Goldgrund ist zu nah an Noh -> eigene Nachtlandschaft:
#    Asagi-Blau-Verlauf, Huegelkulissen, Kirschzweige
def backdrop():
    W, Hh = 2048, 768
    im = Image.new("RGB", (W, Hh), rgb(P["ai"]))
    d = ImageDraw.Draw(im)
    for y in range(Hh):
        t = y / Hh
        c = tuple(int(a * (1 - t) + b * t) for a, b in zip(rgb("#141B33"), rgb(P["asagi"])))
        d.line([(0, y), (W, y)], fill=c)
    random.seed(4)
    for layer, col, base in [(0, "#22304F", 520), (1, "#1A2440", 600)]:
        pts = [(0, Hh)]
        for x in range(0, W + 64, 64):
            pts.append((x, base - 90 * math.sin(x / 260 + layer * 2) - random.randint(0, 30)))
        pts.append((W, Hh))
        d.polygon(pts, fill=rgb(col), outline=rgb(P["sumi"]))
    im = paper_grain(im, 16, 7)
    im.save(os.path.join(OUT, "prospekt.png"))

def tsurieda():
    # haengende Kirschzweige (Buehnenborte): Zweige als Tusche-Striche, Blueten als 5-Blatt-Scheiben
    W, Hh = 1024, 512
    im = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    random.seed(11)
    d.rectangle([0, 0, W, 70], fill=rgb(P["sumi"]) + (255,))  # Borte (Ichimonji)
    d.rectangle([0, 62, W, 70], fill=rgb(P["beni"]) + (255,))
    for k in range(9):
        x = 40 + k * 118 + random.randint(-20, 20)
        y, ang = 70, math.pi / 2 + random.uniform(-0.25, 0.25)
        L = random.randint(260, 420)
        pts = [(x, y)]
        for i in range(10):
            ang += random.uniform(-0.3, 0.3)
            x += math.cos(ang) * L / 10; y += math.sin(ang) * L / 10
            pts.append((x, y))
        d.line(pts, fill=(40, 28, 24, 255), width=7, joint="curve")
        for (bx, by) in pts[1:]:
            for j in range(3):
                cx, cy = bx + random.randint(-26, 26), by + random.randint(-14, 18)
                r = random.randint(9, 14)
                col = rgb(P["sakura"]) if random.random() < 0.75 else (250, 236, 240)
                for p in range(5):
                    a = p / 5 * 2 * math.pi
                    d.ellipse([cx + math.cos(a) * r * 0.7 - r * 0.55, cy + math.sin(a) * r * 0.7 - r * 0.55,
                               cx + math.cos(a) * r * 0.7 + r * 0.55, cy + math.sin(a) * r * 0.7 + r * 0.55], fill=col + (255,))
                d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=rgb(P["beni"]) + (255,))
    im.save(os.path.join(OUT, "tsurieda.png"))

def mask_banner(name, line_col, bg):
    # eigene, abstrakte Buehnenmaske: Flammenkeile von den Brauen zu den Schlaefen, Haken am Mund.
    W, Hh = 256, 900
    im = Image.new("RGB", (W, Hh), rgb(bg))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 18, Hh], fill=rgb(P["sumi"]))
    cx, cy = W / 2 + 8, 300
    d.ellipse([cx - 92, cy - 128, cx + 92, cy + 128], fill=rgb(P["gofun"]), outline=rgb(P["sumi"]), width=7)
    lc = rgb(line_col)
    for s in (-1, 1):
        d.polygon([(cx + s * 12, cy - 10), (cx + s * 40, cy - 30), (cx + s * 70, cy - 80), (cx + s * 84, cy - 112),
                   (cx + s * 62, cy - 70), (cx + s * 34, cy - 40), (cx + s * 14, cy - 26)], fill=lc)
        d.polygon([(cx + s * 50, cy + 10), (cx + s * 78, cy - 6), (cx + s * 88, cy + 30), (cx + s * 70, cy + 18)], fill=lc)
        d.polygon([(cx + s * 22, cy + 82), (cx + s * 56, cy + 70), (cx + s * 72, cy + 40), (cx + s * 62, cy + 76), (cx + s * 26, cy + 92)], fill=lc)
        d.ellipse([cx + s * 38 - 18, cy - 8, cx + s * 38 + 18, cy + 6], fill=rgb(P["sumi"]))
    d.line([(cx - 24, cy + 90), (cx + 24, cy + 90)], fill=rgb(P["sumi"]), width=9)
    vtext(d, W / 2 + 8, 470, "芝居町", ImageFont.truetype(SERIF, 112), rgb(P["sumi"]), 128)
    paper_grain(im, 14).save(os.path.join(OUT, name))

tsurieda(); lantern(); mask_banner("fahne_held.png", P["beni"], P["gofun"]); mask_banner("fahne_gegen.png", P["ai"], P["gofun"])
machiya("haus_a.png", 1, P["gofun"], P["ai"]); machiya("haus_b.png", 2, "#E6D8BE", P["kaki"]); machiya("haus_c.png", 3, "#DCCDB0", P["sumi"])
roof(); exit_sign(); sign_hanamichi(); backdrop()
print("ok")
