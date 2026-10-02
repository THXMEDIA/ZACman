# Style-Tiles + Capsule-Probe fuer den Tokyo-Prototyp (Pillow).
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
B = "/tmp/claude-0/-home-claude/1aaa4092-a4a3-5e5c-b391-8d187e585776/scratchpad/tokyo_shots/"
INTER = "/usr/share/fonts/opentype/inter/Inter-%s.otf"
CJK = "/usr/share/fonts/opentype/noto/NotoSansCJK-%s.ttc"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONOB = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
def F(p, s, idx=0):
    return ImageFont.truetype(p, s, index=idx)

def glow_text(img, xy, text, font, col, blur=6, strength=2):
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=font, fill=col)
    g = layer.filter(ImageFilter.GaussianBlur(blur))
    for _ in range(strength):
        img.paste(ImageChops.add(img, g))
    img.paste(ImageChops.add(img, layer))

DIRS = {
 "natriumregen": dict(
   title="A  NATRIUMREGEN", idea="Nasser Asphalt als einzige photoreale Fläche; die Stadt ist Natriumlicht, Weiß und ein Magenta-Akzent.",
   bg="#060504", fg="#f2efe8",
   pal=[("#060504","Himmel/Hintergrund"),("#030304","Gebäudemasse"),("#0b0a0c","Asphalt nass"),("#ff9a2e","Welt: Natrium-Amber"),("#f2efe8","Welt: Kaltweiß"),("#ff2e88","Akzent: Screens/Rundturm"),("#ffd98a","Kugeln (warmes Gold)"),("#39ff6a","U-Bahn (exklusiv)")],
   roles=[("Welt","#ff9a2e"),("Verkehr","#ffffff","#ff2a1a"),("Passanten","#a49a8c"),("Kugeln","#ffd98a"),("U-Bahn","#39ff6a")],
   shot="natriumregen_strasse.png"),
 "linienstadt": dict(
   title="B  LINIENSTADT", idea="Fast nur Schwarz und haarfeine Kaltweiß-Linien; Farbe gibt es nur als Rolle, der Boden ist eine schwarze Glasfläche.",
   bg="#000000", fg="#dfe8f0",
   pal=[("#000000","Himmel, Masse, Boden"),("#dfe8f0","Welt: Kaltweiß"),("#8d98a6","Welt: Stahlgrau (2. Ebene)"),("#6d7884","Passanten"),("#ffffff","Scheinwerfer"),("#ff1f3d","Rücklichter"),("#ffcf6e","Kugeln"),("#00ff9c","U-Bahn (exklusiv)")],
   roles=[("Welt","#dfe8f0"),("Verkehr","#ffffff","#ff1f3d"),("Passanten","#6d7884"),("Kugeln","#ffcf6e"),("U-Bahn","#00ff9c")],
   shot="linienstadt_strasse.png"),
 "natriumdunst": dict(
   title="C  NATRIUMDUNST", idea="Die ganze Stadt steht in warmem Natriumnebel; Linien tauchen aus dem Dunst auf, nur der Weg zur U-Bahn ist kalt.",
   bg="#2a1305", fg="#ffd9a0",
   pal=[("#2a1305","Himmel"),("#3d1f08","Dunst/Nebel"),("#050201","Gebäudemasse"),("#ffb347","Welt: Amber"),("#ff7a1a","Welt: Orange"),("#ff3b2f","Akzent: Rot (Screens)"),("#fff0c8","Kugeln"),("#00e5d4","U-Bahn (exklusiv)")],
   roles=[("Welt","#ffb347"),("Verkehr","#fff4e0","#ff1a0a"),("Passanten","#b07a48"),("Kugeln","#fff0c8"),("U-Bahn","#00e5d4")],
   shot="natriumdunst_strasse.png"),
}

def hexrgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def lum(h):
    r, g, b = hexrgb(h); return 0.2126*r + 0.7152*g + 0.0722*b

