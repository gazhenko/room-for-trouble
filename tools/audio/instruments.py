"""Instrument voices: felt piano, marimba, woodblock, plucked strings
(Karplus-Strong), clarinet / flute lead lines, celesta, glockenspiel, glassy
bells, warm pad, soft bass and brushed percussion.

Every note function is a pure function of its (rounded) arguments; the random
source for a note is seeded from those arguments, so caching never changes
the output.  All functions return mono float64 arrays at dsp.SR.
"""

from __future__ import annotations

from functools import lru_cache

import numpy as np

from dsp import (SR, TAU, H_bp, H_hp, H_lp, H_peak, env_smooth, filt, midi_hz,
                 modal, ns, phase_of, ramp_in, release_env, rng, stft_shape,
                 taxis, karplus)


def _q(x, step):
    return round(float(x) / step) * step


# ------------------------------------------------------------- felt piano

@lru_cache(maxsize=6000)
def _felt_piano(midi: float, dur: float, vel: float, var: int, pedal: float) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("felt_piano", midi, dur, vel, var, pedal)
    rel_tau = 0.11 + pedal
    n = ns(dur + 6.0 * rel_tau + 0.02)
    t = taxis(n)
    B = 0.00032
    fc_hammer = 650.0 + 2100.0 * vel ** 1.3
    tau1 = float(np.clip(3.0 * (261.6 / f0) ** 0.62, 0.45, 6.5))
    out = np.zeros(n)
    norm = 0.0
    k = 1
    while True:
        fk = k * f0 * np.sqrt(1.0 + B * k * k)
        if fk > 9000.0 or k > 30:
            break
        a = (1.0 / k ** 0.85) / (1.0 + (fk / fc_hammer) ** 2)
        a *= 0.35 + 0.65 * abs(np.sin(np.pi * k / 7.7))     # strike position comb
        tk = tau1 / (1.0 + 0.045 * k * k * (f0 / 261.6) ** 0.25)
        e = 0.55 * np.exp(-t / (0.35 * tk)) + 0.45 * np.exp(-t / (1.7 * tk))
        det = 1.0 + r.uniform(0.25, 1.1) * 0.000578 * (1 if k < 9 else 0)
        s = np.sin(TAU * fk * t + r.uniform(0, TAU))
        if det != 1.0:
            s = 0.5 * (s + np.sin(TAU * fk * det * t + r.uniform(0, TAU)))
        out += a * e * s
        norm += a
        k += 1
    out /= max(norm, 1e-9)
    # felt "touch": a short low thump plus the faint key-bed knock
    thump_n = min(n, ns(0.03))
    th = r.standard_normal(thump_n) * np.exp(-taxis(thump_n) / 0.007)
    th = filt(th, lambda f: H_lp(f, 380.0 + 300.0 * vel) * H_hp(f, 60.0))[:thump_n]
    out[:thump_n] += th * 0.035 * vel
    att = ns(0.0085 - 0.005 * vel)
    out *= ramp_in(n, att)
    out *= release_env(n, ns(dur), rel_tau)
    return out * (0.25 + 0.75 * vel) ** 1.4


def felt_piano(midi, dur, vel=0.7, var=0, pedal=0.0):
    return _felt_piano(float(midi), _q(dur, 0.01), _q(vel, 0.04), int(var) % 4, _q(pedal, 0.05))


# ------------------------------------------------------------- marimba

@lru_cache(maxsize=4000)
def _marimba(midi: float, vel: float, var: int, dur: float) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("marimba", midi, vel, var, dur)
    tau = float(np.clip(0.85 * (261.6 / f0) ** 0.75, 0.16, 1.5))
    n = ns(min(dur, 6.0 * tau) + 0.05)
    modes = [(f0, 1.0, tau), (f0 * 3.98, 0.05 + 0.20 * vel, tau * 0.20),
             (f0 * 9.92, 0.04 * vel, tau * 0.07)]
    out = modal(n, modes, r, attack=0.0012)
    mal = min(n, ns(0.006))
    m = r.standard_normal(mal) * np.exp(-taxis(mal) / 0.0012)
    m = filt(m, lambda f: H_lp(f, 900.0 + 2500.0 * vel))[:mal]
    out[:mal] += m * 0.05 * vel
    if dur < 6.0 * tau:
        out *= release_env(n, ns(dur), 0.05)
    return out * (0.3 + 0.7 * vel) ** 1.3


