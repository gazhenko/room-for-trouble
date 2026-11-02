"""Room for Trouble sound effects, guest/staff vocalisations and voice syllables.

Every cue is a small function returning a mono float array; `CUES` maps the
cue id to (bus, function, loop, target_peak_dbfs).  Friendly pitches come
from F major (F5 = MIDI 77) so cues sit happily over any chapter music.
"""

from __future__ import annotations

import numpy as np

import instruments as I
from dsp import (SR, TAU, H_bp, H_hp, H_lp, H_peak, env_points, env_smooth, filt, midi_hz,
                 modal, ns, phase_of, ramp_in, release_env, rng, rms, stft_shape, taxis)


# ======================================================================= helpers

def place(total, items):
    """items: iterable of (t_seconds, signal, gain)."""
    n = ns(total)
    out = np.zeros(n)
    for t, s, g in items:
        if s is None or g == 0:
            continue
        st = max(0, ns(t))
        m = min(len(s), n - st)
        if m > 0:
            out[st:st + m] += np.asarray(s[:m]) * g
    return out


def env(points, n):
    return env_smooth(points, n)


def tone(dur, f_pts, amp_pts, harm=((1, 1.0),), vib=None, seed="tone", f_is_curve=False):
    n = ns(dur)
    t = taxis(n)
    f = f_pts if f_is_curve else env(f_pts, n)
    if vib:
        rate, cents = vib[0], vib[1]
        onset = vib[2] if len(vib) > 2 else 0.0
        depth = cents * np.clip((t - onset) / 0.15, 0, 1)
        f = f * 2.0 ** (depth * np.sin(TAU * rate * t) / 1200.0)
    ph = phase_of(f)
    r = rng("tone", seed)
    out = np.zeros(n)
    for k, a in harm:
        if k * np.max(f) < 0.45 * SR:
            out += a * np.sin(k * ph + r.uniform(0, TAU))
    return out * env(amp_pts, n)


def bp_noise(dur, fc, q, amp_pts, seed, lo=None):
    n = ns(dur)
    r = rng("bpn", seed)
    x = r.standard_normal(n)

    def H(f):
        h = H_bp(f, fc, q)
        if lo:
            h = h * H_hp(f, lo)
        return h

    y = filt(x, H)[:n]
    y /= np.max(np.abs(y)) + 1e-9
    return y * env(amp_pts, n)


def lp_noise(dur, fc, amp_pts, seed, hp=None):
    n = ns(dur)
    r = rng("lpn", seed)
    x = r.standard_normal(n)
    y = filt(x, lambda f: H_lp(f, fc) * (H_hp(f, hp) if hp else 1.0))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    return y * env(amp_pts, n)


def sweep(dur, f_pts, q, amp_pts, seed, floor=0.0, lp=None):
    """Noise through a moving band-pass; f_pts are (time, Hz) breakpoints."""
    n = ns(dur)
    r = rng("sweep", seed)
    x = r.standard_normal(n)
    ts = np.array([p[0] for p in f_pts])
    fs = np.log(np.array([p[1] for p in f_pts]))

    def g(t, f):
        fc = np.exp(np.interp(t, ts, fs))
        s = f / fc
        bp = (s / q) / np.sqrt((1 - s * s) ** 2 + (s / q) ** 2 + 1e-12)
        return bp + floor

    y = stft_shape(x, g)
    if lp:
        y = filt(y, lambda f: H_lp(f, lp))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    return y * env(amp_pts, n)


def click(fc=3000.0, q=1.2, dur=0.006, seed="click", tau=0.0008):
    n = ns(dur)
    r = rng("click", seed, fc)
    x = r.standard_normal(n) * np.exp(-taxis(n) / tau)
    y = filt(x, lambda f: H_bp(f, fc, q))[:n]
    return y / (np.max(np.abs(y)) + 1e-9)


def thud(f0=120.0, dur=0.18, seed="thud", noise_amt=0.35, lp=700.0, drop=0.35, tau=0.05):
    n = ns(dur)
    t = taxis(n)
    f = f0 * (1.0 + drop * np.exp(-t / 0.02))
    body = np.sin(phase_of(f)) * np.exp(-t / tau)
    r = rng("thud", seed)
    nz = r.standard_normal(n) * np.exp(-t / (tau * 0.4))
    nz = filt(nz, lambda fr: H_lp(fr, lp))[:n]
    nz /= np.max(np.abs(nz)) + 1e-9
    y = (body + noise_amt * nz) * ramp_in(n, ns(0.0015))
    return y / (np.max(np.abs(y)) + 1e-9)


def bubble(f0=500.0, dur=0.07, rise=0.9, seed="bubble", tau=None):
    n = ns(dur)
    t = taxis(n)
    tau = tau or dur / 3.0
    f = f0 * (1.0 + rise * t / dur) ** 1.2
    y = np.sin(phase_of(f)) * np.exp(-t / tau) * ramp_in(n, ns(0.002))
    return y


def bubbles(dur, count, f_lo, f_hi, seed, rise=0.9, size=(0.04, 0.09), shape=None):
    r = rng("bubbles", seed)
    items = []
    for i in range(count):
        if shape == "rising":
            t = dur * (i / max(count, 1)) * 0.85
            f = f_lo * (f_hi / f_lo) ** (i / max(count - 1, 1))
        else:
            t = r.uniform(0, dur * 0.85)
            f = np.exp(r.uniform(np.log(f_lo), np.log(f_hi)))
        d = r.uniform(*size)
        items.append((t, bubble(f, d, rise * r.uniform(0.7, 1.3), seed=f"{seed}{i}"), r.uniform(0.5, 1.0)))
    return place(dur, items)


def flap(dur=0.25, seed="flap", rate=24.0, fc=900.0, snap=0.0):
    """Cloth flap: band-limited noise with a fluttering amplitude."""
    n = ns(dur)
    t = taxis(n)
    r = rng("flap", seed)
    x = r.standard_normal(n)
    x = filt(x, lambda f: H_bp(f, fc, 0.5) * H_hp(f, 150.0))[:n]
    x /= np.max(np.abs(x)) + 1e-9
    flutter = 0.55 + 0.45 * np.abs(np.sin(np.pi * rate * t + r.uniform(0, np.pi)))
    e = env([(0, 0), (dur * 0.12, 1.0), (dur * 0.45, 0.6), (dur, 0.0)], n)
    y = x * flutter * e
    if snap > 0:
        sn = ns(0.02)
        s = r.standard_normal(sn) * np.exp(-taxis(sn) / 0.004)
        s = filt(s, lambda f: H_hp(f, 900.0) * H_lp(f, 7000.0))[:sn]
        s /= np.max(np.abs(s)) + 1e-9
        k = ns(dur * 0.12)
        y[k:k + sn] += s[: max(0, min(sn, n - k))] * snap
    return y


def rustle(dur, seed, density=180.0, lo=1500.0, hi=7000.0, amp_pts=None, grain=0.0025):
    """Paper / leaf crinkle: a bed of tiny filtered clicks."""
    n = ns(dur)
    r = rng("rustle", seed)
    count = max(1, int(density * dur))
    imp = np.zeros(n)
    pos = r.integers(0, n, count)
    imp[pos] += r.uniform(0.2, 1.0, count) * r.choice([-1, 1], count)
    g = ns(grain)
    kern = r.standard_normal(g) * np.exp(-np.arange(g) / (g / 4))
    y = np.convolve(imp, kern)[:n]
    bed = r.standard_normal(n) * 0.12
    y = filt(y + bed, lambda f: H_hp(f, lo) * H_lp(f, hi))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    if amp_pts:
        y *= env(amp_pts, n)
    return y


def whistle(dur, f_pts, amp_pts, seed, breath=0.25, vib=(5.5, 15.0, 0.15), harm2=0.06):
    n = ns(dur)
    t = taxis(n)
    f = env(f_pts, n)
    if vib:
        f = f * 2.0 ** (vib[1] * np.clip((t - vib[2]) / 0.2, 0, 1) * np.sin(TAU * vib[0] * t) / 1200.0)
    ph = phase_of(f)
    y = np.sin(ph) + harm2 * np.sin(2 * ph)
    r = rng("whistle", seed)
    fm = float(np.median(f))
    b = r.standard_normal(n)
    b = filt(b, lambda fr: H_bp(fr, fm, 2.0) + 0.3 * H_bp(fr, fm * 2.2, 1.0))[:n]
    b /= np.max(np.abs(b)) + 1e-9
    a = env(amp_pts, n)
    return (y + breath * b) * a


def boing(f0=330.0, dur=0.55, seed="boing", wobble=0.22, rate=13.0):
    n = ns(dur)
    t = taxis(n)
    f = f0 * (1.0 + wobble * np.exp(-t / 0.12) * np.sin(TAU * rate * t))
    ph = phase_of(f)
    y = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    return y * np.exp(-t / (dur * 0.35)) * ramp_in(n, ns(0.002))


def shimmer(dur, seed="shimmer"):
    """Soft, airy high sparkle bed (used by stingers too)."""
    n = ns(dur)
    r = rng("shimmer", seed)
    x = r.standard_normal(n)
    grains = (r.uniform(0, 1, n) > 0.997).astype(float) * r.uniform(0.5, 1.0, n)
    g = np.convolve(grains, np.exp(-np.arange(ns(0.01)) / ns(0.002)))[:n]
    y = filt(x * (0.25 + g), lambda f: H_hp(f, 6500.0) * H_lp(f, 13000.0))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    return y * env([(0, 0), (dur * 0.3, 1.0), (dur, 0.0)], n)


def sparkle(dur, seed, count=6, notes=(89, 93, 96, 101, 98, 91), inst="celesta", vel=0.5, spread=None):
    r = rng("sparkle", seed)
    fn = {"celesta": I.celesta, "glock": I.glock, "glass": I.glass}[inst]
    items = []
    span = spread if spread is not None else dur * 0.6
    for i in range(count):
        t = i * span / max(count, 1) + r.uniform(0, 0.02)
        m = notes[i % len(notes)]
        items.append((t, fn(m, vel * r.uniform(0.6, 1.0), var=i, dur=0.6), 1.0 - 0.07 * i))
    return place(dur, items)


def mallets(seq, inst="marimba", total=None):
    """seq: list of (t, midi, vel[, dur])."""
    fn = {"marimba": I.marimba, "celesta": I.celesta, "glock": I.glock, "glass": I.glass}[inst]
    items = []
    end = 0.0
    for i, s in enumerate(seq):
        t, m, v = s[:3]
        d = s[3] if len(s) > 3 else 1.5
        y = fn(m, v, var=i, dur=d)
        items.append((t, y, 1.0))
        end = max(end, t + len(y) / SR)
    return place(total or end, items)


def piano(seq, total=None, pedal=0.2):
    items = []
    end = 0.0
    for i, (t, m, v, d) in enumerate(seq):
        y = I.felt_piano(m, d, v, i, pedal)
        items.append((t, y, 1.0))
        end = max(end, t + len(y) / SR)
    return place(total or end, items)


def small_bell(dur, strikes, f0=2350.0, seed="smallbell"):
    """Little shop-door bell swinging: a few quick strikes."""
    r = rng("smallbell", seed)
    items = []
    for i, (t, v) in enumerate(strikes):
        n = ns(dur - t)
        f = f0 * (1.0 + r.uniform(-0.004, 0.004))
        modes = [(f, 1.0, 0.5), (f * 2.41, 0.35, 0.22), (f * 4.07, 0.15, 0.1), (f * 1.003, 0.6, 0.45)]
        items.append((t, modal(n, modes, r) * v, 1.0))
    return place(dur, items)


# ------------------------------------------------------------------ voice

