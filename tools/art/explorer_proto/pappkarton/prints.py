# Richtung F "Pappstadt Danboru-cho": Druckreste, Marker-Malerei und Schablonen als Decals (Pillow,
# eigene Entwuerfe; Piktogramme bewusst NICHT nach ISO 780 / Normsymbolen nachgezeichnet,
# kein Recycling-/Verbandszeichen, keine echten Firmen, keine Barcodes realer Systeme).
# Aufruf: python3 prints.py -> prints/*.png (RGBA, Tinte mit Abnutzung)
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

H = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(H, "prints"); os.makedirs(OUT, exist_ok=True)
SANS = os.path.join(H, "fonts", "NotoSansJP-Black-Subset.otf")
SERIF = os.path.join(H, "fonts", "NotoSerifJP-Black-Subset.otf")
INK = (32, 26, 22); RED = (176, 40, 36); WHITE = (246, 240, 228)

def worn(im, amount=0.18, seed=1, scale=3):
    # Druckabnutzung: Loecher in der Tinte (Flexodruck auf Wellpappe – Wellen zeichnen sich ab)
    random.seed(seed)
    w, h = im.size
    n = Image.effect_noise((w // scale, h // scale), 70).resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(1))
    flute = Image.new("L", (w, h))
    fd = ImageDraw.Draw(flute)
    for x in range(0, w, 14):
        fd.rectangle([x, 0, x + 3, h], fill=60)  # Wellen-Abdruck: senkrechte, schwaechere Streifen
    hole = n.point(lambda v: 255 if v > 128 + 128 * (1 - amount * 2.2) else 0)
    hole = ImageChops.lighter(hole, flute.point(lambda v: v if random.random() < 1 else 0).point(lambda v: 0))
    a = im.getchannel("A")
    a = ImageChops.subtract(a, hole)
    a = ImageChops.subtract(a, flute.point(lambda v: int(v * amount * 1.5)))
    im.putalpha(a)
    return im

def canvas(w, h): return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def arrows(d, x, y, s, col):
    # eigene "oben"-Pfeile: zwei dicke Pfeile ueber einem Balken
    for k in (0, 1):
        cx = x + k * s * 0.9
        d.polygon([(cx, y), (cx + s * 0.4, y + s * 0.45), (cx + s * 0.15, y + s * 0.45), (cx + s * 0.15, y + s),
                   (cx - s * 0.15, y + s), (cx - s * 0.15, y + s * 0.45), (cx - s * 0.4, y + s * 0.45)], fill=col)
    d.rectangle([x - s * 0.45, y + s * 1.08, x + s * 1.35, y + s * 1.22], fill=col)

def tenchi():
    im = canvas(768, 384); d = ImageDraw.Draw(im)
    d.rectangle([8, 8, 760, 376], outline=INK + (255,), width=14)
    arrows(d, 110, 70, 200, INK + (255,))
    d.text((330, 40), "天地無用", font=ImageFont.truetype(SANS, 104), fill=INK + (255,))
    d.text((334, 190), "THIS SIDE UP", font=ImageFont.truetype(SANS, 54), fill=INK + (255,))
    d.text((334, 262), "上 ↑", font=ImageFont.truetype(SANS, 70), fill=INK + (255,))
    worn(im, 0.2, 2).save(os.path.join(OUT, "tenchi.png"))

def ware():
    im = canvas(512, 512); d = ImageDraw.Draw(im)
    d.rectangle([10, 10, 502, 502], outline=RED + (255,), width=16)
    # eigenes Glas-Symbol: Becher mit Riss (kein Normsymbol nachgezeichnet)
    d.polygon([(150, 70), (360, 70), (330, 260), (180, 260)], fill=RED + (255,))
    d.rectangle([243, 260, 267, 360], fill=RED + (255,))
    d.rectangle([180, 360, 330, 384], fill=RED + (255,))
    d.line([(255, 80), (238, 140), (268, 175), (246, 240)], fill=(0, 0, 0, 0), width=10)
    d.text((86, 400), "ワレモノ", font=ImageFont.truetype(SANS, 84), fill=RED + (255,))
    worn(im, 0.22, 3).save(os.path.join(OUT, "ware.png"))

def toriatsukai():
    im = canvas(768, 256); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 767, 255], fill=RED + (255,))
    d.text((40, 30), "取扱注意", font=ImageFont.truetype(SANS, 150), fill=(0, 0, 0, 0))
    worn(im, 0.15, 4).save(os.path.join(OUT, "toriatsukai.png"))