def marimba(midi, vel=0.7, var=0, dur=4.0):
    return _marimba(float(midi), _q(vel, 0.04), int(var) % 4, _q(dur, 0.05))


# ------------------------------------------------------------- woodblock

@lru_cache(maxsize=400)
def _woodblock(freq: float, vel: float, var: int, tone: float) -> np.ndarray:
    r = rng("woodblock", freq, vel, var, tone)
    f = freq * (1.0 + r.uniform(-0.008, 0.008))
    n = ns(0.16 + 0.1 * tone)
    modes = [(f, 1.0, 0.040 + 0.035 * tone), (f * 2.13, 0.32, 0.022 + 0.01 * tone),
             (f * 3.61, 0.12, 0.012)]
    out = modal(n, modes, r, attack=0.0006)
    cl = ns(0.003)
    c = r.standard_normal(cl) * np.exp(-taxis(cl) / 0.0007)
    c = filt(c, lambda fr: H_bp(fr, 2600.0, 0.7))[:cl]
    out[:cl] += c * 0.25
    return out * (0.3 + 0.7 * vel) ** 1.2


def woodblock(freq, vel=0.7, var=0, tone=0.0):
    return _woodblock(_q(freq, 1.0), _q(vel, 0.04), int(var) % 4, _q(tone, 0.1))


# ------------------------------------------------------------- plucked string

@lru_cache(maxsize=4000)
def _pluck(midi: float, dur: float, vel: float, var: int, t60: float, bright: float,
           body: float) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("pluck", midi, dur, vel, var, t60, bright)
    ring = min(dur + 0.12, t60 * 0.9)
    y = karplus(f0, ring + 0.15, r, t60=t60, bright=bright * (0.6 + 0.4 * vel))
    y = filt(y, lambda f: H_lp(f, 2200.0 + 5000.0 * bright * vel, 0.6)
             * H_peak(f, 240.0, 1.0, 3.0 * body) * H_hp(f, 70.0))[: len(y)]
    n = len(y)
    y *= ramp_in(n, ns(0.0015))
    y *= release_env(n, ns(min(dur + 0.03, ring)), 0.045)
    y /= (np.max(np.abs(y[: ns(0.05)])) + 1e-9)
    return y * (0.3 + 0.7 * vel) ** 1.3


def pluck(midi, dur, vel=0.7, var=0, t60=1.8, bright=0.5, body=1.0):
    return _pluck(float(midi), _q(dur, 0.01), _q(vel, 0.04), int(var) % 4,
                  _q(t60, 0.1), _q(bright, 0.05), _q(body, 0.1))


# ------------------------------------------------------------- celesta / bells

@lru_cache(maxsize=3000)
def _celesta(midi: float, vel: float, var: int, dur: float) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("celesta", midi, vel, var, dur)
    tau = float(np.clip(1.35 * (523.3 / f0) ** 0.55, 0.35, 2.4))
    n = ns(min(dur, 5.0 * tau) + 0.05)
    modes = [(f0, 1.0, tau), (f0 * 2.0, 0.10, tau * 0.35), (f0 * 3.0, 0.035, tau * 0.2),
             (f0 * 4.03, 0.06 + 0.12 * vel, 0.09), (f0 * 9.7, 0.03 * vel, 0.025)]
    out = modal(n, modes, r, attack=0.0009)
    tk = ns(0.004)
    tink = r.standard_normal(tk) * np.exp(-taxis(tk) / 0.0009)
    tink = filt(tink, lambda f: H_hp(f, 5000.0) * H_lp(f, 11000.0))[:tk]
    out[:tk] += tink * 0.03 * vel
    if dur < 5.0 * tau:
        out *= release_env(n, ns(dur), 0.12)
    return out * (0.3 + 0.7 * vel) ** 1.3


def celesta(midi, vel=0.7, var=0, dur=8.0):
    return _celesta(float(midi), _q(vel, 0.04), int(var) % 4, _q(dur, 0.05))