VOW = {
    "a": ((760, 1220, 2550, 3400), 0.0), "e": ((480, 1880, 2550, 3400), 0.0),
    "i": ((300, 2250, 2950, 3500), 0.0), "o": ((480, 830, 2450, 3300), 0.0),
    "u": ((330, 760, 2300, 3200), 0.0), "m": ((250, 1050, 2300, 3200), 1.0),
    "n": ((250, 1500, 2500, 3300), 0.85), "l": ((360, 1100, 2700, 3400), 0.25),
    "w": ((300, 650, 2300, 3200), 0.15), "y": ((280, 2150, 2900, 3500), 0.1),
    "b": ((240, 900, 2300, 3200), 0.75), "d": ((260, 1700, 2600, 3300), 0.75),
    "r": ((420, 1150, 1650, 3200), 0.1), "ae": ((660, 1700, 2450, 3400), 0.0),
    "uh": ((560, 1100, 2450, 3300), 0.0),
}
BWS = (90.0, 110.0, 160.0, 230.0)


def _formant_tracks(t, vowel_pts, scale):
    ts = [p[0] for p in vowel_pts]
    F = [np.interp(t, ts, [VOW[k][0][i] for _, k in vowel_pts]) * scale for i in range(4)]
    nas = np.interp(t, ts, [VOW[k][1] for _, k in vowel_pts])
    return F, nas


def voice(dur, f0_pts, vowel_pts, amp_pts, seed, scale=1.0, breath=0.04, tilt=1.15,
          vib=None, jitter=0.005, aspir_pts=None, bright=1.0):
    """Formant-synthesised voiced sound (additive harmonics through 4 formants)."""
    n = ns(dur)
    t = taxis(n)
    r = rng("voice", seed)
    f0 = env(f0_pts, n)
    if vib:
        rate, cents, onset = vib
        f0 = f0 * 2.0 ** (cents * np.clip((t - onset) / 0.2, 0, 1) * np.sin(TAU * rate * t) / 1200.0)
    if jitter:
        j = filt(r.standard_normal(n), lambda f: H_lp(f, 7.0))[:n]
        j /= np.std(j) + 1e-12
        f0 = f0 * (1.0 + jitter * j)
    F, nas = _formant_tracks(t, vowel_pts, scale)
    ph = phase_of(f0)
    kmax = int(min(60, 7500.0 / max(70.0, float(np.min(f0)))))
    out = np.zeros(n)
    bws = [b * scale ** 0.5 for b in BWS]
    for k in range(1, kmax + 1):
        fk = k * f0
        A = np.full(n, 1.0 / k ** tilt)
        for i in range(4):
            Fi = F[i]
            A *= Fi * Fi / np.sqrt((Fi * Fi - fk * fk) ** 2 + (bws[i] * fk) ** 2)
        A *= (1.0 / (1.0 + (fk / 450.0) ** 2)) ** nas
        A *= 1.0 / (1.0 + (fk / (4500.0 * bright)) ** 2)
        A[fk > 0.45 * SR] = 0.0
        out += A * np.sin(k * ph + r.uniform(0, 0.5))
    out /= np.max(np.abs(out)) + 1e-9
    a = env(amp_pts, n)
    out *= a
    if breath > 0:
        x = r.standard_normal(n)
        tsv = [p[0] for p in vowel_pts]

        def g(tf, f):
            G = np.ones(np.broadcast_shapes(tf.shape, f.shape))
            for i in range(4):
                Fi = np.interp(tf, tsv, [VOW[k][0][i] for _, k in vowel_pts]) * scale
                G = G * Fi * Fi / np.sqrt((Fi * Fi - f * f) ** 2 + (bws[i] * 2.2 * f) ** 2)
            return G * (f / (f + 400.0)) / (1.0 + (f / 7000.0) ** 2)

        b = stft_shape(x, g)
        b /= np.max(np.abs(b)) + 1e-9
        a2 = env(aspir_pts, n) if aspir_pts else a
        out += breath * b * a2
    return out


def breath_noise(dur, vowel_pts, amp_pts, seed, scale=1.0, tilt_hp=500.0):
    """Unvoiced breath (inhale/exhale/'shh') through formants."""
    n = ns(dur)
    r = rng("breath", seed)
    x = r.standard_normal(n)
    tsv = [p[0] for p in vowel_pts]

    def g(tf, f):
        G = np.ones(np.broadcast_shapes(tf.shape, f.shape))
        for i in range(4):
            Fi = np.interp(tf, tsv, [VOW[k][0][i] for _, k in vowel_pts]) * scale
            G = G * Fi * Fi / np.sqrt((Fi * Fi - f * f) ** 2 + (BWS[i] * 3.0 * f) ** 2)
        return G * (f / (f + tilt_hp)) / (1.0 + (f / 8000.0) ** 2)

    y = stft_shape(x, g)
    y /= np.max(np.abs(y)) + 1e-9
    return y * env(amp_pts, n)


def syllable(cons, vow, dur, f0=220.0, seed="syl", scale=1.0, f_end=None, breath=0.03):
    """Soft consonant + vowel at a (nearly) fixed pitch."""
    c_len = {"b": 0.022, "d": 0.02, "m": 0.035, "n": 0.035, "l": 0.03, "w": 0.04, "y": 0.035,
             "h": 0.03, "p": 0.02, "": 0.0}[cons]
    trans = 0.035
    vowel_pts = []
    if cons in ("b", "p"):
        vowel_pts = [(0.0, "b"), (c_len, "b"), (c_len + trans, vow), (dur, vow)]
    elif cons == "d":
        vowel_pts = [(0.0, "d"), (c_len, "d"), (c_len + trans, vow), (dur, vow)]
    elif cons in ("m", "n", "l", "w", "y"):
        vowel_pts = [(0.0, cons), (c_len, cons), (c_len + trans, vow), (dur, vow)]
    else:
        vowel_pts = [(0.0, vow), (dur, vow)]
    fe = f_end if f_end is not None else f0 * 0.975
    f_pts = [(0.0, f0 * 1.01), (dur * 0.4, f0), (dur, fe)]
    if cons in ("b", "d", "p"):
        amp = [(0, 0.0), (0.004, 0.12), (c_len, 0.15), (c_len + 0.012, 1.0), (dur * 0.7, 0.85), (dur, 0.0)]
    elif cons == "h":
        amp = [(0, 0.0), (c_len, 0.0), (c_len + 0.02, 1.0), (dur * 0.7, 0.85), (dur, 0.0)]
    elif cons:
        amp = [(0, 0.0), (0.012, 0.45), (c_len, 0.55), (c_len + trans, 1.0), (dur * 0.7, 0.85), (dur, 0.0)]
    else:
        amp = [(0, 0.0), (0.015, 1.0), (dur * 0.7, 0.85), (dur, 0.0)]
    asp = None
    br = breath
    if cons == "h":
        asp = [(0, 0.0), (0.006, 1.0), (c_len, 0.8), (c_len + 0.02, 0.15), (dur, 0.0)]
        br = 0.35
    y = voice(dur, f_pts, vowel_pts, amp, seed, scale=scale, breath=br, aspir_pts=asp, jitter=0.003)
    if cons in ("b", "d", "p"):
        k = ns(c_len)
        burst = click(1400.0 if cons != "d" else 3200.0, 0.8, 0.008, seed + "burst", tau=0.0012)
        g = 0.18 if cons != "p" else 0.3
        y[k:k + len(burst)] += burst[: len(y) - k] * g
    return y


# ======================================================================= cue designs
# Each returns mono float; levels are normalised later by the master stage.

# ---------------------------------------------------------------- input / work

def c_pickup():
    return place(0.2, [(0.0, I.woodblock(1500.0, 0.45, 0, 0.0), 0.35),
                       (0.005, tone(0.11, [(0, 560), (0.08, 860), (0.11, 900)],
                                    [(0, 0), (0.008, 1), (0.05, 0.6), (0.11, 0)],
                                    ((1, 1.0), (2, 0.15)), seed="pickup"), 0.8)])


def c_place():
    return place(0.22, [(0.0, thud(170.0, 0.14, "place", 0.3, 900.0, 0.25, 0.035), 0.8),
                        (0.003, I.woodblock(880.0, 0.4, 1, 0.6), 0.3)])


def c_handoff():
    return place(0.45, [(0.0, sweep(0.18, [(0, 900), (0.18, 2400)], 1.2,
                                    [(0, 0), (0.08, 1), (0.18, 0)], "handoff"), 0.25),
                        (0.03, I.marimba(84, 0.55, 0, 0.3), 0.7),
                        (0.12, I.marimba(89, 0.62, 1, 0.3), 0.75)])


def c_target_valid():
    return place(0.3, [(0.0, I.marimba(84, 0.45, 0, 0.25), 0.6), (0.0, I.celesta(89, 0.3, 0, 0.2), 0.25),
                       (0.0, click(3800.0, 1.5, 0.004, "tv"), 0.05)])


def c_target_invalid():
    # soft low "boop": rounded sine with a gentle downward lean, no edge
    b = tone(0.24, [(0, 222.0), (0.05, 214.0), (0.24, 198.0)],
             [(0, 0), (0.012, 1.0), (0.09, 0.65), (0.24, 0.0)], ((1, 1.0), (2, 0.12), (3, 0.03)),
             seed="invalid")
    return place(0.26, [(0.0, b, 1.0), (0.0, thud(110.0, 0.08, "invalid_thump", 0.2, 400.0, 0.1, 0.02), 0.15)])


def c_work_start():
    return place(0.36, [(0.0, sweep(0.28, [(0, 700), (0.28, 2600)], 1.0,
                                    [(0, 0), (0.2, 0.8), (0.28, 0)], "wstart"), 0.4),
                        (0.2, I.marimba(81, 0.5, 2, 0.25), 0.55),
                        (0.0, I.woodblock(1300.0, 0.4, 2, 0.2), 0.2)])


def c_work_loop():
    """1.5 s seamless loop: four soft scrub strokes plus a quiet fizz."""
    L = ns(1.5)
    r = rng("work_loop")
    t = np.arange(L) / SR
    x = r.standard_normal(L)
    x = filt(x, lambda f: H_bp(f, 1900.0, 0.5) * H_hp(f, 450.0), circular=True)
    x /= np.max(np.abs(x)) + 1e-9
    strokes = 4
    ph = (t / 1.5) * strokes
    stroke = 0.35 + 0.65 * np.sin(np.pi * (ph % 1.0)) ** 2
    fizz = np.zeros(L)
    for i in range(40):
        p = int(r.integers(0, L))
        b = bubble(np.exp(r.uniform(np.log(1800), np.log(4200))), r.uniform(0.006, 0.014), 1.2,
                   seed=f"wl{i}")
        idx = (p + np.arange(len(b))) % L
        np.add.at(fizz, idx, b * r.uniform(0.2, 0.6))
    y = x * stroke * 0.8 + fizz * 0.35
    y = filt(y, lambda f: H_hp(f, 120.0) * H_lp(f, 7000.0), circular=True)
    return y


def c_work_finish():
    return place(1.0, [(0.0, I.glock(84, 0.75, 0, 1.0), 0.6), (0.06, I.celesta(89, 0.6, 1, 0.9), 0.45),
                       (0.0, click(3800.0, 1.2, 0.004, "wf"), 0.05),
                       (0.1, shimmer(0.6, "wfin"), 0.06)])


def c_mop():
    sw = sweep(0.62, [(0, 500), (0.25, 1600), (0.62, 800)], 0.9,
               [(0, 0), (0.06, 0.8), (0.3, 1.0), (0.62, 0)], "mop")
    slosh = lp_noise(0.62, 500.0, [(0, 0), (0.1, 1.0), (0.4, 0.5), (0.62, 0)], "mop_slosh", hp=90.0)
    return place(0.7, [(0.0, sw, 0.6), (0.0, slosh, 0.35),
                       (0.08, bubbles(0.5, 7, 500.0, 1300.0, "mopb", rise=0.6), 0.25)])


