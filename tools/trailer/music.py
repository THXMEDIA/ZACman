#!/usr/bin/env python3
"""Temp-Musik für den ZAPmaniac-Trailer-Pitch (prozedural, keine fremden Samples).

Erzeugt eine 80-s-Stereo-WAV (44,1 kHz), deren Abschnitte zum Beat-Sheet in
studio/projekte/zapmaniac/trailer-pitch-v1.md passen (120 BPM). Nur für den
internen Pitch; für eine Veröffentlichung braucht es echte Musik.

    python3 tools/trailer/music.py out.wav
"""
import sys
import wave

import numpy as np

SR = 44100
DUR = 80.0
BPM = 120.0
BEAT = 60.0 / BPM
N = int(SR * DUR)
rng = np.random.default_rng(7)

mix = np.zeros((N, 2), dtype=np.float64)


def t_of(n):
    return np.arange(n) / SR


def add(sig, at, gain=1.0, pan=0.0):
    """Mixes a mono or stereo signal in at second `at`."""
    i = int(at * SR)
    if i >= N:
        return
    if sig.ndim == 1:
        l = sig * (1.0 - max(0.0, pan))
        r = sig * (1.0 + min(0.0, pan))
        sig = np.stack([l, r], axis=1)
    n = min(len(sig), N - i)
    mix[i:i + n] += sig[:n] * gain


def env(n, a=0.005, d=0.2):
    t = t_of(n)
    e = np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-t / d)
    return e


def lowpass(x, cutoff):
    # one-pole low-pass, good enough for a temp track
    a = np.broadcast_to(np.exp(-2.0 * np.pi * np.asarray(cutoff, dtype=float) / SR), x.shape)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff):
    # FFT brick-wall-ish low-pass for long noise beds
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def saw(freq, n, detune=0.0):
    t = t_of(n)
    out = np.zeros(n)
    for d in (-detune, 0.0, detune):
        ph = (freq * (1 + d)) * t
        out += 2.0 * (ph - np.floor(ph + 0.5))
    return out / 3.0


def square(freq, n):
    t = t_of(n)
    return np.sign(np.sin(2 * np.pi * freq * t))


def kick():
    n = int(0.35 * SR)
    t = t_of(n)
    f = 50 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9) * 1.0


def hat():
    n = int(0.06 * SR)
    x = rng.standard_normal(n)
    x = x - lowpass(x, 6000)
    return x * env(n, 0.001, 0.015) * 0.35


def snare():
    n = int(0.25 * SR)
    t = t_of(n)
    x = rng.standard_normal(n) * np.exp(-t * 18) * 0.5
    x += np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.5
    return x


def bleep(freq, dur=0.07):
    n = int(dur * SR)
    return square(freq, n) * env(n, 0.002, dur / 3) * 0.18


def hit():
    n = int(2.2 * SR)
    t = t_of(n)
    boom = np.sin(2 * np.pi * (38 + 60 * np.exp(-t * 6)) * t) * np.exp(-t * 2.2)
    noise = lowpass_fast(rng.standard_normal(n), 1800) * np.exp(-t * 4) * 0.6
    return (boom + noise) * 0.9


def riser(dur):
    n = int(dur * SR)
    t = t_of(n)
    x = rng.standard_normal(n)
    x = x - lowpass(x, 300 + 3000 * (t / dur))
    return x * (t / dur) ** 2 * 0.35


def heartbeat():
    n = int(0.5 * SR)
    t = t_of(n)
    a = np.sin(2 * np.pi * 48 * t) * np.exp(-t * 18)
    b = np.sin(2 * np.pi * 44 * t) * np.exp(-np.maximum(0, t - 0.18) * 16) * (t > 0.18)
    return (a + 0.8 * b) * 0.9


def tick():
    n = int(0.03 * SR)
    t = t_of(n)
    return np.sin(2 * np.pi * 3200 * t) * np.exp(-t * 200) * 0.25


def zap():
    n = int(0.6 * SR)
    t = t_of(n)
    f = 1800 * np.exp(-t * 7) + 90
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sign(np.sin(ph)) * np.exp(-t * 5) * 0.3


def pad(freqs, dur, gain=0.12):
    n = int(dur * SR)
    t = t_of(n)
    x = np.zeros(n)
    for f in freqs:
        x += saw(f, n, 0.004)
    x = lowpass_fast(x, 900)
    a = np.minimum(1.0, t / 1.2) * np.minimum(1.0, (dur - t) / 1.2)
    return x * a * gain