@lru_cache(maxsize=3000)
def _glock(midi: float, vel: float, var: int, dur: float) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("glock", midi, vel, var, dur)
    tau = float(np.clip(2.0 * (784.0 / f0) ** 0.45, 0.7, 3.0))
    n = ns(min(dur, 4.5 * tau) + 0.05)
    soft = 0.5 + 0.5 * vel
    modes = [(f0, 1.0, tau), (f0 * 2.756, 0.20 * soft, tau * 0.30),
             (f0 * 5.404, 0.07 * soft, tau * 0.12), (f0 * 8.933, 0.025 * soft, tau * 0.06)]
    out = modal(n, modes, r, attack=0.0008)
    if dur < 4.5 * tau:
        out *= release_env(n, ns(dur), 0.15)
    return out * (0.3 + 0.7 * vel) ** 1.3


def glock(midi, vel=0.7, var=0, dur=8.0):
    return _glock(float(midi), _q(vel, 0.04), int(var) % 4, _q(dur, 0.05))


@lru_cache(maxsize=3000)
def _glass(midi: float, vel: float, var: int, dur: float) -> np.ndarray:
    """Cool, glassy bell: near-harmonic body with a high inharmonic shimmer."""
    f0 = midi_hz(midi)
    r = rng("glass", midi, vel, var, dur)
    tau = float(np.clip(2.2 * (659.0 / f0) ** 0.4, 0.8, 3.2))
    n = ns(min(dur, 4.5 * tau) + 0.05)
    base = [(1.0, 1.0, tau), (2.0, 0.16, tau * 0.45), (3.0, 0.06, tau * 0.3),
            (5.33, 0.07 * (0.5 + vel), tau * 0.14), (8.08, 0.025 * vel, tau * 0.07)]
    modes = []
    for ratio, a, tt in base:
        modes.append((f0 * ratio, a * 0.5, tt))
        modes.append((f0 * ratio * (1.0 + 0.0011), a * 0.5, tt))   # slow shimmer beat
    out = modal(n, modes, r, attack=0.0015)
    if dur < 4.5 * tau:
        out *= release_env(n, ns(dur), 0.2)
    return out * (0.3 + 0.7 * vel) ** 1.3


def glass(midi, vel=0.7, var=0, dur=8.0):
    return _glass(float(midi), _q(vel, 0.04), int(var) % 4, _q(dur, 0.05))


@lru_cache(maxsize=600)
def _desk_bell(midi: float, vel: float, var: int) -> np.ndarray:
    """Lobby desk ('service') bell tuned so its strike tone sits on `midi`."""
    f0 = midi_hz(midi)
    r = rng("desk_bell", midi, vel, var)
    n = ns(2.6)
    modes = [(f0, 1.0, 1.25), (f0 * 2.0, 0.28, 0.7), (f0 * 2.92, 0.16, 0.45),
             (f0 * 4.16, 0.10, 0.25), (f0 * 5.43, 0.05, 0.14), (f0 * 0.5, 0.05, 0.9)]
    m2 = []
    for fr, a, tt in modes:
        m2.append((fr, a * 0.55, tt))
        m2.append((fr * 1.0019, a * 0.45, tt * 0.9))
    out = modal(n, m2, r, attack=0.0006)
    cl = ns(0.004)
    c = r.standard_normal(cl) * np.exp(-taxis(cl) / 0.0008)
    c = filt(c, lambda f: H_bp(f, 4500.0, 0.8))[:cl]
    out[:cl] += c * 0.08 * vel
    return out * (0.3 + 0.7 * vel) ** 1.2


def desk_bell(midi, vel=0.8, var=0):
    return _desk_bell(float(midi), _q(vel, 0.04), int(var) % 4)


# ------------------------------------------------------------- pad