def c_linen_fold():
    return place(0.55, [(0.0, flap(0.22, "fold1", 26.0, 850.0), 0.85), (0.24, flap(0.26, "fold2", 22.0, 700.0), 1.0),
                        (0.42, thud(140.0, 0.1, "foldthud", 0.5, 500.0, 0.1, 0.03), 0.2)])


def c_curtain_swish():
    sw = sweep(0.7, [(0, 900), (0.4, 2800), (0.7, 1800)], 1.0, [(0, 0), (0.12, 1.0), (0.45, 0.7), (0.7, 0)],
               "curtain")
    r = rng("rings")
    rings = place(0.7, [(0.05 + 0.07 * i + r.uniform(0, 0.02),
                         modal(ns(0.08), [(3300.0 + r.uniform(-200, 200), 1.0, 0.02),
                                          (5100.0, 0.4, 0.012)], r), r.uniform(0.3, 0.6))
                        for i in range(6)])
    return place(0.75, [(0.0, sw, 0.6), (0.0, rings, 0.22)])


def c_watering():
    stream = sweep(1.1, [(0, 1600), (0.5, 2200), (1.1, 1700)], 0.7,
                   [(0, 0), (0.08, 0.8), (0.85, 0.7), (1.0, 0.0), (1.1, 0)], "pour")
    r = rng("pour_am")
    n = len(stream)
    am = filt(r.standard_normal(n), lambda f: H_lp(f, 25.0))[:n]
    am = 0.7 + 0.3 * am / (np.max(np.abs(am)) + 1e-9)
    drips = place(0.4, [(0.0, bubble(900.0, 0.05, 1.0, "drip1"), 0.6), (0.18, bubble(1100.0, 0.04, 1.0, "drip2"), 0.4)])
    return place(1.4, [(0.0, stream * am, 0.45), (0.05, bubbles(0.95, 26, 450.0, 1600.0, "pourb", 0.8), 0.35),
                       (1.0, drips, 0.5)])


def c_fan():
    sw = sweep(0.85, [(0, 2600), (0.4, 1400), (0.85, 800)], 0.6, [(0, 0), (0.15, 1.0), (0.85, 0)], "fan",
               floor=0.05)
    t = taxis(len(sw))
    blade = 0.75 + 0.25 * np.sin(TAU * 17.0 * t) ** 2
    return place(0.9, [(0.0, sw * blade, 0.8),
                       (0.0, lp_noise(0.85, 350.0, [(0, 0), (0.2, 1), (0.85, 0)], "fanlow", 60.0), 0.25)])


def _foot(f, seed, bright):
    n = ns(0.13)
    r = rng("foot", seed)
    body = modal(n, [(f, 1.0, 0.028), (f * 2.31, 0.35, 0.016), (f * 3.9, 0.12 * bright, 0.008)], r,
                 attack=0.0015)
    c = click(1800.0 + 900.0 * bright, 0.9, 0.006, seed + "c")
    return place(0.14, [(0.0, body, 1.0), (0.0, c, 0.12 * bright)])


def c_footstep_1():
    return _foot(205.0, "f1", 0.8)


def c_footstep_2():
    return _foot(232.0, "f2", 1.0)


def c_footstep_3():
    return _foot(192.0, "f3", 0.7)


def c_footstep_4():
    return _foot(248.0, "f4", 1.1)


def c_quick_step():
    return place(0.28, [(0.0, sweep(0.24, [(0, 800), (0.24, 2800)], 1.1, [(0, 0), (0.06, 1.0), (0.24, 0)],
                                    "qstep"), 0.7),
                        (0.16, _foot(240.0, "qs", 0.9), 0.4)])


def c_wet_squeak():
    return place(0.34, [(0.0, I.squeak(1450.0, 0.17, 0.7, 0, 3.0), 0.6),
                        (0.12, bubbles(0.18, 4, 600.0, 1100.0, "wsq", 0.7), 0.35),
                        (0.0, _foot(220.0, "wsqf", 0.6), 0.35)])


# ---------------------------------------------------------------- hotel

def c_arrival():
    bell = small_bell(1.3, [(0.0, 1.0), (0.11, 0.65), (0.25, 0.4)], 2350.0, "arrive")
    r = rng("wheels")
    n = ns(0.6)
    t = taxis(n)
    rumble = filt(r.standard_normal(n), lambda f: H_lp(f, 420.0) * H_hp(f, 70.0))[:n]
    rumble /= np.max(np.abs(rumble)) + 1e-9
    clack = 0.6 + 0.4 * (np.sin(TAU * 11.0 * t) > 0.6)
    wheels = rumble * clack * env([(0, 0), (0.08, 1.0), (0.5, 0.8), (0.6, 0)], n)
    return place(1.5, [(0.0, bell, 0.55), (0.35, wheels, 0.35),
                       (0.92, I.squeak(1250.0, 0.16, 0.5, 1, 2.0), 0.18),
                       (0.95, thud(130.0, 0.15, "case_down", 0.4, 600.0, 0.2, 0.05), 0.3)])


def c_chime():
    return place(1.3, [(0.0, I.glock(84, 0.7, 0, 1.2), 0.55), (0.32, I.glock(81, 0.65, 1, 1.0), 0.55),
                       (0.0, I.felt_piano(72, 0.5, 0.45, 0, 0.3), 0.3), (0.32, I.felt_piano(69, 0.7, 0.45, 1, 0.3), 0.3)])


def c_request_appear():
    return place(0.75, [(0.0, I.celesta(84, 0.62, 0, 0.6), 0.6), (0.13, I.celesta(89, 0.66, 1, 0.6), 0.6),
                        (0.0, I.marimba(72, 0.45, 0, 0.4), 0.3), (0.13, I.marimba(77, 0.45, 1, 0.4), 0.3)])


def c_request_done():
    return place(0.95, [(0.0, mallets([(0.0, 81, 0.55), (0.07, 84, 0.6), (0.14, 89, 0.7)], "marimba"), 0.5),
                        (0.14, I.glock(93, 0.6, 0, 0.8), 0.35), (0.2, shimmer(0.5, "rqdone"), 0.05)])


def c_request_late():
    # gentle nudge: the same soft note twice, the second leaning up a step ("still waiting?")
    return place(0.7, [(0.0, I.marimba(84, 0.45, 0, 0.35), 0.55), (0.0, I.celesta(84, 0.35, 0, 0.3), 0.25),
                       (0.2, I.marimba(86, 0.42, 1, 0.4), 0.5), (0.2, I.celesta(86, 0.32, 1, 0.35), 0.22)])


def c_goodbye():
    wave = sweep(0.32, [(0, 1400), (0.32, 2600)], 1.0, [(0, 0), (0.12, 1.0), (0.32, 0)], "wave")
    door = place(0.4, [(0.0, thud(105.0, 0.25, "door", 0.6, 450.0, 0.15, 0.07), 1.0),
                       (0.0, click(2200.0, 2.0, 0.01, "latch", 0.002), 0.25)])
    bell = small_bell(0.9, [(0.0, 0.6), (0.12, 0.35)], 2350.0, "bye")
    return place(1.5, [(0.0, wave, 0.4), (0.42, door, 0.5), (0.46, bell, 0.4)])


def c_laundry_start():
    n = ns(1.7)
    t = taxis(n)
    f = 46.0 + 30.0 * np.clip(t / 1.2, 0, 1) ** 0.7
    ph = phase_of(f)
    hum = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.2 * np.sin(4 * ph)
           + 0.12 * np.sin(5 * ph) + 0.07 * np.sin(6 * ph)) * env(
        [(0, 0), (0.15, 0.3), (1.0, 0.8), (1.45, 0.7), (1.7, 0)], n)
    r = rng("washer")
    rum = filt(r.standard_normal(n), lambda fr: H_lp(fr, 260.0) * H_hp(fr, 50.0))[:n]
    rum /= np.max(np.abs(rum)) + 1e-9
    rum *= (0.7 + 0.3 * np.sin(TAU * 5.5 * t)) * env([(0, 0), (0.3, 0.5), (1.2, 1.0), (1.7, 0)], n)
    slosh = sweep(1.4, [(0, 500), (0.7, 900), (1.4, 600)], 0.8, [(0, 0), (0.5, 0.8), (1.0, 0.5), (1.4, 0)], "slosh")
    return place(1.75, [(0.0, click(2600.0, 1.5, 0.008, "wbtn"), 0.3), (0.02, hum, 0.35), (0.0, rum, 0.45),
                        (0.3, slosh, 0.5)])


def c_laundry_done():
    puff = lp_noise(0.4, 1200.0, [(0, 0), (0.05, 1.0), (0.4, 0)], "fluff", 120.0)
    return place(1.1, [(0.0, I.glock(89, 0.65, 0, 1.0), 0.5), (0.0, I.celesta(84, 0.5, 1, 0.9), 0.35),
                       (0.18, puff, 0.35), (0.22, flap(0.25, "fluffflap", 18.0, 700.0), 0.25)])


def c_stock_refill():
    return place(0.32, [(0.0, bubble(620.0, 0.035, 1.6, "pop"), 0.8), (0.0, click(3200.0, 1.0, 0.004, "popc"), 0.2),
                        (0.03, I.celesta(96, 0.4, 0, 0.25), 0.25)])


def c_gate():
    r = rng("gate")
    n = ns(0.5)
    clunk = modal(n, [(310.0, 1.0, 0.09), (742.0, 0.8, 0.07), (1215.0, 0.6, 0.05), (1830.0, 0.35, 0.035),
                      (2650.0, 0.15, 0.02)], r,
                  attack=0.001)
    return place(0.55, [(0.0, clunk, 0.7), (0.0, thud(150.0, 0.12, "gthud", 0.4, 600.0, 0.2, 0.03), 0.4),
                        (0.0, click(2400.0, 1.2, 0.006, "gclk"), 0.2)])


def c_thermostat():
    items = []
    for i, t in enumerate([0.0, 0.045, 0.09]):
        items.append((t, click(2900.0 + 150 * i, 3.0, 0.012, f"th{i}", 0.0015), 0.6 - 0.1 * i))
    items.append((0.15, I.woodblock(1600.0, 0.4, 3, 0.0), 0.3))
    return place(0.32, items)


def c_pump_mode():
    n = ns(0.95)
    t = taxis(n)
    f = env([(0, 92.0), (0.22, 92.0), (0.5, 123.0), (0.95, 123.0)], n)
    ph = phase_of(f)
    hum = (np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.4 * np.sin(3 * ph) + 0.25 * np.sin(4 * ph)
           + 0.15 * np.sin(5 * ph) + 0.08 * np.sin(6 * ph))
    hum *= env([(0, 0), (0.06, 0.8), (0.2, 0.8), (0.26, 0.55), (0.55, 0.85), (0.8, 0.6), (0.95, 0)], n)
    return place(1.0, [(0.0, hum, 0.6), (0.22, click(2100.0, 2.0, 0.01, "pclk", 0.0015), 0.35),
                       (0.23, I.woodblock(1100.0, 0.4, 0, 0.3), 0.15)])


def c_lift_depart():
    sw = sweep(1.1, [(0, 300), (1.1, 3000)], 0.9, [(0, 0), (0.3, 0.9), (0.85, 0.7), (1.1, 0)], "liftup")
    rise = tone(1.1, [(0, 200), (1.1, 560)], [(0, 0), (0.3, 0.5), (0.9, 0.4), (1.1, 0)], ((1, 1.0), (2, 0.2)),
                seed="liftup")
    return place(1.15, [(0.0, sw, 0.6), (0.0, rise, 0.25)])


def c_lift_arrive():
    settle = sweep(0.5, [(0, 2000), (0.5, 500)], 0.9, [(0, 0), (0.1, 0.8), (0.5, 0)], "liftdown")
    return place(1.4, [(0.0, settle, 0.3), (0.3, I.glock(89, 0.7, 0, 1.2), 0.5), (0.3, I.celesta(84, 0.5, 0, 1.0), 0.3),
                       (0.3, I.felt_piano(65, 0.8, 0.45, 0, 0.3), 0.25)])


