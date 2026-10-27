"""Synthesize every Esmiringhoy sound effect from scratch (no samples).

Output: <out>/assets/audio/*.ogg   (mono, 44.1 kHz, Vorbis q5)
Usage: python3 gen_audio.py <out_dir>
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(sys.argv[1], "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(2026)


# ---------------------------------------------------------------- helpers
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def brown(dur):
    b = np.cumsum(noise(dur))
    b = signal.filtfilt(*signal.butter(1, 20 / (SR / 2), "high"), b)
    return b / (np.abs(b).max() + 1e-9)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos"), x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f / (SR / 2), "low", output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f / (SR / 2), "high", output="sos"), x)


def env_adsr(n, a, d, s_level, r):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    s = max(n - a - d - r, 0)
    e = np.concatenate([
        np.linspace(0, 1, a, endpoint=False),
        np.linspace(1, s_level, d, endpoint=False),
        np.full(s, s_level),
        np.linspace(s_level, 0, r),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def saw(f, t):
    return 2 * ((f * t) % 1.0) - 1


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def normalize(x, peak=0.9):
    return x / (np.abs(x).max() + 1e-9) * peak


def loopify(x, xfade=1.0):
    """Crossfade the tail into the head so the clip loops seamlessly."""
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    w = np.linspace(0, 1, n)
    mixed = tail * (1 - w) + head * w
    return np.concatenate([body, mixed])


def write(name, x, peak=0.9, is_loop=False):
    if not is_loop:
        x = fade(x)
    x = normalize(x, peak)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (x * 32767).astype(np.int16))
        path = os.path.join(OUT, name)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name,
                        "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.unlink(tmp.name)
    print("wrote", name, f"{len(x) / SR:.2f}s")


# ---------------------------------------------------------------- sounds
def house_drone():
    dur = 60.0
    t = t_axis(dur)
    # frequencies chosen as whole cycles per 60 s so the tones loop exactly
    tones = [(41.0, 0.5), (55.25, 0.35), (61.75, 0.25), (82.0, 0.12)]
    x = np.zeros_like(t)
    for f, a in tones:
        lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (1 / 20) * t + rng.uniform(0, 6))  # 3 cycles per loop
        x += a * lfo * np.sin(2 * np.pi * f * t)
    air = lp(brown(dur + 2), 400)[: len(t)] * 0.35
    wind = bp(noise(dur + 2), 180, 900)[: len(t)]
    wind *= (0.5 + 0.5 * np.sin(2 * np.pi * (1 / 15) * t)) * 0.08
    x = x + air + wind
    write("amb_house_drone.ogg", loopify(np.concatenate([x, x[: SR]]), 1.0), 0.6, is_loop=True)


def heartbeat(name, bpm, beats):
    period = 60.0 / bpm
    dur = period * beats
    x = np.zeros(int(dur * SR))
    thump_len = int(0.18 * SR)
    tt = np.arange(thump_len) / SR

    def thump(level, f0):
        f = f0 * (1 + 1.2 * np.exp(-tt * 40))  # quick pitch drop
        ph = 2 * np.pi * np.cumsum(f) / SR
        return level * np.sin(ph) * exp_decay(thump_len, 0.045)

    for i in range(beats):
        s = int(i * period * SR)
        lub = thump(1.0, 48)
        dub = thump(0.7, 56)
        x[s:s + thump_len] += lub
        d = s + int(0.22 * period * SR + 0.08 * SR)
        x[d:d + thump_len] += dub[: len(x) - d]
    x = lp(x, 200)
    write(name, x, 0.85, is_loop=True)


def demon_growl():
    dur = 2.6
    t = t_axis(dur)
    f = 46 + 8 * np.sin(2 * np.pi * 3.1 * t) + 6 * rng.standard_normal(len(t)).cumsum() / SR
    ph = 2 * np.pi * np.cumsum(f) / SR
    buzz = 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    rough = brown(dur) * 0.8
    src = buzz * (0.6 + 0.4 * np.abs(rough))
    formants = bp(src, 240, 420) * 1.0 + bp(src, 600, 900) * 0.6 + bp(rough, 90, 300) * 0.8
    e = env_adsr(len(t), 0.35, 0.4, 0.8, 0.9)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 7 * t)
    write("sfx_demon_growl.ogg", np.tanh(formants * e * trem * 3.0))


def whispers_rev():
    dur = 3.2
    x = np.zeros(int(dur * SR))
    pos = 0.05
    while pos < dur - 0.3:
        syl = rng.uniform(0.08, 0.26)
        n = int(syl * SR)
        s = int(pos * SR)
        lo = rng.uniform(1200, 2400)
        burst = bp(noise(syl), lo, lo * rng.uniform(1.8, 2.6))
        burst += 0.4 * bp(noise(syl), 400, 900)  # breathy body
        x[s:s + n] += burst * env_adsr(n, 0.02, 0.05, 0.6, syl * 0.5) * rng.uniform(0.4, 1.0)
        pos += syl + rng.uniform(0.02, 0.18)
    x = x[::-1]  # reversed: swells in, cuts off
    # slight pitch-shimmer by mixing a delayed copy
    d = int(0.013 * SR)
    x = x + 0.5 * np.concatenate([np.zeros(d), x[:-d]])
    write("sfx_whispers_rev.ogg", x, 0.7)


def demon_hiss():
    dur = 0.9
    n = int(dur * SR)
    x = hp(noise(dur), 2800) * env_adsr(n, 0.01, 0.1, 0.55, 0.6)
    x += 0.35 * bp(noise(dur), 900, 1600) * env_adsr(n, 0.02, 0.2, 0.3, 0.5)
    write("sfx_demon_hiss.ogg", x, 0.75)


def scream_sting():
    dur = 2.2
    t = t_axis(dur)
    n = len(t)
    cluster = np.zeros(n)
    for f in (311.0, 329.6, 349.2, 466.2, 493.9):
        glide = f * (1 + 0.08 * t / dur)  # rising, unsettling
        ph = 2 * np.pi * np.cumsum(glide + rng.uniform(-1.5, 1.5)) / SR
        cluster += saw(1, ph / (2 * np.pi))
    cluster = lp(cluster, 3500)
    swell = hp(noise(dur), 1500) * np.linspace(0.2, 1.0, n)
    hit = lp(noise(dur), 120) * exp_decay(n, 0.12) * 3
    e = env_adsr(n, 0.005, 0.15, 0.7, 0.9)
    write("sfx_scream_sting.ogg", np.tanh((cluster * 0.4 + swell * 0.5 + hit) * e * 1.5))


def catch_roar():
    dur = 2.4
    t = t_axis(dur)
    n = len(t)
    layers = np.zeros(n)
    for base, amp in ((38, 1.0), (52, 0.7), (77, 0.4)):
        f = base * (1.3 - 0.4 * t / dur)
        ph = np.cumsum(f) / SR
        layers += amp * saw(1, ph)
    rough = brown(dur)
    roar = bp(layers * (0.5 + 0.5 * np.abs(rough)), 150, 1100) * 1.3
    sub_f = 60 * np.exp(-t * 1.2) + 28
    sub = np.sin(2 * np.pi * np.cumsum(sub_f) / SR) * exp_decay(n, 0.9)
    e = env_adsr(n, 0.04, 0.3, 0.85, 0.8)
    write("sfx_catch_roar.ogg", np.tanh((roar + sub * 0.9) * e * 2.5))


def wood_steps():
    for i in range(1, 5):
        dur = 0.28
        n = int(dur * SR)
        t = t_axis(dur)
        x = np.zeros(n)
        for f in rng.uniform(140, 300, 3):
            x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * exp_decay(n, rng.uniform(0.03, 0.06))
        click = hp(noise(dur), 2000) * exp_decay(n, 0.004) * 0.6
        scuff = bp(noise(dur), 500, 2500) * env_adsr(n, 0.01, 0.05, 0.2, 0.1) * 0.15
        write(f"sfx_step_wood_{i:02d}.ogg", x * 0.8 + click + scuff, 0.7)


def creak(name, dur, f_lo, f_hi, rate_lo, rate_hi):
    n = int(dur * SR)
    t = t_axis(dur)
    # stick-slip impulse train with wandering rate
    rate = rate_lo + (rate_hi - rate_lo) * (0.5 + 0.5 * np.sin(2 * np.pi * t / dur * 1.3 + rng.uniform(0, 3)))
    rate *= 1 + 0.15 * lp(noise(dur), 6) / 0.05
    ph = np.cumsum(np.clip(rate, 5, None)) / SR
    impulses = (np.diff(np.floor(ph), prepend=0) > 0).astype(float)
    centre = np.linspace(f_lo, f_hi, n)
    out = np.zeros(n)
    block = 2048
    for s in range(0, n, block):  # time-varying band-pass, block by block
        c = centre[s]
        seg = impulses[max(0, s - 512):s + block]
        y = bp(seg, c * 0.8, c * 1.25, 2)
        out[s:s + block] = y[-len(out[s:s + block]):]
    out += 0.3 * bp(out, 1500, 3000)
    write(name, out * env_adsr(n, 0.08, 0.2, 0.8, 0.3), 0.75)


def flash_click():
    dur = 0.12
    n = int(dur * SR)
    x = np.zeros(n)
    for off in (0, int(0.035 * SR)):
        m = n - off
        x[off:] += hp(noise(m / SR), 1500)[:m] * exp_decay(m, 0.003)
    write("sfx_flash_click.ogg", x, 0.6)


def battery_low():
    dur = 0.55
    t = t_axis(dur)
    x = np.zeros_like(t)
    for s in (0.0, 0.25):
        m = (t >= s) & (t < s + 0.14)
        tt = t[m] - s
        x[m] += np.sin(2 * np.pi * 1180 * tt) * np.sin(np.pi * tt / 0.14)
    write("sfx_battery_low.ogg", x, 0.45)


def bulb_buzz():
    dur = 4.0
    t = t_axis(dur)
    x = sum(np.sin(2 * np.pi * 60 * k * t) / k for k in (1, 2, 3, 5, 7)) * 0.3  # 4 s = whole cycles
    crackle = np.zeros_like(t)
    for _ in range(25):
        s = rng.integers(0, len(t) - 400)
        crackle[s:s + 400] += hp(noise(400 / SR), 3000) * exp_decay(400, 0.002) * rng.uniform(0.2, 1)
    write("sfx_bulb_buzz.ogg", x + crackle * 0.5, 0.4, is_loop=True)


def candle_light():
    dur = 0.9
    n = int(dur * SR)
    strike = bp(noise(dur), 2000, 7000) * exp_decay(n, 0.05)
    flare = bp(noise(dur), 300, 1800) * env_adsr(n, 0.04, 0.2, 0.4, 0.5)
    write("sfx_candle_light.ogg", strike * 0.8 + flare * 0.6, 0.6)


if __name__ == "__main__":
    house_drone()
    heartbeat("sfx_heartbeat_slow.ogg", 62, 4)
    heartbeat("sfx_heartbeat_fast.ogg", 132, 8)
    demon_growl()
    whispers_rev()
    demon_hiss()
    scream_sting()
    catch_roar()
    wood_steps()
    creak("sfx_creak_door.ogg", 1.6, 600, 950, 25, 70)
    creak("sfx_creak_floor.ogg", 0.9, 280, 420, 18, 45)
    flash_click()
    battery_low()
    bulb_buzz()
    candle_light()