@lru_cache(maxsize=3000)
def _pad(midi: float, dur: float, vel: float, var: int, kind: str, att: float,
         rel: float) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("pad", midi, dur, vel, var, kind)
    n = ns(dur + rel * 4.0 + 0.05)
    t = taxis(n)
    out = np.zeros(n)
    if kind == "airy":
        cut, slope, cents = 1100.0, 2.0, (-5.0, 0.0, 5.5)
    elif kind == "glass":
        cut, slope, cents = 2200.0, 1.7, (-7.0, 0.0, 7.0)
    else:  # warm
        cut, slope, cents = 1500.0, 1.55, (-6.0, 0.0, 6.5)
    for vi, c in enumerate(cents):
        drift = 2.2 * np.sin(TAU * r.uniform(0.07, 0.19) * t + r.uniform(0, TAU))
        fr = f0 * 2.0 ** ((c + drift) / 1200.0)
        ph = phase_of(fr)
        k = 1
        while k * f0 < min(5000.0, 0.4 * SR) and k <= 32:
            a = (1.0 / k ** slope) / (1.0 + (k * f0 / cut) ** 2)
            out += a * np.sin(k * ph + r.uniform(0, TAU))
            k += 1
    norm = sum((1.0 / k ** slope) / (1.0 + (k * f0 / cut) ** 2) for k in range(1, 33)
               if k * f0 < 5000.0)
    out /= (norm * len(cents) * 0.75)
    if kind == "airy":
        b = r.standard_normal(n)
        b = filt(b, lambda f: H_bp(f, min(4.0 * f0, 6000.0), 0.9))[:n]
        out += b * 0.012
    shimmer = 1.0 + 0.05 * np.sin(TAU * r.uniform(0.17, 0.31) * t + r.uniform(0, TAU))
    e = np.ones(n)
    a_n = min(n, ns(att))
    e[:a_n] = (0.5 - 0.5 * np.cos(np.pi * np.arange(a_n) / max(a_n, 1)))
    e *= release_env(n, ns(dur), rel)
    return out * e * shimmer * (0.3 + 0.7 * vel)


def pad(midi, dur, vel=0.6, var=0, kind="warm", att=0.45, rel=0.6):
    return _pad(float(midi), _q(dur, 0.02), _q(vel, 0.04), int(var) % 3, kind,
                _q(att, 0.05), _q(rel, 0.05))


# ------------------------------------------------------------- bass

@lru_cache(maxsize=3000)
def _bass(midi: float, dur: float, vel: float, var: int, style: str) -> np.ndarray:
    f0 = midi_hz(midi)
    r = rng("bass", midi, dur, vel, var, style)
    rel = 0.05 if style == "bouncy" else 0.08
    n = ns(dur + 6 * rel + 0.03)
    t = taxis(n)
    if style == "bouncy":
        fr = f0 * 2.0 ** ((0.35 * np.exp(-t / 0.025)) / 12.0)
        tau1 = 0.55
    else:
        fr = np.full(n, f0)
        tau1 = 1.3
    ph = phase_of(fr)
    out = np.zeros(n)
    norm = 0.0
    for k in range(1, 9):
        if k * f0 > 2500:
            break
        a = (1.0 / k ** 1.25) / (1.0 + (k * f0 / (520.0 + 500.0 * vel)) ** 2)
        tk = tau1 / (1.0 + 0.55 * (k - 1))
        out += a * (0.4 + 0.6 * np.exp(-t / tk)) * np.sin(k * ph + r.uniform(0, 0.4))
        norm += a
    out /= norm
    th_n = min(n, ns(0.025))
    th = r.standard_normal(th_n) * np.exp(-taxis(th_n) / 0.006)
    th = filt(th, lambda f: H_lp(f, 260.0))[:th_n]
    out[:th_n] += th * 0.06 * vel
    out *= ramp_in(n, ns(0.004 if style == "bouncy" else 0.007))
    out *= release_env(n, ns(dur), rel)
    return out * (0.35 + 0.65 * vel)


def bass(midi, dur, vel=0.7, var=0, style="round"):
    return _bass(float(midi), _q(dur, 0.01), _q(vel, 0.04), int(var) % 4, style)


# ------------------------------------------------------------- lead lines

LEAD_SPECTRA = {
    # clarinet: odd harmonics dominate, even ones whisper
    "clarinet": {1: 1.0, 2: 0.035, 3: 0.52, 4: 0.03, 5: 0.28, 6: 0.028, 7: 0.15, 8: 0.022,
                 9: 0.085, 10: 0.018, 11: 0.045, 12: 0.012, 13: 0.025, 15: 0.012},
    "flute": {1: 1.0, 2: 0.24, 3: 0.075, 4: 0.03, 5: 0.012},
    "whistle": {1: 1.0, 2: 0.05, 3: 0.012},
}