def c_shutter_warn():
    # wind-up toy ratchet: soft wooden ticks climbing a friendly scale
    pitches = [72, 74, 76, 77, 79, 81, 82, 84]
    items = []
    for i, m in enumerate(pitches):
        t = 0.16 * i
        items.append((t, I.woodblock(midi_hz(m + 12) * 0.5, 0.5, i, 0.2), 0.45))
        items.append((t, I.marimba(m, 0.35, i, 0.2), 0.25))
    return place(1.45, items)


def c_shutter_close():
    r = rng("slats")
    items = []
    for i in range(10):
        t = 0.06 * i + 0.002 * i * i
        items.append((t, I.woodblock(900.0 - 30.0 * i, 0.5, i, 0.5), 0.35 * (1.0 - 0.03 * i)))
    items.append((0.82, thud(120.0, 0.2, "shut", 0.5, 500.0, 0.2, 0.05), 0.5))
    return place(1.1, items)


def c_shutter_open():
    items = []
    for i in range(10):
        t = 0.055 * i
        items.append((t, I.woodblock(640.0 + 32.0 * i, 0.48, i, 0.5), 0.33))
    items.append((0.6, I.glock(89, 0.55, 0, 0.8), 0.35))
    return place(1.2, items)


def c_bell_ring():
    # the lobby bell plays the welcome motif F6-A6-C7 on beats 0, 1/2, 1 1/2 at 108 BPM
    b = 60.0 / 108.0
    return place(2.5, [(0.0, I.desk_bell(89, 0.8, 0), 0.6), (0.5 * b, I.desk_bell(93, 0.82, 1), 0.6),
                       (1.5 * b, I.desk_bell(96, 0.9, 2), 0.65)])


def c_bell_hiccup():
    n = ns(0.18)
    r = rng("hic_bell")
    t = taxis(n)
    f = midi_hz(96) * 2.0 ** (2.0 * np.clip(t / 0.04, 0, 1) / 12.0)
    hic = np.sin(phase_of(f)) * np.exp(-t / 0.035) * ramp_in(n, ns(0.001))
    return place(1.5, [(0.0, I.desk_bell(89, 0.8, 0), 0.6),
                       (0.3, hic, 0.45), (0.3, click(3000.0, 1.0, 0.005, "hk"), 0.15),
                       (0.62, I.desk_bell(93, 0.5, 1), 0.35), (0.72, I.desk_bell(93, 0.32, 2), 0.25)])


def c_trunk_drag():
    """1.5 s seamless soft wooden scrape."""
    L = ns(1.5)
    r = rng("trunk")
    t = np.arange(L) / SR
    x = r.standard_normal(L)
    x = filt(x, lambda f: H_bp(f, 520.0, 0.7) * H_lp(f, 1600.0), circular=True)
    x /= np.max(np.abs(x)) + 1e-9
    # stick-slip: periodic-in-loop irregular pulse train
    slip = np.zeros(L)
    p = 0
    while p < L:
        slip[p] = r.uniform(0.5, 1.0)
        p += int(r.uniform(0.022, 0.05) * SR)
    kern = np.exp(-np.arange(ns(0.03)) / ns(0.008))
    s = np.real(np.fft.ifft(np.fft.fft(slip) * np.fft.fft(kern, L)))
    s /= np.max(s) + 1e-9
    sway = 0.75 + 0.25 * np.sin(TAU * t / 1.5 * 2)
    grit = filt(r.standard_normal(L), lambda f: H_bp(f, 2400.0, 0.8), circular=True)
    grit /= np.max(np.abs(grit)) + 1e-9
    y = x * (0.45 + 0.55 * s) * sway + 0.12 * grit * s
    return filt(y, lambda f: H_hp(f, 70.0), circular=True)


def c_trunk_open():
    return place(1.5, [(0.0, click(2600.0, 2.0, 0.012, "latch1", 0.002), 0.4),
                       (0.12, click(2400.0, 2.0, 0.012, "latch2", 0.002), 0.35),
                       (0.18, I.squeak(700.0, 0.22, 0.5, 2, 1.0), 0.15),
                       (0.42, mallets([(0.0, 84, 0.55), (0.07, 89, 0.6), (0.14, 93, 0.65), (0.21, 96, 0.72)],
                                      "celesta"), 0.45),
                       (0.42, shimmer(0.7, "trunkopen"), 0.05)])


# ---------------------------------------------------------------- v2 verbs
# One short cue per new verb, each in the kit's own voice (wood, mallets, air),
# so pass counters, the middle step, trunks and the lane hazards read by ear.

def c_counter_put():
    # setting something down on the pass counter: a flat wooden tap, brighter than "place"
    return place(0.24, [(0.0, thud(210.0, 0.12, "cput", 0.25, 1100.0, 0.3, 0.03), 0.7),
                        (0.004, I.woodblock(1320.0, 0.35, 0, 0.5), 0.35),
                        (0.06, click(3600.0, 1.4, 0.008, "cput_c", 0.001), 0.15)])


def c_counter_take():
    # taking from the counter: the same wood, a rising flick
    return place(0.22, [(0.0, I.woodblock(1760.0, 0.4, 1, 0.3), 0.3),
                        (0.004, tone(0.12, [(0, 700), (0.06, 1100), (0.12, 1250)],
                                     [(0, 0), (0.01, 1), (0.06, 0.5), (0.12, 0)],
                                     ((1, 1.0), (2, 0.12)), seed="ctake"), 0.7)])


def c_temper():
    # the heat pump's middle step: a soft breath, then two celesta notes as the badge appears
    return place(0.8, [(0.0, lp_noise(0.35, 900.0, [(0, 0), (0.05, 1), (0.35, 0)], "temper_n"), 0.35),
                       (0.1, mallets([(0.0, 84, 0.5), (0.1, 91, 0.6)], "celesta"), 0.45),
                       (0.2, shimmer(0.5, "temper_s"), 0.06)])


def c_vent():
    # the same step at an open vent: air through slats and one glockenspiel note
    return place(0.7, [(0.0, bp_noise(0.45, 1800.0, 1.0, [(0, 0), (0.08, 1), (0.45, 0)], "vent_n"), 0.4),
                       (0.18, I.glock(91, 0.5, 0, 0.6), 0.3)])


def c_trunk_grab():
    # a trunk handle: a latch click, a low wooden heft, a short squeak of the leather
    return place(0.3, [(0.0, click(1800.0, 1.6, 0.01, "tg_latch", 0.002), 0.4),
                       (0.03, thud(140.0, 0.2, "tg_thud", 0.4, 600.0, 0.3, 0.05), 0.8),
                       (0.08, I.squeak(520.0, 0.14, 0.4, 0, 1.0), 0.15)])


def c_slip():
    # a frosty slide: a glassy whistle falling away under a tiny bell
    return place(0.6, [(0.0, small_bell(0.3, [(0.0, 0.5)], 3100.0, "slip_b"), 0.35),
                       (0.02, whistle(0.45, [(0, 1900), (0.45, 700)], [(0, 0), (0.05, 1), (0.45, 0)], "slip_w", 0.4), 0.5),
                       (0.3, _foot(200.0, "slip_f", 0.5), 0.3)])


def c_startle():
    # a startled hop: a quick rising "yip", then the dropped item's little knock
    return place(0.55, [(0.0, tone(0.16, [(0, 420), (0.06, 980), (0.16, 820)], [(0, 0), (0.01, 1), (0.16, 0)],
                                   ((1, 1.0), (2, 0.3), (3, 0.1)), seed="startle"), 0.6),
                        (0.22, thud(230.0, 0.12, "startle_d", 0.3, 1000.0, 0.3, 0.03), 0.5),
                        (0.22, click(2600.0, 1.6, 0.008, "startle_c", 0.001), 0.2)])


def c_order_served():
    # an order served in full: four celesta notes up the motif and a shimmer
    return place(0.9, [(0.0, mallets([(0.0, 84, 0.5), (0.08, 91, 0.6), (0.16, 96, 0.7), (0.26, 103, 0.75)], "celesta"), 0.5),
                       (0.26, shimmer(0.5, "served_s"), 0.05)])


def c_order_late():
    # served late, happily: three marimba notes that go up and settle back a step
    return place(0.8, [(0.0, mallets([(0.0, 84, 0.5), (0.1, 89, 0.55), (0.28, 86, 0.5)], "marimba"), 0.5),
                       (0.1, I.celesta(89, 0.3, 0, 0.3), 0.2)])


def c_parcel_place():
    return place(0.4, [(0.0, thud(150.0, 0.18, "parcel", 0.7, 650.0, 0.2, 0.04), 0.7),
                       (0.0, rustle(0.15, "parcel_r", 260.0, 1200.0, 5000.0, [(0, 1), (0.15, 0)]), 0.15)])


def c_gift_place():
    return place(1.0, [(0.0, thud(170.0, 0.15, "gift", 0.5, 700.0, 0.2, 0.035), 0.55),
                       (0.05, sparkle(0.9, "gift", 4, (89, 93, 96, 101), "celesta", 0.5, 0.25), 0.35)])


def c_ticket_assign():
    return place(0.4, [(0.0, thud(110.0, 0.2, "stamp", 0.5, 550.0, 0.3, 0.04), 0.7),
                       (0.0, I.woodblock(520.0, 0.5, 0, 1.0), 0.3),
                       (0.01, rustle(0.08, "stamp_paper", 300.0, 2000.0, 6000.0, [(0, 1), (0.08, 0)]), 0.1)])


def c_bed_make():
    return place(0.5, [(0.0, flap(0.4, "bedsnap", 20.0, 1000.0, snap=0.9), 0.8),
                       (0.05, sweep(0.3, [(0, 1500), (0.3, 700)], 0.8, [(0, 0), (0.08, 1), (0.3, 0)], "bedair"), 0.2)])


def c_bed_strip():
    r1 = rustle(0.85, "bedstrip", 120.0, 600.0, 4500.0, [(0, 0), (0.15, 1.0), (0.6, 0.7), (0.85, 0)], grain=0.006)
    return place(0.9, [(0.0, r1, 0.55), (0.1, flap(0.5, "strip", 14.0, 700.0), 0.45)])


def c_hamper():
    return place(0.45, [(0.0, thud(100.0, 0.25, "hamper", 0.8, 420.0, 0.1, 0.06), 0.7),
                        (0.0, flap(0.2, "hamp", 18.0, 600.0), 0.3), (0.05, I.squeak(500.0, 0.1, 0.3, 0, 1.0), 0.05)])


# ---------------------------------------------------------------- guests: slime

def _gloop(dur, f0_pts, seed, vowel="o", wob=60.0):
    return voice(dur, f0_pts, [(0, "u"), (dur * 0.4, vowel), (dur, "u")],
                 [(0, 0), (0.03, 1.0), (dur * 0.7, 0.8), (dur, 0)], seed, scale=0.85, breath=0.02,
                 vib=(9.0, wob, 0.0), tilt=1.4, bright=0.6)


def c_guest_slime_idle_1():
    return place(0.75, [(0.0, bubble(260.0, 0.09, 0.8, "si1a"), 0.7), (0.3, bubble(320.0, 0.08, 0.9, "si1b"), 0.55),
                        (0.52, bubble(230.0, 0.1, 0.7, "si1c"), 0.6)])


def c_guest_slime_idle_2():
    return place(0.6, [(0.0, _gloop(0.42, [(0, 150), (0.42, 135)], "si2"), 0.8),
                       (0.36, bubble(340.0, 0.07, 0.9, "si2b"), 0.4)])


def c_guest_slime_delight_1():
    return place(0.6, [(0.0, bubbles(0.55, 7, 300.0, 820.0, "sd1", 1.0, (0.04, 0.06), "rising"), 1.0)])