A2, C3, D3, E3, F2, G2 = 110.0, 130.81, 146.83, 164.81, 87.31, 98.0
BASS_ROOTS = [A2, A2, F2, G2]


def beat_block(start, end, arp=True, wobble=False):
    t = start
    k = 0
    while t < end - 1e-6:
        bar = int((t - start) / (4 * BEAT)) % 4
        root = BASS_ROOTS[bar]
        add(kick(), t, 0.9)
        if k % 2 == 1:
            add(snare(), t, 0.55)
        add(hat(), t + BEAT / 2, 0.8, 0.3)
        # bass: eighth notes
        for e in range(2):
            n = int(BEAT / 2 * SR)
            f = root / 2 * (1.0 if e == 0 else 2.0)
            if wobble:
                f *= 1.0 + 0.03 * np.sin(2 * np.pi * 0.7 * (t + e * BEAT / 2))
            b = lowpass(saw(f, n, 0.006), 500) * env(n, 0.004, 0.18)
            add(b, t + e * BEAT / 2, 0.55)
        if arp:
            for e, mul in enumerate((2, 3, 4, 3)):
                add(bleep(root * mul, 0.09), t + e * BEAT / 4, 0.6, -0.3 + 0.2 * e)
        t += BEAT
        k += 1


# 0–5 s: drone + typing
n = int(5.2 * SR)
drone = lowpass_fast(saw(55.0, n, 0.01), 300) * np.minimum(1, t_of(n) / 1.5) * 0.35
add(drone, 0.0)
msg = "FOLLOW THE WHITE RABBIT."
for i, ch in enumerate(msg):
    if ch != " ":
        add(bleep(880 + 40 * (i % 5), 0.04), 0.4 + i * (2.2 / len(msg)), 0.7)
add(hit(), 3.2, 0.7)

# 5–12 s: sprint beat
beat_block(5.0, 12.0)
for i in range(28):
    add(bleep(1320, 0.03), 5.0 + i * 0.25 + 0.125, 0.35, 0.4)

# 12–16 s: music gone, heartbeat + clock
for i in range(5):
    add(heartbeat(), 12.1 + i * 0.8, 0.9)
for i in range(8):
    add(tick(), 12.0 + i * 0.5, 0.8)

# 16 s: title card hit, riser into the conditions
add(hit(), 16.0, 1.0)
add(riser(3.0), 16.0, 0.8)

# 19–36 s: conditions montage, F&L detuned
beat_block(19.0, 24.0)
beat_block(24.0, 28.0, wobble=True)
beat_block(28.0, 36.0)
for at in (19.0, 24.0, 28.0, 29.5):
    add(hit(), at, 0.8)
add(riser(2.0), 36.0, 0.9)

# 36–41 s: finish
beat_block(36.0, 38.0)
add(hit(), 38.0, 1.1)
add(pad([A2 * 2, C3 * 2, E3 * 2], 3.2, 0.10), 38.0)

# 41–46 s: leaderboard
beat_block(41.0, 46.0)
add(riser(1.5), 42.0, 0.6)
for k, f in enumerate((1320, 1760, 2640)):
    add(bleep(f, 0.12), 43.5 + k * 0.09, 0.8)

# 46–70 s: relax – rain + pad
n = int(24.5 * SR)
rain = lowpass_fast(rng.standard_normal(n), 2500)
fade = np.minimum(1, t_of(n) / 2.0) * np.minimum(1, (24.5 - t_of(n)) / 1.0)
add(np.stack([rain * fade * 0.10, np.roll(rain, 997) * fade * 0.10], axis=1), 46.0)
chords = [[A2, C3, E3], [F2 * 2, A2, C3], [C3, E3, G2 * 2], [G2, D3 / 2 * 2, G2 * 2]]
for i in range(5):
    add(pad(chords[i % 4], 4.4, 0.09), 46.5 + i * 4.0)
add(pad([A2, E3], 6.0, 0.06), 66.0)

# 70–73.5 s: back to the run
beat_block(70.0, 73.5)
add(hit(), 73.5, 1.2)
add(zap(), 78.5, 1.0)

# master: soft clip + normalise
mix = np.tanh(mix * 0.9)
mix /= max(1e-6, np.max(np.abs(mix))) / 0.89
fo = np.minimum(1, (DUR - t_of(N)) / 0.8)[:, None]
mix *= fo

out = sys.argv[1] if len(sys.argv) > 1 else "trailer_music.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
print("MUSIC", out)