def render_lead(notes, inst: str = "clarinet", seed: str = "lead", total: float | None = None,
                vib_cents: float = 9.0, attack: float = 0.06, release: float = 0.09,
                breath: float = 0.012, glide: float = 0.04, cutoff: float = 2600.0) -> np.ndarray:
    """Render a monophonic legato line.

    notes: list of (start_s, dur_s, midi, vel).  Notes closer than 25 ms are
    joined legato (pitch glide, softened re-articulation, no new attack).
    """
    notes = sorted(notes)
    r = rng("lead", inst, seed)
    end = max(s + d for s, d, _, _ in notes)
    n = ns(max(total or 0.0, end + release * 8 + 0.1))
    t = taxis(n)
    # legato phrases
    phrases, cur = [], []
    for nt in notes:
        if cur and nt[0] - (cur[-1][0] + cur[-1][1]) > 0.025:
            phrases.append(cur)
            cur = []
        cur.append(nt)
    phrases.append(cur)
    flat = [nt for ph in phrases for nt in ph]
    onsets = [ns(nt[0]) for nt in flat]
    freq = np.full(n, midi_hz(flat[0][2]))
    amp = np.zeros(n)
    vib = np.zeros(n)
    first_of_phrase = {id(ph[0]) for ph in phrases}
    prev_f = None
    for i, (s, d, m, v) in enumerate(flat):
        a = onsets[i]
        b = onsets[i + 1] if i + 1 < len(flat) else n
        f = midi_hz(m)
        seg = np.full(max(b - a, 0), f)
        if prev_f is not None and id(flat[i]) not in first_of_phrase and len(seg):
            g = min(len(seg), ns(glide))
            u = 0.5 - 0.5 * np.cos(np.pi * np.arange(g) / max(g, 1))
            seg[:g] = prev_f * (f / prev_f) ** u
        freq[a:b] = seg
        amp[a:b] = v
        if d > 0.28:
            e_n = min(b, ns(s + d + 0.3)) - a
            lt = np.arange(e_n) / SR
            depth = np.clip((lt - 0.22) / 0.35, 0.0, 1.0) * vib_cents
            vib[a:a + e_n] = depth * np.sin(TAU * r.uniform(4.8, 5.6) * lt + r.uniform(0, TAU))
        prev_f = f
    ksz = ns(0.03)
    amp = np.convolve(amp, np.ones(ksz) / ksz, mode="same")
    env = np.zeros(n)
    an = max(1, ns(attack))
    for ph in phrases:
        p0 = ns(ph[0][0])
        p1 = ns(ph[-1][0] + ph[-1][1])
        q1 = min(n, p1 + ns(release * 9))
        k = np.arange(q1 - p0)
        on = 0.5 - 0.5 * np.cos(np.pi * np.clip(k / an, 0, 1))
        off = np.where(k >= p1 - p0, np.exp(-(k - (p1 - p0)) / (release * SR)), 1.0)
        env[p0:q1] = np.maximum(env[p0:q1], on * off)
        for nt in ph[1:]:
            c = ns(nt[0])
            w = ns(0.03)
            lo, hi = max(0, c - w), min(n, c + w)
            env[lo:hi] *= 0.86 + 0.14 * np.abs(np.arange(lo, hi) - c) / w
    total_env = env * amp
    f_inst = freq * 2.0 ** (vib / 1200.0)
    phase = phase_of(f_inst)
    spec = LEAD_SPECTRA[inst]
    out = np.zeros(n)
    fmax = float(np.max(f_inst))
    norm = 0.0
    envc = np.clip(env, 1e-4, 1.0)
    for k, a in spec.items():
        if k * fmax > 12000:
            continue
        lp = 1.0 / (1.0 + (k * f_inst / cutoff) ** 2)
        bright = envc ** (0.09 * (k - 1)) if k > 1 else 1.0
        out += a * lp * bright * np.sin(k * phase + r.uniform(0, TAU))
        norm += a / (1.0 + (k * 440.0 / cutoff) ** 2)
    out = out / norm * total_env
    if inst == "flute":
        out *= 1.0 + 0.05 * np.sin(TAU * 5.1 * t)
    if breath > 0:
        b = r.standard_normal(n)
        if inst == "clarinet":
            b = filt(b, lambda f: H_bp(f, 1900.0, 0.8))[:n]
        else:
            b = filt(b, lambda f: H_bp(f, 2600.0, 0.6) + 0.5 * H_bp(f, 900.0, 1.0))[:n]
        b /= np.std(b) + 1e-12
        out += b * breath * total_env * (0.6 + 0.4 * np.clip(1.0 - env, 0, 1))
    if inst in ("flute", "whistle"):
        for ph in phrases:
            p0 = ns(ph[0][0])
            cn = min(ns(0.05), n - p0)
            if cn > 0:
                c = r.standard_normal(cn) * np.exp(-taxis(cn) / 0.012)
                c = filt(c, lambda f: H_bp(f, 2.0 * midi_hz(ph[0][2]), 1.5))[:cn]
                out[p0:p0 + cn] += c * 0.05 * ph[0][3]
    return out