def c_guest_slime_delight_2():
    w = voice(0.4, [(0, 220), (0.3, 360), (0.4, 340)], [(0, "u"), (0.12, "i"), (0.4, "i")],
              [(0, 0), (0.04, 1.0), (0.3, 0.8), (0.4, 0)], "sd2", scale=0.9, vib=(8.0, 50.0, 0.05), bright=0.8)
    return place(0.75, [(0.0, w, 0.7), (0.3, bubbles(0.4, 5, 500.0, 900.0, "sd2b", 1.0, (0.04, 0.06), "rising"), 0.6)])


def c_guest_slime_need_1():
    return place(0.45, [(0.0, _gloop(0.38, [(0, 140), (0.2, 150), (0.38, 205)], "sn1", "o", 40.0), 1.0)])


def c_guest_slime_need_2():
    hum = voice(0.3, [(0, 170), (0.3, 215)], [(0, "m"), (0.3, "m")], [(0, 0), (0.04, 1.0), (0.3, 0)], "sn2",
                scale=0.9, breath=0.02)
    return place(0.6, [(0.0, bubble(280.0, 0.08, 0.8, "sn2a"), 0.6), (0.14, bubble(300.0, 0.07, 0.8, "sn2b"), 0.5),
                       (0.26, hum, 0.6)])


def c_guest_slime_quirk_warn():
    n = ns(1.25)
    t = taxis(n)
    rate = 5.0 + 9.0 * (t / 1.25) ** 1.5
    wob = np.sin(TAU * np.cumsum(rate) / SR)
    base = _gloop(1.25, [(0, 120), (1.25, 165)], "sqw", "o", 30.0)
    return base * (0.55 + 0.45 * wob) * env([(0, 0.3), (1.0, 1.0), (1.25, 0.0)], n)


def c_guest_slime_quirk():
    whoosh = sweep(0.3, [(0, 900), (0.3, 2200)], 1.0, [(0, 0), (0.12, 1.0), (0.3, 0)], "slipper")
    plap = place(0.2, [(0.0, thud(180.0, 0.12, "plap", 0.8, 900.0, 0.2, 0.03), 1.0),
                       (0.0, bubble(380.0, 0.06, 0.9, "plapb"), 0.4)])
    return place(1.1, [(0.0, boing(210.0, 0.45, "sboing", 0.28, 11.0), 0.6), (0.25, whoosh, 0.35),
                       (0.72, plap, 0.55)])


def c_guest_slime_helper():
    return place(1.1, [(0.0, sparkle(1.0, "slimehelp", 6, (84, 89, 93, 96, 101, 105), "celesta", 0.45, 0.5), 0.5),
                       (0.0, sweep(0.8, [(0, 600), (0.8, 2400)], 0.9, [(0, 0), (0.3, 0.7), (0.8, 0)], "slimesw"), 0.25),
                       (0.05, bubbles(0.7, 6, 350.0, 900.0, "slimehb", 1.0, (0.04, 0.07), "rising"), 0.35)])


def c_guest_slime_checkout():
    bye = voice(0.32, [(0, 260), (0.32, 300)], [(0, "b"), (0.03, "b"), (0.08, "ae"), (0.25, "i"), (0.32, "i")],
                [(0, 0), (0.03, 0.2), (0.06, 1.0), (0.25, 0.8), (0.32, 0)], "sco", scale=0.9, bright=0.8)
    return place(0.7, [(0.0, bubble(300.0, 0.08, 0.8, "scoa"), 0.5), (0.14, bubble(380.0, 0.08, 0.9, "scob"), 0.5),
                       (0.3, bye, 0.6)])


# ---------------------------------------------------------------- guests: yeti

def _hum(dur, f_pts, seed, scale=0.82, vowel="m", breath=0.03, amp=None):
    a = amp or [(0, 0), (0.06, 1.0), (dur * 0.7, 0.85), (dur, 0)]
    return voice(dur, f_pts, [(0, vowel), (dur, vowel)], a, seed, scale=scale, breath=breath, tilt=1.25)


def _sniff(dur, seed):
    return breath_noise(dur, [(0, "i"), (dur, "i")], [(0, 0), (dur * 0.25, 1.0), (dur, 0)], seed, scale=1.3,
                        tilt_hp=1500.0)


def c_guest_yeti_idle_1():
    return _hum(0.85, [(0, 112), (0.4, 118), (0.85, 108)], "yi1")


def c_guest_yeti_idle_2():
    return place(1.05, [(0.0, _hum(0.28, [(0, 110), (0.28, 110)], "yi2a"), 0.9),
                        (0.3, _hum(0.28, [(0, 123), (0.28, 123)], "yi2b"), 0.9),
                        (0.6, _hum(0.42, [(0, 138), (0.42, 131)], "yi2c"), 1.0)])


def c_guest_yeti_delight_1():
    oh = voice(0.55, [(0, 112), (0.3, 165), (0.55, 158)], [(0, "o"), (0.3, "o"), (0.55, "u")],
               [(0, 0), (0.05, 1.0), (0.4, 0.8), (0.55, 0)], "yd1", scale=0.82, breath=0.05, tilt=1.2)
    return oh


def c_guest_yeti_delight_2():
    items = [(0.17 * i, _hum(0.13, [(0, 128 - 4 * i), (0.13, 120 - 4 * i)], f"yd2{i}",
                              amp=[(0, 0), (0.02, 1.0), (0.13, 0)]), 1.0 - 0.1 * i) for i in range(3)]
    return place(0.62, items)


def c_guest_yeti_need_1():
    return place(0.65, [(0.0, _sniff(0.12, "yn1s"), 0.3),
                        (0.15, _hum(0.42, [(0, 108), (0.25, 112), (0.42, 140)], "yn1h"), 1.0)])


def c_guest_yeti_need_2():
    return place(0.5, [(0.0, _sniff(0.13, "yn2a"), 0.8), (0.2, _sniff(0.16, "yn2b"), 0.9),
                       (0.36, _hum(0.12, [(0, 118), (0.12, 116)], "yn2h", amp=[(0, 0), (0.02, 0.7), (0.12, 0)]), 0.5)])


def _inhale_ah(dur, f_lo, f_hi, seed, gain=1.0):
    v = voice(dur, [(0, f_lo), (dur, f_hi)], [(0, "uh"), (dur * 0.4, "a"), (dur, "a")],
              [(0, 0), (dur * 0.5, 0.35), (dur * 0.9, 0.7), (dur, 0)], seed, scale=0.85, breath=0.9, tilt=1.4,
              aspir_pts=[(0, 0), (dur * 0.3, 0.6), (dur * 0.85, 1.0), (dur, 0)], bright=0.8)
    return v * gain


def c_guest_yeti_quirk_warn():
    """Four seconds of building 'ah... ah... ahh...' before the sneeze."""
    return place(4.0, [(0.12, _inhale_ah(0.85, 150.0, 172.0, "ywa1", 0.55), 1.0),
                       (1.35, _inhale_ah(0.95, 165.0, 200.0, "ywa2", 0.75), 1.0),
                       (2.6, _inhale_ah(1.25, 185.0, 245.0, "ywa3", 1.0), 1.0)])


def c_guest_yeti_quirk():
    tch = bp_noise(0.07, 3800.0, 1.2, [(0, 0), (0.005, 1.0), (0.07, 0)], "tch", lo=1800.0)
    choo = voice(0.36, [(0, 270), (0.36, 175)], [(0, "u"), (0.36, "u")], [(0, 0), (0.02, 1.0), (0.2, 0.6), (0.36, 0)],
                 "choo", scale=0.88, breath=0.45, tilt=1.25)
    frost = sparkle(0.6, "yfrost", 4, (98, 101, 105, 103), "glass", 0.45, 0.3)
    return place(1.0, [(0.0, tch, 0.6), (0.05, choo, 0.8), (0.18, frost, 0.25), (0.72, _sniff(0.12, "yqs"), 0.25)])


def c_guest_yeti_helper():
    wind = sweep(1.0, [(0, 2400), (0.5, 1500), (1.0, 2000)], 0.8, [(0, 0), (0.3, 0.8), (1.0, 0)], "ywind")
    return place(1.1, [(0.0, wind, 0.4), (0.15, sparkle(0.9, "yhelp", 4, (93, 98, 101, 105), "glass", 0.5, 0.4), 0.35),
                       (0.2, _hum(0.5, [(0, 118), (0.5, 130)], "yhh"), 0.45)])


def c_guest_yeti_checkout():
    return place(0.75, [(0.0, _hum(0.2, [(0, 123), (0.2, 120)], "yco1", amp=[(0, 0), (0.03, 1), (0.2, 0)]), 0.9),
                        (0.24, _hum(0.38, [(0, 140), (0.2, 150), (0.38, 146)], "yco2"), 1.0)])


# ---------------------------------------------------------------- guests: dragon

def _purr(dur, seed, rate=24.0):
    n = ns(dur)
    t = taxis(n)
    r = rng("purr", seed)
    x = filt(r.standard_normal(n), lambda f: H_lp(f, 240.0) * H_hp(f, 50.0))[:n]
    x /= np.max(np.abs(x)) + 1e-9
    return x * (0.5 + 0.5 * np.sin(TAU * rate * t) ** 2) * env([(0, 0), (0.1, 1.0), (dur * 0.8, 0.8), (dur, 0)], n)


def c_guest_dragon_idle_1():
    return place(0.9, [(0.0, whistle(0.8, [(0, 920), (0.8, 1080)], [(0, 0), (0.25, 0.8), (0.65, 0.7), (0.8, 0)],
                                     "di1", 0.35), 0.6), (0.0, _purr(0.8, "di1p"), 0.3)])


def c_guest_dragon_idle_2():
    return place(0.8, [(0.0, _purr(0.7, "di2p", 21.0), 0.6),
                       (0.3, whistle(0.35, [(0, 1180), (0.35, 1120)], [(0, 0), (0.08, 0.7), (0.35, 0)], "di2", 0.3), 0.4)])


def c_guest_dragon_delight_1():
    return whistle(0.62, [(0, 900), (0.45, 1550), (0.62, 1500)], [(0, 0), (0.06, 0.8), (0.45, 1.0), (0.62, 0)],
                   "dd1", 0.25, vib=(7.0, 35.0, 0.2))


def c_guest_dragon_delight_2():
    return place(0.8, [(0.0, whistle(0.32, [(0, 1050), (0.32, 1400)], [(0, 0), (0.05, 0.9), (0.32, 0.5)], "dd2a", 0.25), 1.0),
                       (0.3, whistle(0.45, [(0, 1400), (0.45, 1050)], [(0, 0.5), (0.06, 0.9), (0.45, 0)], "dd2b", 0.25,
                                     vib=(6.5, 25.0, 0.1)), 1.0)])


def c_guest_dragon_need_1():
    return whistle(0.42, [(0, 900), (0.3, 980), (0.42, 1250)], [(0, 0), (0.06, 0.8), (0.32, 0.8), (0.42, 0)], "dn1", 0.3)


def c_guest_dragon_need_2():
    sigh = bp_noise(0.4, 2400.0, 0.6, [(0, 0), (0.05, 1.0), (0.4, 0)], "dsigh", lo=800.0)
    return place(0.7, [(0.0, sigh, 0.5), (0.25, whistle(0.4, [(0, 1100), (0.25, 950), (0.4, 1020)],
                                                         [(0, 0), (0.05, 0.6), (0.4, 0)], "dn2", 0.3), 0.6)])


def c_guest_dragon_quirk_warn():
    """Four seconds: a little kettle coming up to the boil (the hiccup is coming)."""
    n = ns(4.0)
    rumble = _purr(4.0, "dqw_r", 9.0) * env([(0, 0.4), (3.0, 1.0), (4.0, 0.0)], n)
    wh = whistle(4.0, [(0, 680), (2.5, 900), (3.85, 1150), (4.0, 1150)],
                 [(0, 0), (1.2, 0.08), (2.6, 0.45), (3.85, 0.85), (4.0, 0)], "dqw_w", 0.45, vib=(6.0, 12.0, 1.0))
    bl = bubbles(4.0, 14, 160.0, 420.0, "dqw_b", 0.6, (0.05, 0.1))
    bl *= env([(0, 0.2), (3.6, 1.0), (4.0, 0)], n)
    return place(4.0, [(0.0, rumble, 0.35), (0.0, wh, 0.5), (0.0, bl, 0.3)])