def kasa():
    im = canvas(512, 512); d = ImageDraw.Draw(im)
    d.rectangle([10, 10, 502, 502], outline=INK + (255,), width=16)
    # eigener Schirm: Halbkreis mit 3 Bogen-Kerben, Griff
    d.pieslice([90, 90, 422, 360], 180, 360, fill=INK + (255,))
    for k in range(4):
        d.ellipse([90 + k * 83, 200, 173 + k * 83, 260], fill=(0, 0, 0, 0))
    d.rectangle([248, 220, 264, 380], fill=INK + (255,))
    d.arc([200, 340, 264, 410], 0, 180, fill=INK + (255,), width=16)
    for k in range(5):
        d.line([(120 + k * 70, 60), (100 + k * 70, 100)], fill=INK + (255,), width=10)
    d.text((86, 410), "水濡れ注意", font=ImageFont.truetype(SANS, 60), fill=INK + (255,))
    worn(im, 0.2, 5).save(os.path.join(OUT, "kasa.png"))

def label():
    # Versandetikett (Papier) mit erfundener Adresse und Fantasie-Strichcode
    im = Image.new("RGBA", (512, 340), WHITE + (255,)); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 511, 339], outline=INK + (255,), width=6)
    f = ImageFont.truetype(SANS, 34)
    d.text((24, 18), "段ボール町 1-2-3", font=f, fill=INK + (255,))
    d.text((24, 64), "DANBORU-CHO  1-2-3", font=ImageFont.truetype(SANS, 28), fill=INK + (255,))
    d.text((24, 104), "ZAPMANIAC THEATER", font=ImageFont.truetype(SANS, 28), fill=INK + (255,))
    random.seed(9); x = 24
    while x < 480:
        w = random.choice([3, 3, 6, 9]); d.rectangle([x, 170, x + w, 300], fill=INK + (255,)); x += w + random.choice([4, 6, 9])
    im.save(os.path.join(OUT, "etikett.png"))

def kumadori_face(name, line_col):
    # Marker-Malerei auf Pappe: weiss deckend gemaltes Gesicht, eigene Linien (keine Rollen-Kumadori)
    im = canvas(512, 640); d = ImageDraw.Draw(im)
    random.seed(len(name))
    pts = [(256 + math.cos(a) * 200 * (1 + random.uniform(-0.03, 0.03)), 320 + math.sin(a) * 280 * (1 + random.uniform(-0.03, 0.03)))
           for a in [i / 40 * 2 * math.pi for i in range(40)]]
    d.polygon(pts, fill=WHITE + (255,))
    lc = line_col + (255,)
    for s in (-1, 1):
        d.line([(256 + s * 30, 300), (256 + s * 90, 250), (256 + s * 150, 150), (256 + s * 175, 80)], fill=lc, width=34, joint="curve")
        d.line([(256 + s * 60, 450), (256 + s * 140, 420), (256 + s * 170, 340)], fill=lc, width=26, joint="curve")
        d.ellipse([256 + s * 80 - 40, 290, 256 + s * 80 + 40, 330], fill=INK + (255,))
    d.line([(206, 500), (306, 500)], fill=INK + (255,), width=18)
    # Marker-Strichkante: leicht ausgefranst
    im = im.filter(ImageFilter.GaussianBlur(1.2))
    worn(im, 0.06, 7, 2).save(os.path.join(OUT, name))

def lantern():
    im = Image.new("RGBA", (256, 512), (150, 104, 60, 255)); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 256, 70], fill=RED + (255,)); d.rectangle([0, 442, 256, 512], fill=RED + (255,))
    f = ImageFont.truetype(SERIF, 140)
    for i, ch in enumerate("大入"):
        w = d.textlength(ch, font=f); d.text((128 - w / 2, 96 + i * 160), ch, font=f, fill=INK + (255,))
    worn(im, 0.08, 8).save(os.path.join(OUT, "laterne.png"))

def exit_stencil():
    # Schablonen-Schrift (Stege in den Zeichen), weiss auf gruener Pappe
    im = canvas(768, 384); d = ImageDraw.Draw(im)
    d.text((40, 20), "出口", font=ImageFont.truetype(SANS, 260), fill=WHITE + (255,))
    for (x, y) in ((168, 60), (168, 250), (430, 120)):
        d.rectangle([x, y, x + 9, y + 40], fill=(0, 0, 0, 0))  # wenige Schablonenstege, Zeichen bleiben lesbar
    d.text((560, 90), "EXIT", font=ImageFont.truetype(SANS, 80), fill=WHITE + (255,))
    d.polygon([(560, 260), (680, 260), (680, 230), (740, 290), (680, 350), (680, 320), (560, 320)], fill=WHITE + (255,))
    worn(im, 0.1, 10).save(os.path.join(OUT, "ausgang.png"))

def shop_sign(name, txt, col):
    im = canvas(768, 192); d = ImageDraw.Draw(im)
    d.text((24, 8), txt, font=ImageFont.truetype(SERIF, 150), fill=col + (255,))
    worn(im, 0.1, len(txt)).save(os.path.join(OUT, name))

tenchi(); ware(); toriatsukai(); kasa(); label(); kumadori_face("gesicht_held.png", RED); kumadori_face("gesicht_gegen.png", (40, 62, 120))
lantern(); exit_stencil(); shop_sign("schild_芝居.png".replace("芝居", "shibai"), "芝居町", INK); shop_sign("schild_dan.png", "段ボール", INK)
print("ok")
