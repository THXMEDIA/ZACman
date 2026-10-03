#!/usr/bin/env python3
"""Schnitt des ZAPmaniac-Trailer-Pitch v2 (intern, nicht zur Veröffentlichung).

Setzt die von trailer_capture.gd aufgenommenen Szenen zu 80 s zusammen und
legt Texttafeln, Run-Timer, Chat-Einblendung, Bestenliste, Glitch-Übergänge,
Wasserzeichen und die Temp-Musik (music.py) darüber.

    python3 tools/trailer/compose.py FRAMES_DIR MUSIC_WAV OUT_MP4

Namen auf der Bestenliste kommen aus TRAILER_NAMES (sonst neutrale
Platzhalter). Echte Personen nur im internen Pitch und vor jeder externen
Nutzung ersetzen oder schriftliche Zustimmung einholen.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FPS = 30
W, H = 1920, 1080
TOTAL = 80 * FPS

FR, MUSIC, OUT = sys.argv[1], sys.argv[2], sys.argv[3]

FONT_BOLD = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
FONT_MED = "/usr/share/fonts/truetype/google-fonts/Poppins-Medium.ttf"
FONT_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
_fc = {}


def font(path, size):
    k = (path, size)
    if k not in _fc:
        _fc[k] = ImageFont.truetype(path, size)
    return _fc[k]


def seg_frame(seg, i):
    files = _list(seg)
    i = max(0, min(len(files) - 1, i))
    return Image.open(os.path.join(FR, seg, files[i])).convert("RGB")


_lc = {}


def _list(seg):
    if seg not in _lc:
        _lc[seg] = sorted(f for f in os.listdir(os.path.join(FR, seg)) if f.endswith(".png"))
    return _lc[seg]


def black():
    return Image.new("RGB", (W, H), (0, 0, 0))


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def text_center(img, text, y, size=72, fill=(245, 245, 245), alpha=1.0, fnt=FONT_BOLD, shadow=True):
    if alpha <= 0:
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(fnt, size)
    w = d.textlength(text, font=f)
    x = (W - w) / 2
    a = int(255 * alpha)
    if shadow:
        for dx, dy in ((4, 4), (0, 4), (4, 0)):
            d.text((x + dx, y + dy), text, font=f, fill=(0, 0, 0, int(a * 0.8)))
    d.text((x, y), text, font=f, fill=fill + (a,))
    img.paste(layer, (0, 0), layer)


def fade_in_out(t, t0, t1, f=0.35):
    if t < t0 or t > t1:
        return 0.0
    return min(1.0, (t - t0) / f, (t1 - t) / f)


def fmt(s):
    m = int(s // 60)
    return "%d:%05.2f" % (m, s - m * 60)


def timer(img, secs, color=(255, 255, 255), sub=None, sub_color=(90, 235, 130), scale=1.0):
    d = ImageDraw.Draw(img, "RGBA")
    f = font(FONT_MONO, int(84 * scale))
    t = fmt(secs)
    w = d.textlength(t, font=f)
    x, y = W - w - 70, H - int(150 * scale)
    d.rounded_rectangle([x - 26, y - 8, W - 44, y + int(108 * scale)], 14, fill=(0, 0, 0, 170))
    d.text((x, y), t, font=f, fill=color)
    if sub:
        fs = font(FONT_BOLD, 46)
        sw = d.textlength(sub, font=fs)
        d.text((W - sw - 70, y - 70), sub, font=fs, fill=sub_color)


def watermark(img):
    d = ImageDraw.Draw(img, "RGBA")
    f = font(FONT_MED, 22)
    d.text((30, 22), "INTERN · PITCH v2 · NICHT ZUR VERÖFFENTLICHUNG", font=f, fill=(255, 255, 255, 120))


def glitch(img, strength, seed):
    """RGB split + horizontal block displacement."""
    import random
    rnd = random.Random(seed)
    r, g, b = img.split()
    off = int(30 * strength)
    r = r.transform(img.size, Image.AFFINE, (1, 0, off, 0, 1, 0))
    b = b.transform(img.size, Image.AFFINE, (1, 0, -off, 0, 1, 0))
    out = Image.merge("RGB", (r, g, b))
    for _ in range(int(14 * strength)):
        y = rnd.randrange(0, H - 40)
        h = rnd.randrange(8, 90)
        dx = rnd.randrange(-int(220 * strength) - 1, int(220 * strength) + 1)
        band = out.crop((0, y, W, y + h))
        out.paste(band, (dx, y))
    return out


# ------------------------------------------------------------ leaderboard

# Platzhalter-Namen; für den internen Pitch per TRAILER_NAMES (Komma-Liste,
# 6 Namen) überschreibbar. Echte Namen gehören nicht ins öffentliche Repo.
_NAMES = os.environ.get("TRAILER_NAMES", "Runner_A,Runner_B,Runner_C,Runner_D,Runner_E,Runner_F").split(",")
BOARD_BEFORE = [(n, t) for n, t in zip(_NAMES, (108.91, 109.02, 109.15, 109.33, 109.41, 109.58))] + [("YOU", 109.60)]
YOU_NEW = 108.76


def leaderboard(bg, t):
    img = bg.filter(ImageFilter.GaussianBlur(14))
    img = Image.blend(img, black(), 0.55)
    d = ImageDraw.Draw(img, "RGBA")
    px, py, pw, ph = 520, 150, 880, 640
    d.rounded_rectangle([px, py, px + pw, py + ph], 22, fill=(4, 18, 28, 235), outline=(60, 220, 230, 255), width=3)
    d.text((px + 50, py + 34), "KANINCHEN DER WOCHE · KW 41", font=font(FONT_BOLD, 40), fill=(90, 225, 235))
    tabs = ["WOCHE", "CHAOS", "CHAT"]
    active = 0
    if 3.4 < t < 3.9:
        active = 1
    elif 3.9 < t < 4.4:
        active = 2
    for k, tab in enumerate(tabs):
        x = px + 50 + k * 170
        on = k == active
        d.rounded_rectangle([x, py + 98, x + 150, py + 140], 8, fill=(40, 180, 190, 255) if on else (20, 50, 60, 255))
        d.text((x + 22, py + 104), tab, font=font(FONT_MED, 24), fill=(0, 0, 0) if on else (160, 200, 205))
    # rows: YOU climbs from #7 to #1 between 1.0 and 2.6 s
    climb = ease((t - 1.0) / 1.6)
    others = [r for r in BOARD_BEFORE if r[0] != "YOU"]
    row_h = 62
    y0 = py + 170
    you_slot = 6 - 6 * climb
    for k, (name, tm) in enumerate(others):
        slot = k + min(1.0, max(0.0, k + 1 - you_slot))
        y = y0 + slot * row_h
        rank = int(round(slot)) + 1
        d.text((px + 50, y), "#%d" % rank, font=font(FONT_BOLD, 34), fill=(200, 200, 200))
        d.text((px + 160, y), name, font=font(FONT_MED, 34), fill=(225, 225, 225))
        d.text((px + 620, y), fmt(tm), font=font(FONT_MONO, 34), fill=(225, 225, 225))
    y = y0 + you_slot * row_h
    you_t = 109.60 + (YOU_NEW - 109.60) * min(1.0, climb * 1.4)
    d.rounded_rectangle([px + 30, y - 8, px + pw - 30, y + 52], 10, fill=(58, 46, 14, 255), outline=(255, 210, 70, 255), width=2)
    rank = int(round(you_slot)) + 1
    d.text((px + 50, y), "#%d" % rank, font=font(FONT_BOLD, 34), fill=(255, 215, 80))
    d.text((px + 160, y), "YOU", font=font(FONT_BOLD, 34), fill=(255, 215, 80))
    d.text((px + 620, y), fmt(you_t), font=font(FONT_MONO, 34), fill=(255, 215, 80))
    if climb >= 1.0:
        d.text((px + 790, y + 4), "▲6", font=font("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28), fill=(90, 235, 130))
    text_center(img, "SAME MAZE. EVERY WEEK. ONE LEADERBOARD.", 860, 62, alpha=fade_in_out(t, 1.8, 5.2, 0.3))
    return img


# ------------------------------------------------------------ chat

CHAT = [
    ("pelletgoblin", "!schlecht"), ("mazeenjoyer", "!gut"), ("ghost_of_blinky", "!schlecht"),
    ("whiterabbit_fan", "!schlecht"), ("speedy_sloth", "!gut"), ("ascii_andy", "!schlecht"),
    ("neon_noodle", "!schlecht"), ("cherry_bomb", "!gut"), ("kippbild_kai", "!schlecht"),
    ("frame_perfect", "!schlecht"), ("zap_zap_zap", "!schlecht"), ("loopholelisa", "!gut"),
]


def chat_overlay(img, t):
    d = ImageDraw.Draw(img, "RGBA")
    x, y, w, h = 60, 230, 560, 600
    d.rounded_rectangle([x, y, x + w, y + h], 16, fill=(10, 8, 20, 200), outline=(145, 70, 255, 255), width=3)
    d.text((x + 24, y + 16), "STREAM CHAT", font=font(FONT_BOLD, 28), fill=(190, 150, 255))
    shown = min(len(CHAT), int(t * 3.2) + 1)
    lines = CHAT[max(0, shown - 9):shown]
    for k, (u, c) in enumerate(lines):
        yy = y + 70 + k * 56
        d.text((x + 24, yy), u, font=font(FONT_MED, 26), fill=(150, 200, 255))
        uw = d.textlength(u, font=font(FONT_MED, 26))
        d.text((x + 34 + uw, yy), c, font=font(FONT_BOLD, 26), fill=(255, 110, 110) if "schlecht" in c else (110, 235, 140))
    # vote bar: good share falls from 60 % towards 28 %
    good = 0.60 - 0.32 * ease(t / 4.0)
    bx, by, bw = 60, 860, 560
    d.rounded_rectangle([bx, by, bx + bw, by + 46], 10, fill=(40, 40, 40, 230))
    d.rounded_rectangle([bx, by, bx + int(bw * good), by + 46], 10, fill=(90, 220, 120, 255))
    d.rounded_rectangle([bx + int(bw * good), by, bx + bw, by + 46], 10, fill=(230, 80, 90, 255))
    d.text((bx + 14, by + 6), "GUT %d %%" % round(good * 100), font=font(FONT_BOLD, 26), fill=(0, 0, 0))
    lbl = "SCHLECHT %d %%" % round((1 - good) * 100)
    d.text((bx + bw - 14 - d.textlength(lbl, font=font(FONT_BOLD, 26)), by + 6), lbl, font=font(FONT_BOLD, 26), fill=(0, 0, 0))


# ------------------------------------------------------------ timeline

def frame_at(n):
    t = n / FPS
    if t < 5.0:  # hook
        img = black()
        msg = "FOLLOW THE WHITE RABBIT."
        k = int(len(msg) * ease((t - 0.4) / 2.2)) if t > 0.4 else 0
        text_center(img, msg[:k], 440, 84)
        if t > 3.2:
            text_center(img, "BUT BEWARE.", 560, 84, fill=(225, 40, 45), alpha=min(1.0, (t - 3.2) / 0.15))
            if t < 3.45:
                img = glitch(img, 0.8, n)
        return img
    if t < 12.0:  # s02 sprint
        i = n - 150
        img = seg_frame("s02", i)
        if i < 3:
            img = glitch(img, 1.0 - i / 3, n)
        timer(img, 12.40 + i / FPS)
        return img
    if t < 16.0:  # s03 rabbit
        i = n - 360
        img = seg_frame("s03", i)
        timer(img, 19.40 + i / FPS)
        return img
    if t < 19.0:  # s04 title card (HUD visible)
        i = n - 480
        img = seg_frame("s04", i)
        if i < 5:
            img = glitch(img, 1.0 - i / 5, n)
        return img
    if t < 24.0:  # s05 matrix
        i = n - 570
        img = seg_frame("s05", i)
        if i < 3:
            img = glitch(img, 0.8, n)
        timer(img, 23.40 + i / FPS * 0.6, color=(90, 255, 120))
        text_center(img, "THE RULES ARE OPTIONAL", 120, 80, alpha=fade_in_out(t, 19.4, 23.8))
        return img
    if t < 28.0:  # s06 fear & loathing
        i = n - 720
        img = seg_frame("s06", i)
        if i < 3:
            img = glitch(img, 0.8, n)
        timer(img, 26.40 + i / FPS * 1.4, color=(255, 90, 90))
        text_center(img, "…UNTIL THEY TURN ON YOU", 120, 80, alpha=fade_in_out(t, 24.3, 27.8))
        return img
    if t < 31.0:  # s07 blackout / pocket watch
        i = n - 840
        img = seg_frame("s07", i)
        if i < 3 or 45 <= i < 48:
            img = glitch(img, 0.9, n)
        timer(img, 32.00 + i / FPS)
        return img
    if t < 36.0:  # s08 chat
        i = n - 930
        img = seg_frame("s08", i)
        chat_overlay(img, t - 31.0)
        timer(img, 61.10 + i / FPS)
        text_center(img, "YOUR CHAT DECIDES HOW BAD IT GETS", 110, 72, alpha=fade_in_out(t, 31.4, 35.8))
        return img
    if t < 41.0:  # s09 finish + freeze
        i = n - 1080
        img = seg_frame("s09", min(i, 59))
        frozen = i >= 60
        secs = 106.76 + min(i, 60) / FPS
        if frozen:
            pop = ease((i - 60) / 6)
            timer(img, 108.76, color=(255, 215, 80), sub="NEW BEST  −0.84" if pop > 0.5 else None, scale=1.0 + 0.15 * (1 - pop))
            text_center(img, "EVERY HUNDREDTH COUNTS.", 120, 80, alpha=fade_in_out(t, 38.3, 40.9))
            if i < 63:
                img = glitch(img, 0.7, n)
        else:
            timer(img, secs)
        return img
    if t < 46.0:  # leaderboard
        return leaderboard(seg_frame("s09", 59), t - 41.0)
    if t < 54.0:  # s11 Tokyo street, glitch out of the ASCII world
        i = n - 1380
        img = seg_frame("s11", i)
        if i < 45:
            src = seg_frame("s05", 149)
            k = ease(i / 45)
            img = Image.blend(glitch(src, 1.0 - k * 0.5, n), glitch(img, (1 - k) * 0.8, n + 7), k)
        text_center(img, "BUT THERE IS ALSO TIME TO RELAX…", 860, 74, alpha=fade_in_out(t, 48.0, 53.6, 0.8))
        return img
    if t < 64.0:  # s12 crossing
        i = n - 1620
        img = seg_frame("s12", i)
        if i < 15:
            img = Image.blend(seg_frame("s11", 239), img, i / 15)
        text_center(img, "…AND WORLDS TO EXPLORE.", 860, 74, alpha=fade_in_out(t, 55.5, 63.4, 0.8))
        return img
    if t < 70.0:  # s13 alley, subway, Manhattan
        i = n - 1920
        img = seg_frame("s13", i)
        for cut in (90, 150):
            if cut <= i < cut + 8:
                img = Image.blend(seg_frame("s13", cut - 1), img, (i - cut) / 8)
        return img
    if t < 73.5:  # s14 new run
        i = n - 2100
        img = seg_frame("s14", i)
        if i < 4:
            img = glitch(img, 1.0, n)
        timer(img, i / FPS)
        return img
    # logo
    img = black()
    lt = t - 73.5
    if lt < 0.2:
        return glitch(seg_frame("s14", 104), 1.0, n)
    text_center(img, "ZAPmaniac", 330, 170, fill=(255, 225, 80), alpha=ease(lt / 0.4))
    text_center(img, "RACE THE WEEK.", 560, 64, alpha=ease((lt - 0.8) / 0.4))
    remain = 2 * 86400 + 14 * 3600 + 7 * 60 + 33 - int(lt)
    cd = "WEEKLY RABBIT RESETS IN %dD %02dH %02dM %02dS" % (remain // 86400, remain % 86400 // 3600, remain % 3600 // 60, remain % 60)
    text_center(img, cd, 660, 34, fill=(170, 170, 170), alpha=ease((lt - 1.4) / 0.4), fnt=FONT_MONO)
    text_center(img, "PITCH – NOT FOR RELEASE", 960, 28, fill=(210, 60, 60), alpha=ease((lt - 1.4) / 0.4), fnt=FONT_MED)
    return img


def main():
    cmd = [
        "ffmpeg", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
        "-i", MUSIC,
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", OUT,
    ]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for n in range(TOTAL):
        img = frame_at(n)
        if img.size != (W, H):
            img = img.resize((W, H))
        watermark(img)
        p.stdin.write(img.tobytes())
        if n % 300 == 0:
            print("COMPOSE", n, "/", TOTAL, flush=True)
    p.stdin.close()
    p.wait()
    print("OUT", OUT)


if __name__ == "__main__":
    if len(sys.argv) > 4:  # preview single frames: compose.py FR MUSIC OUTDIR n1,n2,...
        for n in map(int, sys.argv[4].split(",")):
            img = frame_at(n)
            watermark(img)
            img.save(os.path.join(OUT, "preview_%04d.png" % n))
    else:
        main()