def c_guest_dragon_quirk():
    hic = voice(0.09, [(0, 300), (0.02, 470), (0.09, 440)], [(0, "i"), (0.09, "i")],
                [(0, 0), (0.008, 1.0), (0.06, 0.6), (0.09, 0)], "dhic", scale=1.05, breath=0.2)
    steam = sweep(0.5, [(0, 2600), (0.5, 1600)], 0.5, [(0, 0), (0.04, 1.0), (0.5, 0)], "dsteam", floor=0.02,
                  lp=6500.0)
    toot = whistle(0.14, [(0, 1420), (0.14, 1400)], [(0, 0), (0.02, 0.8), (0.14, 0)], "dtoot", 0.2, vib=None)
    return place(0.8, [(0.0, hic, 0.8), (0.07, steam, 0.4), (0.3, toot, 0.3)])


def c_guest_dragon_helper():
    warm = sweep(0.9, [(0, 500), (0.45, 1200), (0.9, 700)], 0.7, [(0, 0), (0.3, 0.9), (0.9, 0)], "dwarm")
    return place(1.1, [(0.0, warm, 0.5), (0.2, whistle(0.7, [(0, 1000), (0.4, 1350), (0.7, 1300)],
                                                         [(0, 0), (0.1, 0.8), (0.7, 0)], "dhelpw", 0.3), 0.5),
                       (0.6, sparkle(0.5, "dhelp", 3, (89, 93, 96), "celesta", 0.4, 0.2), 0.25)])


def c_guest_dragon_checkout():
    return place(0.7, [(0.0, whistle(0.16, [(0, 1250), (0.16, 1250)], [(0, 0), (0.02, 0.9), (0.16, 0)], "dco1", 0.25, None), 1.0),
                       (0.22, whistle(0.3, [(0, 1250), (0.1, 1580), (0.3, 1560)], [(0, 0), (0.02, 0.9), (0.3, 0)],
                                      "dco2", 0.25, (6.5, 20.0, 0.1)), 1.0)])


# ---------------------------------------------------------------- guests: ghost

def _ooo(dur, f_pts, seed, vowel="u", air=1.3, wob=40.0, amp=None):
    a = amp or [(0, 0), (dur * 0.3, 1.0), (dur * 0.7, 0.8), (dur, 0)]
    v = voice(dur, f_pts, [(0, vowel), (dur, vowel)], a, seed, scale=1.05, breath=air, tilt=1.6,
              vib=(3.2, wob, 0.0), bright=0.6, aspir_pts=a)
    return v


def c_guest_ghost_idle_1():
    return _ooo(1.0, [(0, 330), (0.5, 350), (1.0, 320)], "gi1")


def c_guest_ghost_idle_2():
    return place(1.1, [(0.0, _ooo(0.5, [(0, 340), (0.5, 345)], "gi2a"), 0.9),
                       (0.45, _ooo(0.6, [(0, 300), (0.6, 295)], "gi2b"), 0.9)])


def c_guest_ghost_delight_1():
    return place(0.95, [(0.0, _ooo(0.8, [(0, 300), (0.6, 450), (0.8, 440)], "gd1", "o"), 1.0),
                        (0.4, shimmer(0.5, "gd1"), 0.1)])


def c_guest_ghost_delight_2():
    items = [(0.16 * i, _ooo(0.14, [(0, 420 - 15 * i), (0.14, 400 - 15 * i)], f"gd2{i}", "i", 0.8, 0.0,
                              [(0, 0), (0.03, 1.0), (0.14, 0)]), 1.0) for i in range(3)]
    return place(0.65, items)


def c_guest_ghost_need_1():
    shh = breath_noise(0.4, [(0, "i"), (0.4, "i")], [(0, 0), (0.1, 1.0), (0.4, 0)], "gshh", scale=1.6, tilt_hp=2500.0)
    return place(0.95, [(0.0, shh, 0.6), (0.38, _ooo(0.5, [(0, 300), (0.5, 380)], "gn1"), 0.8)])


def c_guest_ghost_need_2():
    return _ooo(0.7, [(0, 300), (0.4, 310), (0.7, 400)], "gn2")


def c_guest_ghost_quirk_warn():
    rus = flap(0.6, "gqw_flap", 10.0, 800.0)
    return place(1.1, [(0.0, _ooo(1.0, [(0, 280), (1.0, 420)], "gqw", "o", 0.9, 30.0,
                                  [(0, 0), (0.7, 1.0), (1.0, 0)]), 0.9), (0.45, rus, 0.25)])


def c_guest_ghost_quirk():
    return place(1.1, [(0.0, flap(0.7, "gq_sheet", 13.0, 900.0), 0.6),
                       (0.1, _ooo(0.8, [(0, 360), (0.3, 480), (0.8, 330)], "gq", "o", 0.8, 60.0), 0.8)])


def c_guest_ghost_helper():
    return place(1.0, [(0.0, sweep(0.7, [(0, 900), (0.7, 2200)], 0.9, [(0, 0), (0.3, 0.6), (0.7, 0)], "ghelp"), 0.35),
                       (0.3, I.celesta(89, 0.4, 0, 0.6), 0.3), (0.0, _ooo(0.6, [(0, 330), (0.6, 360)], "ghelpv"), 0.6)])


def c_guest_ghost_checkout():
    return _ooo(1.0, [(0, 380), (1.0, 300)], "gco", "o", 0.9, 20.0, [(0, 0), (0.15, 1.0), (1.0, 0)])


# ---------------------------------------------------------------- guests: moonwolf

def _sung(dur, f_pts, vow_pts, seed, vib=(5.4, 22.0, 0.18), clar=0.35, scale=0.95, amp=None):
    a = amp or [(0, 0), (0.06, 1.0), (dur * 0.75, 0.85), (dur, 0)]
    v = voice(dur, f_pts, vow_pts, a, seed, scale=scale, breath=0.05, tilt=1.1, vib=vib, bright=0.9)
    if clar > 0:
        n = len(v)
        f = env(f_pts, n)
        # clarinet colour on the same pitch contour
        ph = phase_of(f * 2.0 ** (vib[1] * np.clip((taxis(n) - vib[2]) / 0.2, 0, 1)
                                  * np.sin(TAU * vib[0] * taxis(n)) / 1200.0))
        c = sum(a_ * np.sin(k * ph) for k, a_ in ((1, 1.0), (3, 0.45), (5, 0.22), (7, 0.1)))
        c = c * env(a, n) / 1.6
        v = v + clar * c
    return v


def c_guest_moonwolf_idle_1():
    return _sung(0.8, [(0, 220), (0.8, 220)], [(0, "m"), (0.8, "m")], "mi1", clar=0.15)


def c_guest_moonwolf_idle_2():
    # three hummed notes: A3 C4 D4 (fits F major and friends)
    return place(1.1, [(0.0, _sung(0.3, [(0, 220), (0.3, 220)], [(0, "m"), (0.3, "m")], "mi2a", clar=0.15), 1.0),
                       (0.32, _sung(0.3, [(0, 262), (0.3, 262)], [(0, "m"), (0.3, "m")], "mi2b", clar=0.15), 1.0),
                       (0.64, _sung(0.45, [(0, 294), (0.45, 294)], [(0, "m"), (0.45, "m")], "mi2c", clar=0.15), 1.0)])


def c_guest_moonwolf_delight_1():
    return _sung(0.7, [(0, 330), (0.08, 440), (0.7, 440)], [(0, "a"), (0.15, "r"), (0.3, "u"), (0.7, "u")], "md1")


def c_guest_moonwolf_delight_2():
    return place(0.9, [(0.0, _sung(0.35, [(0, 294), (0.35, 294)], [(0, "a"), (0.35, "a")], "md2a"), 1.0),
                       (0.34, _sung(0.5, [(0, 440), (0.5, 440)], [(0, "o"), (0.2, "u"), (0.5, "u")], "md2b"), 1.0)])


def c_guest_moonwolf_need_1():
    return _sung(0.5, [(0, 330), (0.3, 340), (0.5, 392)], [(0, "u"), (0.5, "u")], "mn1", vib=(5.4, 10.0, 0.3))


def c_guest_moonwolf_need_2():
    return _sung(0.72, [(0, 392), (0.35, 330), (0.6, 330), (0.72, 349)], [(0, "o"), (0.72, "o")], "mn2",
                 vib=(5.2, 15.0, 0.25))


def c_guest_moonwolf_quirk_warn():
    """Exactly 4.0 s: a big, friendly breath-in swell."""
    n = ns(4.0)
    inh = breath_noise(4.0, [(0, "u"), (1.5, "o"), (3.9, "a"), (4.0, "a")],
                       [(0, 0), (1.0, 0.18), (2.5, 0.5), (3.75, 1.0), (3.93, 0.6), (4.0, 0)], "mqw", scale=1.0,
                       tilt_hp=700.0)
    # faint rising pitch-glow, like a chest filling up (a hummed glissando)
    glow = _sung(4.0, [(0, 180), (3.9, 330), (4.0, 330)], [(0, "m"), (4.0, "m")], "mqw_g", vib=(5.0, 6.0, 1.0),
                 clar=0.1, amp=[(0, 0), (1.5, 0.05), (3.7, 0.3), (3.95, 0.15), (4.0, 0)])
    return place(4.0, [(0.0, inh, 0.85), (0.0, glow, 0.25)])


def c_guest_moonwolf_quirk():
    """A short friendly sung 'aroo' (musical, clarinet-like) - not a dog howl."""
    return _sung(1.3, [(0, 330), (0.12, 440), (1.0, 440), (1.3, 446)],
                 [(0, "a"), (0.12, "a"), (0.26, "r"), (0.42, "u"), (1.3, "u")], "mq", vib=(5.4, 22.0, 0.3),
                 clar=0.45, amp=[(0, 0), (0.07, 0.85), (0.4, 1.0), (1.0, 0.85), (1.3, 0)])


def c_guest_moonwolf_helper():
    seq = [(0.0, 220, 0.25), (0.27, 262, 0.25), (0.54, 294, 0.25), (0.81, 330, 0.4)]
    items = [(t, _sung(d, [(0, f), (d, f)], [(0, "m"), (d, "m")], f"mh{i}", clar=0.2), 0.9) for i, (t, f, d) in enumerate(seq)]
    items.append((0.6, sparkle(0.6, "mhelp", 3, (93, 96, 101), "celesta", 0.4, 0.3), 0.25))
    return place(1.3, items)


def c_guest_moonwolf_checkout():
    return place(0.8, [(0.0, _sung(0.22, [(0, 330), (0.22, 330)], [(0, "a"), (0.22, "a")], "mco1"), 1.0),
                       (0.24, _sung(0.45, [(0, 392), (0.06, 440), (0.45, 440)], [(0, "w"), (0.08, "u"), (0.45, "u")],
                                    "mco2"), 1.0)])


# ---------------------------------------------------------------- guests: sprout

def _chirps(notes, seed, breath=0.05):
    """notes: (start_s, dur_s, midi, vel) flute chirps."""
    return I.render_lead(notes, "flute", seed=seed, breath=breath, vib_cents=6.0, attack=0.012, release=0.05,
                         cutoff=3800.0)


def _leaves(dur, seed, density=140.0, amp=None):
    return rustle(dur, seed, density, 1400.0, 6000.0, amp or [(0, 0), (dur * 0.2, 1.0), (dur * 0.7, 0.7), (dur, 0)],
                  grain=0.003)


def c_guest_sprout_idle_1():
    return _leaves(0.6, "spi1")