def tile(key, D):
    W, H = 1600, 1000
    img = Image.new("RGB", (W, H), hexrgb(D["bg"]))
    d = ImageDraw.Draw(img)
    fg = hexrgb(D["fg"])
    d.text((60, 40), D["title"], font=F(INTER % "Bold", 54), fill=fg)
    d.text((60, 110), D["idea"], font=F(INTER % "Regular", 24), fill=tuple(int(c*0.75) for c in fg))
    # Palette
    x, y = 60, 170
    for i, (h, role) in enumerate(D["pal"]):
        cx = x + (i % 4) * 200; cy = y + (i // 4) * 170
        d.rectangle([cx, cy, cx + 170, cy + 100], fill=hexrgb(h), outline=(70, 70, 70))
        d.text((cx, cy + 106), h.upper(), font=F(MONOB, 18), fill=fg)
        d.text((cx, cy + 130), role, font=F(INTER % "Regular", 14), fill=tuple(int(c*0.7) for c in fg))
    # Schriftprobe
    sy = 540
    d.text((60, sy), "Schrift", font=F(INTER % "SemiBold", 18), fill=tuple(int(c*0.6) for c in fg))
    glow_text(img, (60, sy + 28), "SHIBUYA", F(INTER % "Black", 60), fg, 8, 1)
    glow_text(img, (360, sy + 22), "渋谷", F(CJK % "Black", 62, 0), fg, 8, 1)
    d = ImageDraw.Draw(img)
    d.text((60, sy + 110), "Inter Black / Regular — UI, Titel  (SIL OFL 1.1, rsms.me/inter)", font=F(INTER % "Regular", 18), fill=fg)
    glow_text(img, (60, sy + 145), "ラーメン  カラオケ  薬  地下鉄", F(CJK % "Bold", 40, 0), hexrgb(D["roles"][0][1]), 6, 1)
    d = ImageDraw.Draw(img)
    d.text((60, sy + 205), "Noto Sans CJK JP Bold — Schilder/Screens  (SIL OFL 1.1, github.com/notofonts/noto-cjk)", font=F(INTER % "Regular", 18), fill=fg)
    d.text((60, sy + 240), "PUNKTE 1280   ZEIT 0:42.17   ZAC>_", font=F(MONOB, 26), fill=hexrgb(D["roles"][3][1]))
    d.text((60, sy + 278), "DejaVu Sans Mono Bold — HUD-Zahlen, ASCII-Übergang  (Bitstream-Vera-Lizenz, frei)", font=F(INTER % "Regular", 18), fill=fg)
    # Rollen
    rx, ry = 860, 170
    d.text((rx, ry - 10), "Rollenfarben", font=F(INTER % "SemiBold", 18), fill=tuple(int(c*0.6) for c in fg))
    for i, r in enumerate(D["roles"]):
        yy = ry + 30 + i * 62
        name = r[0]; c1 = hexrgb(r[1])
        d.text((rx, yy + 10), name, font=F(INTER % "Bold", 22), fill=fg)
        if name == "Welt":
            d.line([(rx + 170, yy + 40), (rx + 170, yy + 4), (rx + 260, yy + 4), (rx + 260, yy + 40)], fill=c1, width=3)
        elif name == "Verkehr":
            d.rectangle([rx + 170, yy + 14, rx + 210, yy + 24], fill=c1)
            d.rectangle([rx + 230, yy + 14, rx + 270, yy + 24], fill=hexrgb(r[2]))
            d.text((rx + 290, yy + 10), "vorn weiß / hinten rot", font=F(INTER % "Regular", 16), fill=fg)
        elif name == "Passanten":
            px = rx + 200
            d.ellipse([px - 8, yy, px + 8, yy + 16], outline=c1, width=2)
            d.line([(px, yy + 16), (px, yy + 34), (px - 9, yy + 48)], fill=c1, width=2)
            d.line([(px, yy + 34), (px + 9, yy + 48)], fill=c1, width=2)
            d.arc([px - 30, yy - 18, px + 30, yy + 18], 180, 360, fill=c1, width=2)
            d.text((rx + 290, yy + 10), "~50 % Gebäudehelligkeit", font=F(INTER % "Regular", 16), fill=fg)
        elif name == "Kugeln":
            for k in range(4):
                cx = rx + 190 + k * 40
                d.ellipse([cx - 11, yy + 8, cx + 11, yy + 30], fill=c1)
            d.text((rx + 360, yy + 10), "massiv, Augenhöhe", font=F(INTER % "Regular", 16), fill=fg)
        elif name == "U-Bahn":
            d.rectangle([rx + 170, yy, rx + 270, yy + 46], fill=c1)
            d.text((rx + 290, yy + 10), "einzige gefüllte Fläche", font=F(INTER % "Regular", 16), fill=fg)
    img2 = img.filter(ImageFilter.GaussianBlur(5))
    # Szenenausschnitt
    sh = Image.open(B + D["shot"]).convert("RGB").resize((640, 360))
    img.paste(sh, (W - 640 - 60, H - 360 - 50))
    d = ImageDraw.Draw(img)
    d.text((W - 640 - 60, H - 46), "Godot-4.3-Prototyp, Compatibility-Renderer", font=F(INTER % "Regular", 15), fill=tuple(int(c*0.6) for c in fg))
    img.save(B + key + "_styletile.png")

for k, D in DIRS.items():
    tile(k, D)

# ---------------- Capsule-Probe (Richtung A) ----------------
src = Image.open(B + "natriumregen_capsulecam.png").convert("RGB")
# Ausschnitt 1280x598 (Seitenverhaeltnis 460:215)
crop = src.crop((0, 40, 1280, 40 + 598)).resize((920, 430), Image.LANCZOS)
W, H = crop.size
random.seed(3)
# Rechts zerfallen die Linien zu Matrix-ASCII: Bild in Zellen, Helligkeit -> Glyphe
cell = 12
ascii_layer = Image.new("RGB", (W, H), (0, 0, 0))
ad = ImageDraw.Draw(ascii_layer)
glyphs = "01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ:+*#=ZAC"
gfont = F(CJK % "Bold", 12, 0)
small = crop.resize((W // cell, H // cell), Image.BOX)
mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
for gy in range(H // cell):
    for gx in range(W // cell):
        x = gx * cell
        t = (x - W * 0.80) / (W * 0.18)  # 0..1 Uebergang
        if t <= 0:
            continue
        if random.random() > min(1.0, t * 1.4):
            continue
        r, g, b = small.getpixel((gx, gy))
        v = max(r, g, b)
        if v < 18:
            if random.random() < 0.06 * t:
                ad.text((x, gy * cell - 2), random.choice(glyphs), font=gfont, fill=(20, 110, 40))
            continue
        k = min(1.0, v / 255 * 1.6)
        col = (int(40 * k), int(255 * k), int(90 * k))
        ad.text((x, gy * cell - 2), random.choice(glyphs), font=gfont, fill=col)
        md.rectangle([x, gy * cell, x + cell, gy * cell + cell], fill=int(255 * min(1, t * 1.2)))
mask = mask.filter(ImageFilter.GaussianBlur(3))
dark = Image.new("RGB", (W, H), (0, 0, 0))
base = Image.composite(dark, crop, mask)
cap = ImageChops.add(base, ascii_layer)
cap = ImageChops.add(cap, ascii_layer.filter(ImageFilter.GaussianBlur(4)))
# Titel
d = ImageDraw.Draw(cap)
shade = Image.new("L", (W, H), 0)
ImageDraw.Draw(shade).rectangle([0, 0, W, 150], fill=170)
shade = shade.filter(ImageFilter.GaussianBlur(40))
cap = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), cap, shade)
tf = F(INTER % "Black", 118)
glow_text(cap, (34, 14), "ZACman", tf, (255, 226, 170), 5, 1)
d = ImageDraw.Draw(cap)
d.text((42, 150), "TOKYO", font=F(INTER % "Bold", 34), fill=(255, 154, 46))
d.text((176, 142), "渋谷", font=F(CJK % "Bold", 34, 0), fill=(255, 46, 136))
cap = cap.resize((460, 215), Image.LANCZOS)
cap.save(B + "natriumregen_capsule_460x215.png")
cap.resize((184, 69), Image.LANCZOS).save(B + "natriumregen_capsule_184x69.png")
# Vergleichsbogen: 184x69 in 4facher Vergroesserung (nearest) zum Beurteilen
cap.resize((184, 69), Image.LANCZOS).resize((736, 276), Image.NEAREST).save(B + "natriumregen_capsule_184x69_zoom4.png")
print("ok")
