# Richtung J v2: Steam-Capsule-Mockups aus den Renderings (Pillow). Aufruf: python3 capsule.py <bildordner>
# Erwartet <bildordner>/<variante>/capsule.png, schreibt capsule_920x430.png und capsule_460x215.png daneben.
# Titel als Modellbau-Schild (weisser Karton, Bleistift-Massstab). Schrift: Inter (SIL OFL 1.1).
import os, sys
from PIL import Image, ImageDraw, ImageFont

B = sys.argv[1]
INTER = "/usr/share/fonts/opentype/inter/Inter-%s.otf"
def F(w, s): return ImageFont.truetype(INTER % w, s)
for v in sorted(os.listdir(B)):
    src = os.path.join(B, v, "capsule.png")
    if not os.path.exists(src):
        continue
    im = Image.open(src).convert("RGB")
    crop = im.crop((0, 60, 1280, 60 + 598)).resize((920, 430), Image.LANCZOS)
    dark = v in ("nacht", "studio")
    d = ImageDraw.Draw(crop)
    L0, R0, T0 = 24, 444, 22
    sh = Image.new("RGBA", crop.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rectangle([L0 + 6, T0 + 8, R0 + 6, T0 + 154], fill=(0, 0, 0, 90))
    crop.paste(sh, (0, 0), sh)
    d.rectangle([L0, T0, R0, T0 + 146], fill=(240, 236, 226), outline=(110, 98, 84), width=2)
    f1 = F("Bold", 74)
    tw = d.textlength("ZAPmaniac", font=f1)
    d.text(((L0 + R0) / 2 - tw / 2, T0 + 4), "ZAPmaniac", font=f1, fill=(43, 33, 24))
    d.line([(L0 + 30, T0 + 94), (R0 - 30, T0 + 94)], fill=(150, 140, 128), width=2)
    for k in range(11):   # Massstab-Striche
        x = L0 + 30 + k * (R0 - L0 - 60) / 10
        d.line([(x, T0 + 94), (x, T0 + 88 if k % 5 else T0 + 84)], fill=(150, 140, 128), width=2)
    t2 = "EXPLORER · AMSTERDAM  M 1:100"
    f2 = F("Medium", 22)
    tw2 = d.textlength(t2, font=f2)
    d.text(((L0 + R0) / 2 - tw2 / 2, T0 + 104), t2, font=f2, fill=(91, 74, 58))
    crop.save(os.path.join(B, v, "capsule_920x430.png"))
    crop.resize((460, 215), Image.LANCZOS).save(os.path.join(B, v, "capsule_460x215.png"))
    print("capsule", v)