def c_guest_sprout_idle_2():
    return place(0.65, [(0.0, _leaves(0.4, "spi2"), 0.5), (0.2, _chirps([(0, 0.12, 93, 0.7)], "spi2c"), 0.7)])


def c_guest_sprout_delight_1():
    notes = [(0.07 * i, 0.065, m, 0.7) for i, m in enumerate([89, 91, 93, 96, 98])]
    return place(0.6, [(0.0, _chirps(notes, "spd1"), 0.9), (0.0, _leaves(0.4, "spd1l", 90.0), 0.25)])


def c_guest_sprout_delight_2():
    return place(0.75, [(0.0, _leaves(0.35, "spd2l"), 0.4),
                        (0.1, _chirps([(0, 0.12, 93, 0.75), (0.15, 0.2, 96, 0.8)], "spd2c"), 0.8),
                        (0.45, bubble(700.0, 0.03, 1.8, "spd2p"), 0.35)])


def c_guest_sprout_need_1():
    return _chirps([(0, 0.08, 91, 0.7), (0.1, 0.2, 96, 0.75)], "spn1")


def c_guest_sprout_need_2():
    return place(0.7, [(0.0, _leaves(0.3, "spn2l", 80.0), 0.4),
                       (0.25, _chirps([(0, 0.14, 91, 0.6), (0.16, 0.22, 93, 0.65)], "spn2c"), 0.8)])


def c_guest_sprout_quirk_warn():
    n = ns(1.25)
    lv = _leaves(1.25, "spqw", 220.0, [(0, 0.1), (1.1, 1.0), (1.25, 0)])
    gl = I.render_lead([(0.3, 0.9, 86, 0.6)], "flute", seed="spqw_gl", breath=0.06, vib_cents=0.0, attack=0.25,
                       release=0.05)
    # glissando: pitch-bend by resampling the held note upward
    m = len(gl)
    pos = np.cumsum(np.linspace(1.0, 1.5, m))
    pos = pos[pos < m - 1]
    gl = np.interp(pos, np.arange(m), gl)
    return place(1.3, [(0.0, lv, 0.55), (0.0, gl, 0.5)])


def c_guest_sprout_quirk():
    pop = place(0.1, [(0.0, bubble(320.0, 0.03, 4.0, "bloom"), 1.0), (0.0, click(2500.0, 0.8, 0.006, "bloomc"), 0.4)])
    return place(0.9, [(0.0, pop, 0.8), (0.04, sparkle(0.8, "spq", 4, (93, 96, 101, 105), "celesta", 0.5, 0.25), 0.4),
                       (0.1, _chirps([(0, 0.08, 96, 0.7), (0.09, 0.08, 98, 0.7), (0.18, 0.25, 101, 0.75)], "spqf"), 0.55)])


def c_guest_sprout_helper():
    mist = sweep(0.8, [(0, 4000), (0.8, 6000)], 0.7, [(0, 0), (0.2, 0.7), (0.8, 0)], "spmist")
    notes = [(0.08 * i, 0.08 if i < 3 else 0.3, m, 0.7) for i, m in enumerate([89, 93, 96, 101])]
    return place(1.1, [(0.0, mist, 0.25), (0.1, _chirps(notes, "sph"), 0.8),
                       (0.3, sparkle(0.7, "sphs", 3, (98, 101, 105), "celesta", 0.4, 0.3), 0.25)])


def c_guest_sprout_checkout():
    return place(0.7, [(0.0, _chirps([(0, 0.12, 96, 0.75), (0.16, 0.26, 101, 0.75)], "spco"), 0.85),
                       (0.3, _leaves(0.35, "spcol", 90.0), 0.3)])


# ---------------------------------------------------------------- staff / NPC

def c_staff_effort():
    return voice(0.2, [(0, 300), (0.12, 340), (0.2, 320)], [(0, "uh"), (0.2, "uh")],
                 [(0, 0), (0.015, 1.0), (0.12, 0.8), (0.2, 0)], "effort", scale=1.15, breath=0.3,
                 aspir_pts=[(0, 1.0), (0.03, 0.4), (0.2, 0.1)])


def c_staff_thanks():
    a = voice(0.16, [(0, 330), (0.16, 360)], [(0, "d"), (0.02, "d"), (0.06, "ae"), (0.16, "ae")],
              [(0, 0), (0.02, 0.2), (0.04, 1.0), (0.16, 0.6)], "thx1", scale=1.15)
    b = voice(0.26, [(0, 400), (0.26, 330)], [(0, "y"), (0.05, "u"), (0.26, "u")],
              [(0, 0.5), (0.04, 1.0), (0.18, 0.8), (0.26, 0)], "thx2", scale=1.15)
    return place(0.45, [(0.0, a, 1.0), (0.16, b, 1.0)])


def c_staff_wave():
    return voice(0.32, [(0, 320), (0.32, 430)], [(0, "a"), (0.15, "a"), (0.32, "i")],
                 [(0, 0), (0.03, 1.0), (0.25, 0.8), (0.32, 0)], "wave", scale=1.15, breath=0.25,
                 aspir_pts=[(0, 1.0), (0.04, 0.2), (0.32, 0.05)])


def c_nana_hmm():
    return voice(0.75, [(0, 205), (0.45, 192), (0.75, 222)], [(0, "m"), (0.75, "m")],
                 [(0, 0), (0.08, 1.0), (0.6, 0.85), (0.75, 0)], "nana_hmm", scale=0.95, breath=0.06, tilt=1.2,
                 vib=(4.5, 10.0, 0.3))


def c_nana_laugh():
    items = []
    for i, f in enumerate([255, 242, 230, 218]):
        s = voice(0.17, [(0, f), (0.17, f * 0.95)], [(0, "o"), (0.17, "o")],
                  [(0, 0), (0.035, 1.0), (0.1, 0.7), (0.17, 0)], f"nlaugh{i}", scale=0.95, breath=0.45,
                  aspir_pts=[(0, 1.0), (0.04, 0.3), (0.17, 0.1)], tilt=1.25)
        items.append((0.19 * i, s, 1.0 - 0.1 * i))
    return place(0.85, items)


def c_dot_paper():
    items = []
    for i in range(4):
        items.append((0.16 * i, rustle(0.13, f"fold{i}", 400.0, 1600.0, 6000.0, [(0, 0), (0.02, 1.0), (0.13, 0)],
                                       grain=0.0018), 0.6))
        items.append((0.16 * i + 0.02, flap(0.12, f"fan{i}", 30.0, 1300.0), 0.5))
    return place(0.8, items)


def c_dot_hmm():
    a = voice(0.16, [(0, 390), (0.16, 380)], [(0, "m"), (0.16, "m")], [(0, 0), (0.02, 1.0), (0.16, 0)], "dothm1",
              scale=1.2, breath=0.2)
    b = voice(0.24, [(0, 380), (0.24, 470)], [(0, "m"), (0.24, "m")], [(0, 0), (0.02, 1.0), (0.24, 0)], "dothm2",
              scale=1.2, breath=0.2)
    return place(0.5, [(0.0, a, 0.85), (0.2, b, 1.0)])


def c_gus_squeak():
    return place(0.36, [(0.0, I.squeak(1150.0, 0.3, 0.7, 0, 6.0), 0.9), (0.0, click(2600.0, 1.5, 0.006, "gusq"), 0.15)])


def c_gus_chirp():
    return place(0.32, [(0.0, I.squeak(1500.0, 0.09, 0.7, 1, 3.0), 0.9), (0.12, I.squeak(1900.0, 0.12, 0.75, 2, 4.0), 0.9)])


def c_gus_rattle():
    r = rng("gus_rattle")
    items = []
    t = 0.0
    i = 0
    while t < 0.62:
        n = ns(0.05)
        m = modal(n, [(2400.0 + r.uniform(-150, 150), 1.0, 0.012), (3700.0, 0.5, 0.008)], r)
        items.append((t, m, r.uniform(0.4, 0.8)))
        if i % 2 == 0:
            items.append((t + 0.01, I.woodblock(900.0 + r.uniform(-80, 80), 0.4, i, 0.4), 0.25))
        t += r.uniform(0.035, 0.06)
        i += 1
    items.append((0.7, I.squeak(1300.0, 0.18, 0.6, 1, 3.0), 0.5))
    return place(1.0, items)


# ---------------------------------------------------------------- incidents

def c_frost_ting():
    n = ns(0.5)
    t = taxis(n)
    r = rng("frost")
    f0 = midi_hz(96)
    ting = modal(n, [(f0, 1.0, 0.6), (f0 * 2.76, 0.3, 0.2), (f0 * 5.4, 0.1, 0.08), (f0 * 1.0016, 0.6, 0.55)], r)
    choke = release_env(n, ns(0.36), 0.012)
    k = click(3500.0, 1.5, 0.008, "frostk", 0.0012)
    return place(0.62, [(0.0, ting * choke, 0.8), (0.38, k, 0.25)])


def c_steam_puff():
    s = sweep(0.6, [(0, 2600), (0.6, 1500)], 0.45, [(0, 0), (0.025, 1.0), (0.2, 0.6), (0.6, 0)], "steam", floor=0.02,
              lp=6500.0)
    return place(0.65, [(0.0, s, 0.8), (0.0, lp_noise(0.25, 500.0, [(0, 0), (0.02, 1.0), (0.25, 0)], "pff", 80.0), 0.25)])


def c_trip():
    return place(0.75, [(0.0, click(2200.0, 1.5, 0.012, "trip_click", 0.002), 0.5),
                        (0.02, thud(160.0, 0.1, "trip_t", 0.3, 600.0, 0.2, 0.03), 0.3),
                        (0.04, boing(300.0, 0.65, "trip_boing", 0.3, 12.0), 0.6)])


def c_trip_reset():
    bw = tone(0.25, [(0, 300), (0.25, 900)], [(0, 0), (0.03, 1.0), (0.25, 0)], ((1, 1.0), (2, 0.2)), seed="reset")
    n = ns(0.5)
    hum = tone(0.5, [(0, 120), (0.5, 120)], [(0, 0), (0.2, 0.6), (0.5, 0)], ((1, 1.0), (2, 0.4), (3, 0.15)), seed="rhum")
    return place(0.75, [(0.0, click(2400.0, 1.5, 0.012, "reset_click", 0.002), 0.5), (0.05, bw, 0.45),
                        (0.2, hum, 0.25), (0.28, I.celesta(89, 0.45, 0, 0.4), 0.25)])


def c_howl_note():
    return c_guest_moonwolf_quirk()


def c_overflow():
    tr = sweep(1.4, [(0, 1200), (0.7, 1700), (1.4, 1300)], 0.7, [(0, 0), (0.15, 0.6), (1.1, 0.5), (1.4, 0)], "trickle")
    return place(1.5, [(0.0, bubbles(1.35, 22, 220.0, 700.0, "burble", 0.7, (0.05, 0.11)), 0.6), (0.0, tr, 0.25)])


# ---------------------------------------------------------------- celebration / UI

def c_ui_move():
    return place(0.09, [(0.0, I.woodblock(1900.0, 0.4, 0, 0.0), 0.6),
                        (0.0, tone(0.05, [(0, 1320), (0.05, 1320)], [(0, 0), (0.003, 1.0), (0.05, 0)], seed="uimove"), 0.15)])


def c_ui_confirm():
    return place(0.45, [(0.0, I.marimba(84, 0.55, 0, 0.3), 0.6), (0.07, I.marimba(89, 0.62, 1, 0.35), 0.65),
                        (0.07, I.celesta(89, 0.35, 0, 0.3), 0.2)])


def c_ui_back():
    return place(0.4, [(0.0, I.marimba(77, 0.45, 0, 0.25), 0.6), (0.08, I.marimba(72, 0.42, 1, 0.3), 0.55)])


def c_ready():
    return place(0.8, [(0.0, mallets([(0.0, 81, 0.55), (0.06, 84, 0.6), (0.12, 89, 0.68)], "celesta"), 0.6),
                       (0.12, I.glock(89, 0.5, 0, 0.6), 0.3)])


