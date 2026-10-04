# Richtung G "Aizuri-Pop-up – Bilderbuch-Theaterstadt": Holzschnitt-Drucke in Blau (Aizuri-e-
# Prinzip: Preussischblau in Stufen + Papierweiss + Tusche, Bokashi-Verlaeufe, Konturplatte,
# leichter Passerversatz) als freigestellte Pop-up-Teile. Eigene Entwuerfe; keine Kopie eines
# bestimmten Holzschnitts (keine "Grosse Welle", kein Fuji-Motiv, keine Darsteller-Portraets).
# Aufruf: python3 prints.py -> prints/*.png (RGBA)
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

H = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(H, "prints"); os.makedirs(OUT, exist_ok=True)
SERIF = os.path.join(H, "fonts", "NotoSerifJP-Black-Subset.otf")
SERIF_B = os.path.join(H, "fonts", "NotoSerifJP-Bold-Subset.otf")
def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
AI1, AI2, AI3, AI4 = rgb("#1E3A6E"), rgb("#3F6CA8"), rgb("#8DB0D6"), rgb("#CFE0EE")
PAPER, SUMI, BENI = rgb("#F3EEE2"), rgb("#1C1A1E"), rgb("#C8384B")
REG = (4, 3)  # Passerversatz Farbplatten gegen Konturplatte