# ------------------------------------------------------------- percussion

@lru_cache(maxsize=200)
def _brush_tap(vel: float, var: int) -> np.ndarray:
    r = rng("brush_tap", vel, var)
    n = ns(0.22)
    t = taxis(n)
    x = r.standard_normal(n)
    e = 0.75 * np.exp(-t / 0.022) + 0.25 * np.exp(-t / 0.075)
    y = filt(x * e, lambda f: H_bp(f, 3300.0 + 300 * var, 0.55) * H_hp(f, 700.0))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    body = np.sin(TAU * 185.0 * t) * np.exp(-t / 0.03) * 0.12
    out = (y + body) * ramp_in(n, ns(0.0015))
    return out * (0.25 + 0.75 * vel) ** 1.4


def brush_tap(vel=0.6, var=0):
    return _brush_tap(_q(vel, 0.04), int(var) % 4)


@lru_cache(maxsize=200)
def _brush_swell(dur: float, vel: float, var: int) -> np.ndarray:
    """Filtered-noise swell: a brush stirring into the next beat."""
    r = rng("brush_swell", dur, vel, var)
    n = ns(dur + 0.06)
    x = r.standard_normal(n)
    d = dur

    def g(t, f):
        u = np.clip(t / d, 0.0, 1.0)
        fc = 1700.0 + 2600.0 * u
        bw = 0.9
        lo = (f / fc) ** 2
        return (lo / (1.0 + lo)) / (1.0 + (f / (fc * (1.0 + bw))) ** 2)

    y = stft_shape(x, g)
    u = np.clip(taxis(n) / d, 0, 1.2)
    e = np.where(u <= 1.0, u ** 1.8, np.exp(-(u - 1.0) * d / 0.025))
    y *= e
    y /= np.max(np.abs(y)) + 1e-9
    return y * (0.25 + 0.75 * vel) ** 1.4


def brush_swell(dur, vel=0.5, var=0):
    return _brush_swell(_q(dur, 0.01), _q(vel, 0.04), int(var) % 4)


@lru_cache(maxsize=200)
def _shaker(vel: float, var: int, length: float) -> np.ndarray:
    r = rng("shaker", vel, var, length)
    n = ns(length + 0.03)
    t = taxis(n)
    x = r.standard_normal(n)
    grains = (r.uniform(0, 1, n) > 0.55).astype(float)
    grains = np.convolve(grains, np.ones(18) / 18.0, mode="same")
    att = length * 0.3
    e = np.where(t < att, (t / att) ** 1.5, np.exp(-(t - att) / (length * 0.35)))
    y = filt(x * (0.4 + 0.6 * grains) * e,
             lambda f: H_hp(f, 4200.0) * H_lp(f, 11000.0) * H_peak(f, 7200.0, 1.0, 3.0))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    return y * (0.2 + 0.8 * vel) ** 1.5


def shaker(vel=0.5, var=0, length=0.09):
    return _shaker(_q(vel, 0.04), int(var) % 4, _q(length, 0.01))