def c_unready():
    return place(0.55, [(0.0, I.celesta(89, 0.42, 0, 0.3), 0.5), (0.1, I.celesta(84, 0.38, 1, 0.35), 0.45),
                        (0.0, I.marimba(77, 0.35, 0, 0.3), 0.3), (0.1, I.marimba(72, 0.32, 1, 0.3), 0.3)])


def c_photo_timer():
    items = []
    for i in range(3):
        beep = tone(0.13, [(0, 1046.5), (0.13, 1046.5)], [(0, 0), (0.008, 1.0), (0.08, 0.6), (0.13, 0)],
                    ((1, 1.0), (2, 0.08)), seed=f"pt{i}")
        items.append((float(i), beep, 0.6))
        items.append((float(i), I.marimba(84, 0.4, i, 0.2), 0.25))
    return place(2.25, items)


def c_photo_shutter():
    whirr = bp_noise(0.12, 3000.0, 0.8, [(0, 0), (0.02, 1.0), (0.12, 0)], "whirr", lo=900.0)
    return place(0.4, [(0.0, click(1800.0, 1.0, 0.015, "sh1", 0.0025), 0.6), (0.02, whirr, 0.15),
                       (0.075, click(2600.0, 1.0, 0.012, "sh2", 0.0018), 0.45),
                       (0.075, thud(220.0, 0.06, "shth", 0.3, 900.0, 0.1, 0.012), 0.15)])


def c_postcard():
    slide = rustle(0.5, "postcard", 260.0, 1500.0, 5500.0, [(0, 0), (0.1, 0.8), (0.4, 1.0), (0.5, 0)], grain=0.004)
    sw = sweep(0.5, [(0, 1500), (0.5, 3500)], 0.8, [(0, 0), (0.2, 0.8), (0.5, 0)], "pcsw")
    return place(0.65, [(0.0, slide, 0.45), (0.0, sw, 0.35), (0.5, I.woodblock(1400.0, 0.3, 0, 0.0), 0.15)])


def c_ribbon():
    n = ns(0.6)
    t = taxis(n)
    flt = bp_noise(0.6, 2200.0, 0.6, [(0, 0), (0.1, 1.0), (0.45, 0.7), (0.6, 0)], "ribbon", lo=500.0)
    flt *= 0.55 + 0.45 * np.abs(np.sin(np.pi * 31.0 * t))
    return place(1.0, [(0.0, flt, 0.5), (0.3, sparkle(0.7, "ribbon", 4, (93, 96, 101, 98), "celesta", 0.45, 0.25), 0.35)])


def c_unlock():
    return place(1.1, [(0.0, I.glock(89, 0.6, 0, 1.0), 0.45), (0.1, I.glock(93, 0.65, 1, 1.0), 0.45),
                       (0.2, I.celesta(96, 0.6, 0, 0.8), 0.35), (0.15, shimmer(0.8, "unlock"), 0.07)])


def _yay(f, seed, scale, delay):
    d = 0.42
    v = voice(d, [(0, f * 0.9), (0.12, f * 1.25), (d, f * 1.1)], [(0, "y"), (0.05, "ae"), (0.22, "ae"), (d, "i")],
              [(0, 0), (0.03, 1.0), (0.3, 0.8), (d, 0)], seed, scale=scale, breath=0.12)
    return (delay, v)


def c_cheer():
    voices = [_yay(300.0, "yay1", 1.12, 0.0), _yay(370.0, "yay2", 1.2, 0.035), _yay(250.0, "yay3", 1.02, 0.06),
              _yay(430.0, "yay4", 1.25, 0.02)]
    items = [(d, v, g) for (d, v), g in zip(voices, (0.5, 0.42, 0.45, 0.35))]
    items.append((0.25, rustle(0.75, "cheer_conf", 160.0, 1800.0, 7000.0, [(0, 0), (0.05, 1.0), (0.75, 0)]), 0.18))
    items.append((0.3, sparkle(0.7, "cheer", 4, (89, 93, 96, 101), "celesta", 0.4, 0.4), 0.2))
    return place(1.15, items)


def c_confetti():
    conf = rustle(0.95, "confetti", 240.0, 1800.0, 7000.0, [(0, 0), (0.04, 1.0), (0.3, 0.6), (0.95, 0)], grain=0.002)
    pops = place(0.4, [(0.0, bubble(700.0, 0.025, 2.0, "cp1"), 0.6), (0.06, bubble(900.0, 0.02, 2.0, "cp2"), 0.4)])
    return place(1.0, [(0.0, pops, 0.5), (0.02, conf, 0.5), (0.15, sparkle(0.7, "conf", 3, (96, 101, 105), "celesta", 0.35, 0.3), 0.2)])


def c_ping_help():
    # question shape: up a fourth
    return place(0.45, [(0.0, I.marimba(81, 0.55, 0, 0.25), 0.55), (0.09, I.marimba(86, 0.62, 1, 0.3), 0.6),
                        (0.09, I.celesta(86, 0.35, 0, 0.3), 0.25)])


def c_ping_bringing():
    # quick rising run: "on my way!"
    return place(0.5, [(0.0, mallets([(0.0, 84, 0.5), (0.05, 86, 0.55), (0.1, 89, 0.6), (0.15, 93, 0.62)], "marimba"), 0.6),
                       (0.0, sweep(0.22, [(0, 1200), (0.22, 3000)], 1.2, [(0, 0), (0.1, 1.0), (0.22, 0)], "bring"), 0.12)])


def c_ping_ready():
    # bright repeated note: "ready, ready!"
    return place(0.5, [(0.0, I.glock(89, 0.55, 0, 0.3), 0.5), (0.12, I.glock(89, 0.62, 1, 0.4), 0.55),
                       (0.0, I.marimba(77, 0.4, 0, 0.25), 0.25), (0.12, I.marimba(77, 0.42, 1, 0.3), 0.25)])


def c_ping_thanks():
    # warm falling third: "tha-nks"
    return place(0.6, [(0.0, I.felt_piano(81, 0.2, 0.55, 0, 0.2), 0.6), (0.14, I.felt_piano(77, 0.35, 0.5, 1, 0.3), 0.6),
                       (0.0, I.celesta(93, 0.3, 0, 0.3), 0.2), (0.14, I.celesta(89, 0.3, 1, 0.4), 0.2)])


def c_countdown_go():
    return place(1.0, [(0.0, mallets([(0.0, 77, 0.6), (0.01, 81, 0.6), (0.02, 84, 0.62), (0.03, 89, 0.7)], "glock"), 0.4),
                       (0.0, I.celesta(96, 0.55, 0, 0.6), 0.25), (0.0, shimmer(0.7, "go"), 0.06)])


# ======================================================================= voice syllables

SYLLABLES = [("b", "a", 0.11), ("d", "e", 0.10), ("l", "i", 0.095), ("m", "o", 0.13), ("n", "u", 0.12),
             ("w", "a", 0.14), ("y", "e", 0.11), ("h", "o", 0.12), ("p", "i", 0.09), ("l", "a", 0.12),
             ("m", "u", 0.13), ("n", "e", 0.105), ("b", "o", 0.12), ("d", "i", 0.09), ("w", "o", 0.14),
             ("y", "u", 0.12)]


def make_syllable(i):
    c, v, d = SYLLABLES[i]
    return syllable(c, v, d, 220.0, seed=f"syl{i + 1:02d}", scale=1.08)


# ======================================================================= registry

E, V, U = "Effects", "Voices", "UI"

CUES = {}


EXACT_LENGTH = {"guest_yeti_quirk_warn": 4.0, "guest_dragon_quirk_warn": 4.0, "guest_moonwolf_quirk_warn": 4.0}


def _reg(cid, bus, fn, target, loop=False):
    CUES[cid] = dict(bus=bus, fn=fn, target=target, loop=loop, length=EXACT_LENGTH.get(cid))


for _cid, _bus, _t in [
    ("pickup", E, -5.0), ("place", E, -5.0), ("handoff", E, -4.5), ("target_valid", E, -6.0),
    ("target_invalid", E, -6.0), ("work_start", E, -5.0), ("work_finish", E, -4.0), ("mop", E, -5.0),
    ("linen_fold", E, -5.0), ("curtain_swish", E, -5.0), ("watering", E, -5.0), ("fan", E, -5.0),
    ("footstep_1", E, -6.0), ("footstep_2", E, -6.0), ("footstep_3", E, -6.0), ("footstep_4", E, -6.0),
    ("quick_step", E, -5.5), ("wet_squeak", E, -5.0),
    ("arrival", E, -4.0), ("chime", E, -4.0), ("request_appear", E, -4.0), ("request_done", E, -4.0),
    ("request_late", E, -5.0), ("goodbye", E, -4.5), ("laundry_start", E, -5.0), ("laundry_done", E, -4.5),
    ("stock_refill", E, -5.0), ("gate", E, -5.0), ("thermostat", E, -5.0), ("pump_mode", E, -5.0),
    ("lift_depart", E, -4.5), ("lift_arrive", E, -4.5), ("shutter_warn", E, -4.5), ("shutter_close", E, -4.5),
    ("shutter_open", E, -4.5), ("bell_ring", E, -3.5), ("bell_hiccup", E, -3.5), ("trunk_open", E, -4.5),
    ("parcel_place", E, -5.0), ("gift_place", E, -4.5), ("ticket_assign", E, -5.0), ("bed_make", E, -5.0),
    ("bed_strip", E, -5.0), ("hamper", E, -5.0),
]:
    _reg(_cid, _bus, globals()["c_" + _cid], _t)
_reg("work_loop", E, c_work_loop, -6.0, loop=True)
_reg("trunk_drag", E, c_trunk_drag, -6.0, loop=True)

for _fam in ("slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"):
    for _kind in ("idle_1", "idle_2", "delight_1", "delight_2", "need_1", "need_2", "quirk_warn", "quirk",
                  "helper", "checkout"):
        _cid = f"guest_{_fam}_{_kind}"
        _t = -6.0 if _fam == "ghost" else (-4.5 if _kind in ("quirk", "quirk_warn") else -5.0)
        _reg(_cid, V, globals()["c_" + _cid], _t)

for _cid, _bus, _t in [("staff_effort", V, -5.0), ("staff_thanks", V, -5.0), ("staff_wave", V, -5.0),
                       ("nana_hmm", V, -5.0), ("nana_laugh", V, -5.0), ("dot_paper", E, -5.0),
                       ("dot_hmm", V, -5.0), ("gus_squeak", V, -5.0), ("gus_chirp", V, -5.0),
                       ("gus_rattle", E, -4.5),
                       ("frost_ting", E, -4.5), ("steam_puff", E, -5.0), ("trip", E, -4.5), ("trip_reset", E, -4.5),
                       ("howl_note", E, -4.0), ("overflow", E, -5.0),
                       ("ui_move", U, -8.0), ("ui_confirm", U, -8.0), ("ui_back", U, -8.0), ("ready", U, -8.0),
                       ("unready", U, -8.0), ("photo_timer", U, -8.0), ("photo_shutter", E, -5.0),
                       ("postcard", E, -5.0), ("ribbon", E, -5.0), ("unlock", E, -4.5), ("cheer", E, -4.5),
                       ("confetti", E, -5.0), ("ping_help", U, -8.0), ("ping_bringing", U, -8.0),
                       ("ping_ready", U, -8.0), ("ping_thanks", U, -8.0), ("countdown_go", U, -8.0),
                       # v2 verbs
                       ("counter_put", E, -5.0), ("counter_take", E, -5.0), ("temper", E, -4.5), ("vent", E, -4.5),
                       ("trunk_grab", E, -4.5), ("slip", E, -4.5), ("startle", E, -4.5),
                       ("order_served", E, -4.0), ("order_late", E, -5.0)]:
    _reg(_cid, _bus, globals()["c_" + _cid], _t)
