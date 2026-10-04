# Erzeugt kleine Subsets der Noto-CJK-JP-Schriften (SIL OFL 1.1) fuer die Kabuki-/Pappe-Prototypen
# (Richtungen E-G). Nur die benoetigten Zeichen + ASCII. Aufruf: python3 tools/cjk_subset.py
import os
from fontTools import subset
from fontTools.ttLib import TTCollection

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
NOTO = "/usr/share/fonts/opentype/noto/"
# Alle japanischen Schriftzuege der Prototypen (Bedeutung im Kommentar, Pruefung durch Muttersprachler offen):
TEXT = (
    "出口"      # deguchi – Ausgang
    "花道"      # hanamichi – Laufsteg der Kabuki-Buehne
    "大入"      # oo-iri – volles Haus (Glueckszeichen im Theater)
    "芝居町"    # shibai-machi – Theaterviertel
    "天地無用"  # tenchi muyou – nicht stuerzen / diese Seite oben (Paketaufdruck)
    "取扱注意"  # toriatsukai chuui – vorsichtig behandeln
    "ワレモノ"  # waremono – zerbrechlich
    "段ボール"  # danbooru – Wellpappe
    "絵本"      # ehon – Bilderbuch
    "幕"        # maku – Vorhang
    "上下"      # ue/shita – oben/unten
    "水濡れ"    # mizunure (chuui) – vor Naesse schuetzen
    "一二三四五六七八九十"
)
LATIN = "".join(chr(c) for c in range(0x20, 0x7F)) + "ÄÖÜäöüß·–→↑"

def make(ttc, out, idx=0):
    col = TTCollection(NOTO + ttc)
    f = col.fonts[idx]
    tmp = out + ".full.otf"
    f.save(tmp)
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    fnt = subset.load_font(tmp, opts)
    s = subset.Subsetter(opts)
    s.populate(text=TEXT + LATIN)
    s.subset(fnt)
    subset.save_font(fnt, out, opts)
    os.remove(tmp)
    print(out, os.path.getsize(out))

LIC_HEAD = ("Noto Serif CJK / Noto Sans CJK (JP) – Subset fuer BeachVibeStudio-Prototypen\n"
            "Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.\n"
            "Noto is a trademark of Google LLC. Quelle: https://github.com/notofonts/noto-cjk\n\n")

def license_to(d):
    body = open(os.path.join(ROOT, "himmelsbrunn_kulisse", "fonts", "OFL-Jost.txt"), encoding="utf-8").read()
    body = body[body.index("This Font Software"):]
    open(os.path.join(d, "OFL-NotoCJK.txt"), "w", encoding="utf-8").write(LIC_HEAD + body)

for d, files in {
    "kabuki_buehne": [("NotoSerifCJK-Black.ttc", "NotoSerifJP-Black-Subset.otf")],
    "pappkarton": [("NotoSansCJK-Black.ttc", "NotoSansJP-Black-Subset.otf"), ("NotoSerifCJK-Black.ttc", "NotoSerifJP-Black-Subset.otf")],
    "aizuri_popup": [("NotoSerifCJK-Black.ttc", "NotoSerifJP-Black-Subset.otf"), ("NotoSerifCJK-Bold.ttc", "NotoSerifJP-Bold-Subset.otf")],
}.items():
    fd = os.path.join(ROOT, d, "fonts")
    os.makedirs(fd, exist_ok=True)
    for ttc, out in files:
        make(ttc, os.path.join(fd, out))
    license_to(fd)