@lru_cache(maxsize=100)
def _soft_kick(vel: float, var: int) -> np.ndarray:
    r = rng("soft_kick", vel, var)
    n = ns(0.45)
    t = taxis(n)
    f = 52.0 + 55.0 * np.exp(-t / 0.028)
    y = np.sin(phase_of(f)) * np.exp(-t / 0.17)
    b = r.standard_normal(n) * np.exp(-t / 0.006)
    b = filt(b, lambda fr: H_lp(fr, 700.0))[:n]
    y = (y + 0.12 * b) * ramp_in(n, ns(0.002))
    return y * (0.3 + 0.7 * vel) ** 1.3


def soft_kick(vel=0.6, var=0):
    return _soft_kick(_q(vel, 0.04), int(var) % 3)


@lru_cache(maxsize=100)
def _tambourine(vel: float, var: int) -> np.ndarray:
    r = rng("tamb", vel, var)
    n = ns(0.3)
    t = taxis(n)
    out = np.zeros(n)
    for j, dt in enumerate([0.0, 0.007, 0.016]):
        k = ns(dt)
        m = n - k
        x = r.standard_normal(m) * np.exp(-taxis(m) / 0.07) * (1.0 - 0.3 * j)
        out[k:] += x
    out = filt(out, lambda f: H_hp(f, 5500.0) * (H_bp(f, 7600.0, 4.0) + H_bp(f, 9900.0, 4.0)
                                                 + 0.4 * H_bp(f, 12400.0, 3.0)))[:n]
    out /= np.max(np.abs(out)) + 1e-9
    return out * ramp_in(n, ns(0.001)) * (0.2 + 0.8 * vel) ** 1.5


def tambourine(vel=0.5, var=0):
    return _tambourine(_q(vel, 0.04), int(var) % 3)


@lru_cache(maxsize=100)
def _clap(vel: float, var: int) -> np.ndarray:
    r = rng("clap", vel, var)
    n = ns(0.25)
    out = np.zeros(n)
    for j, dt in enumerate([0.0, 0.009, 0.019, 0.026]):
        k = ns(dt + r.uniform(0, 0.002))
        m = n - k
        tau = 0.004 if j < 3 else 0.05
        out[k:] += r.standard_normal(m) * np.exp(-taxis(m) / tau) * (0.8 if j < 3 else 0.6)
    out = filt(out, lambda f: H_bp(f, 1350.0, 0.9) * H_hp(f, 400.0))[:n]
    out /= np.max(np.abs(out)) + 1e-9
    return out * ramp_in(n, ns(0.001)) * (0.2 + 0.8 * vel) ** 1.5


def clap(vel=0.5, var=0):
    return _clap(_q(vel, 0.04), int(var) % 4)


@lru_cache(maxsize=100)
def _squeak(freq: float, dur: float, vel: float, var: int, up: float) -> np.ndarray:
    """Little suitcase-hinge squeak: rubbery glide with stick-slip grain."""
    r = rng("squeak", freq, dur, vel, var, up)
    n = ns(dur)
    t = taxis(n)
    u = t / dur
    f = freq * 2.0 ** ((up * (u - 0.3) + 0.25 * np.sin(np.pi * u)) / 12.0)
    f = f * (1.0 + 0.012 * np.sin(TAU * 38.0 * t))
    ph = phase_of(f)
    y = np.sin(ph) + 0.35 * np.sin(2 * ph + 0.3) + 0.12 * np.sin(3 * ph + 1.0)
    slip = 0.75 + 0.25 * np.sin(TAU * r.uniform(52.0, 64.0) * t) ** 2
    e = np.sin(np.pi * np.clip(u, 0, 1)) ** 0.8
    y = y * slip * e
    y = filt(y, lambda fr: H_lp(fr, 5000.0) * H_hp(fr, 300.0))[:n]
    y /= np.max(np.abs(y)) + 1e-9
    return y * (0.3 + 0.7 * vel)


def squeak(freq, dur=0.16, vel=0.6, var=0, up=2.0):
    return _squeak(_q(freq, 0.5), _q(dur, 0.01), _q(vel, 0.04), int(var) % 3, _q(up, 0.25))