class Print:
    """Zwei Ebenen: Farbplatten (fills) und Konturplatte (keys); beim Zusammensetzen leicht versetzt."""
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.fill = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.key = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.mask = Image.new("L", (w, h), 0)  # Silhouette (Ausschnitt)
        self.f = ImageDraw.Draw(self.fill); self.k = ImageDraw.Draw(self.key); self.m = ImageDraw.Draw(self.mask)
    def poly(self, pts, col, key=True, kw=5, sil=True):
        self.f.polygon(pts, fill=col + (255,))
        if key: self.k.line(pts + [pts[0]], fill=SUMI + (255,), width=kw, joint="curve")
        if sil: self.m.polygon(pts, fill=255)
    def rect(self, b, col, key=True, kw=5, sil=True):
        self.poly([(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])], col, key, kw, sil)
    def bokashi(self, b, c_top, c_bot):
        x0, y0, x1, y1 = [int(v) for v in b]
        for y in range(y0, y1):
            t = (y - y0) / max(1, y1 - y0)
            t = t * t * (3 - 2 * t)
            c = tuple(int(a * (1 - t) + b_ * t) for a, b_ in zip(c_top, c_bot))
            self.f.line([(x0, y), (x1, y)], fill=c + (255,))
    def finish(self, name, grain=True):
        w, h = self.w, self.h
        base = Image.new("RGBA", (w, h), PAPER + (255,))
        # Holzmaserung (Mokume) in den Farbflaechen
        n = Image.effect_noise((w // 2, max(2, h // 18)), 60).resize((w, h), Image.BICUBIC)
        fill = self.fill.copy()
        if grain:
            r, g, b, a = fill.split()
            mod = n.point(lambda v: int(232 + (v - 128) * 0.12))
            r = ImageChops.multiply(r, mod); g = ImageChops.multiply(g, mod); b = ImageChops.multiply(b, mod)
            fill = Image.merge("RGBA", (r, g, b, a))
        shifted = Image.new("RGBA", (w, h), (0, 0, 0, 0)); shifted.paste(fill, REG, fill)
        base.alpha_composite(shifted)
        base.alpha_composite(self.key)
        # Washi-Fasern
        fib = Image.effect_noise((w, h), 30).convert("L").filter(ImageFilter.GaussianBlur(0.5)).point(lambda v: 255 if v > 205 else 0)
        base = Image.composite(Image.new("RGBA", (w, h), (250, 247, 238, 255)), base, fib.point(lambda v: v // 6))
        # weisser Schnittrand (Pop-up-Teile sind mit Papierrand ausgeschnitten)
        margin = self.mask.filter(ImageFilter.MaxFilter(13))
        rim = Image.new("RGBA", (w, h), (250, 247, 238, 255))
        rim.alpha_composite(Image.composite(base, Image.new("RGBA", (w, h), (0, 0, 0, 0)), self.mask))
        base = rim
        base.putalpha(margin)
        base.save(os.path.join(OUT, name))

def tiles(p, x0, x1, y, rows, col_line):
    for r in range(rows):
        yy = y + r * 18
        for x in range(int(x0) - (12 if r % 2 else 0), int(x1), 24):
            p.k.arc([x, yy - 10, x + 24, yy + 14], 0, 180, fill=col_line + (255,), width=3)

def house(name, seed, variant):
    random.seed(seed)
    W, Hh = 1024, 900   # = 8 m x 7 m
    p = Print(W, Hh)
    gy = Hh - 4
    # Dach (Obergeschoss-Dach): Bokashi von dunkel nach mittel, Ziegelreihen
    roof = [(20, 190), (512, 110), (1004, 190), (1004, 250), (20, 250)]
    p.poly(roof, AI1)
    p.bokashi([22, 112, 1002, 248], AI1, AI2)
    p.m.polygon(roof, fill=255)
    tiles(p, 30, 1000, 170, 4, AI1)
    # Obergeschoss: Putz (Papierweiss), Mushiko-Fenster
    p.rect([60, 250, 964, 470], PAPER)
    for k in range(3):
        x = 140 + k * 280
        p.rect([x, 300, x + 180, 420], AI2)
        for j in range(8):
            p.k.rectangle([x + 10 + j * 21, 306, x + 18 + j * 21, 414], fill=PAPER + (255,))
    # Zwischendach (Hisashi)
    p.poly([(10, 470), (1014, 470), (980, 540), (44, 540)], AI1)
    p.bokashi([12, 472, 1012, 538], AI2, AI1)
    tiles(p, 40, 990, 490, 2, AI1)
    # Erdgeschoss: Gitter, Noren in der Mitte (eine Variante mit Beni-Akzent)
    p.rect([60, 540, 964, gy], AI3)
    for x in range(70, 954, 26):
        p.k.rectangle([x, 556, x + 8, gy - 6], fill=AI1 + (255,))
    nc = BENI if variant == 1 else AI1
    p.rect([330, 540, 694, 760], nc)
    for k in range(1, 4):
        p.k.line([(330 + k * 91, 560), (330 + k * 91, 760)], fill=PAPER + (255,), width=6)
    # bewusst kein Kreis/Wappen auf dem Noren (Mon-Risiko)
    p.rect([330, 760, 694, gy], AI1)
    # Firstschild (Kanban) auf dem Dach mit 芝居 in Variante 2
    if variant == 2:
        p.rect([392, 40, 632, 120], PAPER)
        p.k.text((412, 36), "絵本", font=ImageFont.truetype(SERIF, 70), fill=SUMI + (255,))
        p.m.rectangle([392, 40, 632, 120], fill=255)
    p.finish(name)

def theater():
    # Schauspielhaus-Front (eigene Gestaltung, kein reales Theater): breiter Bau, Yagura (Trommelturm)
    # mit Streifentuch (ohne Wappen), Bildtafeln mit eigenen Figuren-Silhouetten, Fahnen.
    W, Hh = 2048, 1280  # = 20 m x 12,5 m
    p = Print(W, Hh)
    gy = Hh - 4
    # Yagura
    p.rect([824, 40, 1224, 300], AI3)
    for k in range(5):
        p.rect([824 + k * 80, 120, 864 + k * 80, 300], AI1, key=False)
    p.poly([(790, 60), (1258, 60), (1224, 20), (824, 20)], AI1)
    for x in (850, 1190):
        p.poly([(x - 6, 0), (x + 6, 0), (x + 6, 40), (x - 6, 40)], SUMI)  # Bonten-Staebe, schlicht
    # Hauptdach
    roof = [(40, 380), (1024, 280), (2008, 380), (2008, 460), (40, 460)]
    p.poly(roof, AI1); p.bokashi([42, 282, 2006, 458], AI1, AI2); tiles(p, 60, 1990, 360, 5, AI1)
    # Bildtafeln (Kanban) – sechs Felder mit eigenen Silhouetten in Mie-Pose
    for k in range(6):
        x = 120 + k * 310
        p.rect([x, 480, x + 260, 760], PAPER)
        p.rect([x + 12, 492, x + 248, 748], AI4, kw=3)
        cx = x + 130
        sil = [(cx - 20, 740), (cx - 6, 660), (cx + 30, 740), (cx + 60, 740), (cx + 18, 650), (cx + 20, 600), (cx + 90, 560),
               (cx + 26, 585), (cx + 22, 560), (cx + 10, 540), (cx - 14, 540), (cx - 24, 562), (cx - 30, 590), (cx - 90, 540),
               (cx - 34, 610), (cx - 40, 660), (cx - 60, 740)]
        p.f.polygon(sil, fill=(AI1 if k % 2 else BENI) + (255,))
        p.f.ellipse([cx - 16, 520, cx + 16, 552], fill=PAPER + (255,))
        p.k.line([(cx - 10, 530), (cx - 2, 536)], fill=(BENI if k % 2 == 0 else AI1) + (255,), width=4)
    # Unterbau: Eingangsvorhaenge, Bank, Holzgitter
    p.rect([60, 780, 1988, gy], AI3)
    for x in range(80, 1980, 30):
        p.k.rectangle([x, 800, x + 8, gy - 4], fill=AI2 + (255,))
    for k in range(3):
        x = 300 + k * 600
        p.rect([x, 780, x + 260, 1050], AI1)
        p.k.text((x + 80, 820), "芝居", font=ImageFont.truetype(SERIF, 54), fill=PAPER + (255,), direction=None)
    # Schriftband ueber den Tafeln
    p.rect([700, 380, 1348, 468], PAPER, kw=6)
    p.k.text((760, 370), "芝居絵本", font=ImageFont.truetype(SERIF, 86), fill=SUMI + (255,))
    p.finish("theater.png")

def pine():
    W, Hh = 768, 1024
    p = Print(W, Hh)
    p.poly([(360, 1020), (410, 1020), (420, 600), (470, 380), (430, 380), (390, 560), (350, 600)], AI1)
    for (cx, cy, w) in [(400, 330, 340), (250, 520, 260), (560, 560, 280), (420, 160, 220), (230, 760, 220), (560, 780, 200)]:
        pts = []
        for i in range(18):
            a = math.pi + i / 17 * math.pi
            pts.append((cx + math.cos(a) * w / 2, cy + math.sin(a) * w * 0.28))
        pts += [(cx + w / 2, cy + 18), (cx - w / 2, cy + 18)]
        p.poly(pts, AI2); p.bokashi([cx - w / 2 + 4, cy - w * 0.28, cx + w / 2 - 4, cy + 16], AI1, AI3)
        for j in range(6):
            x = cx - w / 2 + 20 + j * (w - 40) / 5
            p.k.line([(x, cy + 10), (x + 8, cy - 30)], fill=AI1 + (255,), width=3)
    p.finish("kiefer.png")

def waves():
    # Wellenband (eigene Form): drei Reihen Kaemme mit "Krallen"-Gischt aus Papierweiss
    W, Hh = 1024, 360
    p = Print(W, Hh)
    p.rect([0, 160, W, Hh], AI2, key=False)
    p.bokashi([0, 160, W, Hh], AI2, AI1)
    for r in range(3):
        y = 80 + r * 80
        for x in range(-60 + (r % 2) * 60, W + 60, 140):
            pts = [(x, y + 80)]
            for i in range(12):
                a = math.pi * (1 - i / 11)
                pts.append((x + 70 + math.cos(a) * 70, y + 40 - math.sin(a) * 55))
            pts += [(x + 150, y + 40), (x + 140, y + 80)]
            p.poly(pts, AI1 if r % 2 else AI2, kw=4)
            for k in range(4):
                fx = x + 70 + 46 * math.cos(math.pi * 0.25 * (k + 0.5))
                fy = y + 40 - 50 * math.sin(math.pi * 0.25 * (k + 0.5))
                p.k.ellipse([fx - 7, fy - 7, fx + 7, fy + 7], fill=PAPER + (255,))
    p.finish("wellen.png")

def kasumi():
    # Nebelbaender (Suyari-gasumi): abgerundete Papierbaender mit hellblauer Bokashi-Unterkante
    W, Hh = 1024, 200
    p = Print(W, Hh)
    p.f.rounded_rectangle([10, 30, 1014, 170], 70, fill=PAPER + (255,))
    p.k.rounded_rectangle([10, 30, 1014, 170], 70, outline=AI2 + (255,), width=5)
    p.m.rounded_rectangle([10, 30, 1014, 170], 70, fill=255)
    for y in range(120, 168):
        t = (y - 120) / 48
        p.f.line([(60, y), (964, y)], fill=tuple(int(a * (1 - t) + b * t) for a, b in zip(PAPER, AI4)) + (255,))
    p.finish("kasumi.png", grain=False)

def actor(name, accent):
    # Pop-up-Darsteller in Mie-Pose (eigene Figur): Kimono mit Wellenmuster, Gesicht weiss, eigene Linien
    W, Hh = 600, 1000
    p = Print(W, Hh)
    cx = 300
    body = [(cx - 60, 990), (cx - 20, 700), (cx + 60, 990), (cx + 200, 990), (cx + 90, 640), (cx + 90, 470), (cx + 260, 330),
            (cx + 280, 380), (cx + 110, 520), (cx + 60, 420), (cx + 40, 330), (cx - 40, 330), (cx - 70, 420), (cx - 240, 260),
            (cx - 270, 300), (cx - 110, 520), (cx - 100, 640), (cx - 230, 990)]
    p.poly(body, AI2)
    for r in range(8):
        for x in range(cx - 200, cx + 200, 60):
            y = 520 + r * 55
            p.k.arc([x, y, x + 60, y + 40], 180, 360, fill=AI1 + (255,), width=4)
    p.poly([(cx - 40, 560), (cx + 40, 560), (cx + 50, 610), (cx - 50, 610)], accent)  # Guertel
    p.poly([(cx - 46, 330), (cx + 46, 330), (cx + 20, 300), (cx - 20, 300)], accent)  # Kragen
    p.f.ellipse([cx - 62, 160, cx + 62, 310], fill=PAPER + (255,)); p.k.ellipse([cx - 62, 160, cx + 62, 310], outline=SUMI + (255,), width=5)
    p.m.ellipse([cx - 62, 160, cx + 62, 310], fill=255)
    p.poly([(cx - 66, 200), (cx - 40, 120), (cx + 40, 120), (cx + 66, 200), (cx + 30, 170), (cx - 30, 170)], SUMI)  # Haar
    for s in (-1, 1):
        p.k.line([(cx + s * 12, 230), (cx + s * 40, 205), (cx + s * 58, 175)], fill=accent + (255,), width=10)
        p.k.ellipse([cx + s * 28 - 12, 228, cx + s * 28 + 12, 240], fill=SUMI + (255,))
    p.k.line([(cx - 14, 278), (cx + 14, 278)], fill=SUMI + (255,), width=6)
    p.finish(name)

def cartouche():
    # Titel-Kartusche einer Bilderbuchseite: 芝居絵本 senkrecht, Seitenzahl 十二
    W, Hh = 220, 700
    p = Print(W, Hh)
    p.rect([6, 6, 214, 694], PAPER, kw=6)
    p.k.rectangle([18, 18, 202, 682], outline=BENI + (255,), width=4)
    f = ImageFont.truetype(SERIF, 130)
    for i, ch in enumerate("芝居絵本"):
        w = p.k.textlength(ch, font=f); p.k.text((110 - w / 2, 30 + i * 158), ch, font=f, fill=SUMI + (255,))
    p.finish("kartusche.png", grain=False)

def exit_sign():
    W, Hh = 600, 300
    im = Image.new("RGBA", (W, Hh), (34, 196, 96, 255)); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W - 1, Hh - 1], outline=SUMI + (255,), width=12)
    d.text((40, 20), "出口", font=ImageFont.truetype(SERIF, 190), fill=(255, 255, 255, 255))
    d.text((440, 100), "EXIT", font=ImageFont.truetype(SERIF, 54), fill=(255, 255, 255, 255))
    im.save(os.path.join(OUT, "ausgang.png"))

house("haus_a.png", 1, 0); house("haus_b.png", 2, 1); house("haus_c.png", 3, 2)
theater(); pine(); waves(); kasumi(); actor("darsteller_a.png", BENI); actor("darsteller_b.png", AI1); cartouche(); exit_sign()
print("ok")
