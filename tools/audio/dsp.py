"""Core DSP helpers for the Room for Trouble audio generator.

Everything here is plain numpy and fully deterministic: every random source is
seeded from a stable CRC32 of a descriptive name (never Python's hash()).

Conventions
-----------
* Sample rate is 44.1 kHz.  Mono signals are 1-D float64 arrays; stereo
  signals are shaped (2, n).
* Static filters are applied in the frequency domain using analog (s-plane)
  prototype responses evaluated on the FFT grid.  The responses are causal and
  smooth, so there is no pre-ringing to speak of.  With ``circular=True`` the
  filtering wraps around the end of the buffer, which is exactly what a
  seamless loop needs.
* Time-varying filters use an STFT (Hann, 75 % overlap) gain mask.
"""

from __future__ import annotations

import struct
import zlib

import numpy as np

SR = 44100
TAU = 2.0 * np.pi


# ---------------------------------------------------------------- utilities

def seed_of(*parts) -> int:
    return zlib.crc32("|".join(repr(p) for p in parts).encode("utf-8"))


def rng(*parts) -> np.random.Generator:
    return np.random.default_rng(seed_of(*parts))


def db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-12))


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def ns(sec: float) -> int:
    return int(round(sec * SR))


def taxis(n: int) -> np.ndarray:
    return np.arange(n) / SR


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if x.size else 0.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if x.shape[-1] >= n:
        return x[..., :n]
    pad = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
    return np.pad(x, pad)


def next_fast(n: int) -> int:
    """Smallest 2^a * 3^b * 5^c >= n (fast pocketfft size)."""
    best = 1 << (int(n - 1).bit_length())
    p5 = 1
    while p5 < best:
        p35 = p5
        while p35 < best:
            p = p35
            while p < n:
                p *= 2
            if p < best:
                best = p
            p35 *= 3
        p5 *= 5
    return best


# ---------------------------------------------------------------- envelopes

def env_points(points, n: int) -> np.ndarray:
    """Piecewise-linear envelope from (time_s, value) breakpoints."""
    ts = np.array([p[0] for p in points], dtype=float)
    vs = np.array([p[1] for p in points], dtype=float)
    return np.interp(taxis(n), ts, vs)


def env_smooth(points, n: int) -> np.ndarray:
    """Like env_points but each segment is raised-cosine shaped (no corners)."""
    t = taxis(n)
    ts = np.array([p[0] for p in points], dtype=float)
    vs = np.array([p[1] for p in points], dtype=float)
    idx = np.clip(np.searchsorted(ts, t, side="right") - 1, 0, len(ts) - 2)
    t0, t1 = ts[idx], ts[idx + 1]
    v0, v1 = vs[idx], vs[idx + 1]
    span = np.maximum(t1 - t0, 1e-9)
    u = np.clip((t - t0) / span, 0.0, 1.0)
    u = 0.5 - 0.5 * np.cos(np.pi * u)
    out = v0 + (v1 - v0) * u
    out[t < ts[0]] = vs[0]
    out[t >= ts[-1]] = vs[-1]
    return out


def ramp_in(n_total: int, n_ramp: int) -> np.ndarray:
    e = np.ones(n_total)
    n_ramp = min(n_ramp, n_total)
    if n_ramp > 0:
        e[:n_ramp] = 0.5 - 0.5 * np.cos(np.pi * np.arange(n_ramp) / n_ramp)
    return e


def fade(x: np.ndarray, fin: float = 0.003, fout: float = 0.003) -> np.ndarray:
    """Raised-cosine fade in/out (seconds) along the last axis."""
    y = np.array(x, dtype=float, copy=True)
    n = y.shape[-1]
    a = min(n, max(1, ns(fin)))
    b = min(n, max(1, ns(fout)))
    y[..., :a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    y[..., n - b:] *= 0.5 + 0.5 * np.cos(np.pi * (np.arange(b) + 1) / b)
    return y


def release_env(n: int, start: int, tau: float) -> np.ndarray:
    """1 until `start`, then a smooth exponential release with time constant tau."""
    e = np.ones(n)
    if start < n:
        k = np.arange(n - start) / SR
        # short raised-cosine knee into the exponential to avoid a corner
        knee = min(len(k), ns(0.004))
        r = np.exp(-k / max(tau, 1e-4))
        if knee > 1:
            w = 0.5 - 0.5 * np.cos(np.pi * np.arange(knee) / knee)
            r[:knee] = (1 - w) * 1.0 + w * r[:knee]
        e[start:] = r
    return e


# ---------------------------------------------------------------- filters

def _s(f, fc):
    return 1j * np.asarray(f, dtype=float) / float(fc)


def H_lp(f, fc, q=0.7071):
    s = _s(f, fc)
    return 1.0 / (s * s + s / q + 1.0)


def H_hp(f, fc, q=0.7071):
    s = _s(f, fc)
    return (s * s) / (s * s + s / q + 1.0)


def H_bp(f, fc, q=1.0):
    """Band-pass with unity gain at fc."""
    s = _s(f, fc)
    return (s / q) / (s * s + s / q + 1.0)


def H_lp1(f, fc):
    return 1.0 / (1.0 + _s(f, fc))


def H_hp1(f, fc):
    s = _s(f, fc)
    return s / (1.0 + s)


def H_peak(f, fc, q, gain_db):
    a = 10.0 ** (gain_db / 40.0)
    s = _s(f, fc)
    return (s * s + s * (a / q) + 1.0) / (s * s + s / (a * q) + 1.0)


def H_lowshelf(f, fc, gain_db, q=0.7071):
    a = 10.0 ** (gain_db / 40.0)
    s = _s(f, fc)
    sa = np.sqrt(a)
    return a * (s * s + (sa / q) * s + a) / (a * s * s + (sa / q) * s + 1.0)


def H_highshelf(f, fc, gain_db, q=0.7071):
    a = 10.0 ** (gain_db / 40.0)
    s = _s(f, fc)
    sa = np.sqrt(a)
    return a * (a * s * s + (sa / q) * s + 1.0) / (s * s + (sa / q) * s + a)


def filt(x: np.ndarray, H, circular: bool = False, tail: float = 0.0) -> np.ndarray:
    """Apply a frequency response callable H(freqs) along the last axis.

    circular=True wraps the filter's ringing around the buffer (loops).
    tail (seconds) extends a non-circular result so ringing is kept.
    """
    x = np.asarray(x, dtype=float)
    n = x.shape[-1]
    if circular:
        nfft = n
    else:
        nfft = next_fast(n + ns(tail) + ns(0.25))
    X = np.fft.rfft(x, n=nfft, axis=-1)
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    y = np.fft.irfft(X * H(f), n=nfft, axis=-1)
    out_n = n if circular else n + ns(tail)
    return y[..., :out_n]


def dc_block(x, fc=22.0, circular=False):
    return filt(x, lambda f: H_hp(f, fc, 0.7071), circular=circular)


def stft_shape(x: np.ndarray, gain_fn, n_fft: int = 1024, hop: int = 256) -> np.ndarray:
    """Time-varying zero-phase filtering of a mono signal.

    gain_fn(t, f) receives frame-centre times (F,1) and bin frequencies (1,B)
    and returns a broadcastable real gain matrix.
    """
    x = np.asarray(x, dtype=float)
    n = len(x)
    pad = n_fft
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + n_fft)])
    win = 0.5 - 0.5 * np.cos(TAU * np.arange(n_fft) / n_fft)
    n_frames = 1 + (len(xp) - n_fft) // hop
    idx = np.arange(n_fft)[None, :] + hop * np.arange(n_frames)[:, None]
    X = np.fft.rfft(xp[idx] * win, axis=1)
    t = ((hop * np.arange(n_frames) + n_fft / 2 - pad) / SR)[:, None]
    f = np.fft.rfftfreq(n_fft, 1.0 / SR)[None, :]
    G = np.broadcast_to(gain_fn(t, f), X.shape)
    Y = np.fft.irfft(X * G, n=n_fft, axis=1) * win
    out = np.zeros(len(xp))
    # overlap-add, vectorised per hop-phase (frames in one phase never overlap)
    step = n_fft // hop
    for r in range(step):
        fr = Y[r::step]
        if len(fr) == 0:
            continue
        start = r * hop
        flat = fr.reshape(-1)
        m = min(len(flat), len(out) - start)
        out[start:start + m] += flat[:m]
    norm = np.sum(win ** 2) / hop
    return out[pad:pad + n] / norm


def noise(n: int, r: np.random.Generator) -> np.ndarray:
    return r.standard_normal(n)


def band_noise(n: int, r, lo=None, hi=None, q=0.7071, circular=False) -> np.ndarray:
    x = r.standard_normal(n)

    def H(f):
        h = np.ones_like(f, dtype=complex)
        if lo:
            h = h * H_hp(f, lo, q)
        if hi:
            h = h * H_lp(f, hi, q)
        return h

    y = filt(x, H, circular=circular)
    return y / (rms(y) + 1e-12)


# ---------------------------------------------------------------- oscillators

def phase_of(freq) -> np.ndarray:
    """Running phase (radians) of an instantaneous-frequency array."""
    return TAU * np.cumsum(freq) / SR


def additive(phase: np.ndarray, partials, f0max: float, amp_env=None, rnd=None,
             limit: float = 15000.0) -> np.ndarray:
    """Sum of harmonics sin(k*phase) with amplitudes; partials = [(k, a), ...]."""
    out = np.zeros_like(phase)
    for k, a in partials:
        if k * f0max > limit or a == 0:
            continue
        ph = rnd.uniform(0, TAU) if rnd is not None else 0.0
        out += a * np.sin(k * phase + ph)
    if amp_env is not None:
        out *= amp_env
    return out


def modal(n: int, modes, r=None, attack: float = 0.0008) -> np.ndarray:
    """Sum of exponentially decaying sinusoids: modes = [(freq, amp, tau), ...]."""
    t = taxis(n)
    out = np.zeros(n)
    for fr, a, tau in modes:
        if fr >= 0.45 * SR or a == 0:
            continue
        ph = r.uniform(0, TAU) if r is not None else 0.0
        out += a * np.exp(-t / tau) * np.sin(TAU * fr * t + ph)
    return out * ramp_in(n, ns(attack))


# ---------------------------------------------------------------- Karplus-Strong

def karplus(freq: float, dur: float, r: np.random.Generator, t60: float = 2.0,
            bright: float = 0.5, pick_pos: float = 0.18) -> np.ndarray:
    """Vectorised Karplus-Strong plucked string.

    The loop y[n] = g*(y[n-N] + y[n-N-1])/2 is evaluated one period (N samples)
    at a time.  The 2-tap average adds half a sample of delay, so the period
    is N + 0.5; the result is then resampled so the pitch is exact.
    """
    period = SR / freq
    N = max(2, int(np.floor(period - 0.5)))
    eff = N + 0.5
    n_out = ns(dur)
    n_gen = int(np.ceil(n_out * eff / period)) + 2 * N + 4
    nblocks = n_gen // N + 2
    g = 0.001 ** (1.0 / (freq * t60))
    # excitation: soft, low-passed noise with a pick-position comb
    exc = r.uniform(-1, 1, N)
    k = max(1, int(round((1.0 - bright) * 6)) + 1)
    if k > 1:
        exc = np.convolve(np.concatenate([exc, exc[:k]]), np.ones(k) / k, mode="valid")[:N]
    d = max(1, int(round(pick_pos * N)))
    exc = exc - np.roll(exc, d)
    exc -= exc.mean()
    blocks = np.empty((nblocks, N))
    blocks[0] = exc
    pp_last = 0.0
    prev = exc
    for i in range(1, nblocks):
        sh = np.empty(N)
        sh[0] = pp_last
        sh[1:] = prev[:-1]
        cur = g * 0.5 * (prev + sh)
        blocks[i] = cur
        pp_last = prev[-1]
        prev = cur
    y = blocks.reshape(-1)
    # resample: output sample m corresponds to generated position m*eff/period
    pos = np.arange(n_out) * (eff / period)
    out = np.interp(pos, np.arange(len(y)), y)
    return out


# ---------------------------------------------------------------- convolution / reverb

def convolve(x: np.ndarray, ir: np.ndarray, circular: bool = False) -> np.ndarray:
    n = x.shape[-1]
    if circular:
        assert ir.shape[-1] <= n, "IR longer than loop"
        nfft = n
    else:
        nfft = next_fast(n + ir.shape[-1])
    X = np.fft.rfft(x, n=nfft, axis=-1)
    Hh = np.fft.rfft(ir, n=nfft, axis=-1)
    y = np.fft.irfft(X * Hh, n=nfft, axis=-1)
    return y[..., : (n if circular else n + ir.shape[-1] - 1)]


def make_ir(rt60: float = 1.5, length: float = 3.0, predelay: float = 0.014,
            damp_hz: float = 4200.0, lo_cut: float = 180.0, seed: str = "hall") -> np.ndarray:
    """Stereo synthetic room impulse response (frequency-dependent decay)."""
    r = rng("ir", seed, rt60, length)
    n = ns(length)
    out = np.zeros((2, n + ns(predelay)))

    def gain(t, f):
        rt = rt60 / (1.0 + (f / damp_hz) ** 1.3)
        g = np.exp(-6.9078 * np.maximum(t, 0) / np.maximum(rt, 0.05))
        hp = (f / lo_cut) ** 2 / (1.0 + (f / lo_cut) ** 2)
        return g * hp

    for ch in range(2):
        tail = stft_shape(r.standard_normal(n), gain)
        tail *= ramp_in(n, ns(0.006))
        # early reflections: a handful of soft taps
        er = np.zeros(n)
        for j, ms in enumerate([7.1, 11.3, 16.9, 23.7, 31.1, 42.3, 55.0]):
            p = ns(ms / 1000.0 * (1.0 + 0.07 * ch * (1 if j % 2 else -1)))
            if p < n:
                er[p] += (0.55 - 0.06 * j) * (1 if (j + ch) % 2 else -1) * r.uniform(0.7, 1.0)
        er = filt(er, lambda f: H_lp(f, 5000) * H_hp(f, lo_cut))[:n]
        tail = tail / (rms(tail) + 1e-12)
        er = er / (np.sqrt(np.sum(er ** 2)) + 1e-12)
        ir = tail / np.sqrt(np.sum(tail ** 2)) * 0.92 + er * 0.39
        out[ch, ns(predelay):] = ir
    out /= np.sqrt(np.sum(out ** 2) / 2.0)
    return out


def pan_gains(pan: float):
    th = (np.clip(pan, -1.0, 1.0) + 1.0) * np.pi / 4.0
    return np.cos(th), np.sin(th)


# ---------------------------------------------------------------- limiter

def sliding_min(a: np.ndarray, w: int) -> np.ndarray:
    """out[i] = min(a[i:i+w]) for i in 0..len(a)-w (van Herk / Gil-Werman)."""
    n = len(a)
    if w <= 1:
        return a.copy()
    nb = -(-n // w) + 1
    p = np.full(nb * w, np.inf)
    p[:n] = a
    blk = p.reshape(nb, w)
    pre = np.minimum.accumulate(blk, axis=1).reshape(-1)
    suf = np.minimum.accumulate(blk[:, ::-1], axis=1)[:, ::-1].reshape(-1)
    i = np.arange(n - w + 1)
    return np.minimum(suf[i], pre[i + w - 1])


def limiter_gain(det: np.ndarray, ceiling_db: float, knee_db: float = 3.0,
                 look: float = 0.004, hold: float = 0.045, circular: bool = False) -> np.ndarray:
    """Soft-knee look-ahead peak limiter gain curve.

    Guarantees gain[n] * det[n] <= ceiling (the smoothed gain at every sample is
    at most the instantaneous required gain: each value is a mean of window
    minima that all include that sample).
    """
    n = len(det)
    L = 20.0 * np.log10(np.maximum(det, 1e-9))
    T, W = ceiling_db, knee_db
    over = L - (T - W / 2.0)
    gr = np.where(over <= 0, 0.0, np.where(over < W, -(over ** 2) / (2.0 * W), T - L))
    g = 10.0 ** (gr / 20.0)
    la = max(1, ns(look))
    hd = max(0, ns(hold))
    P = hd + 2 * la + 2
    if circular:
        reps = int(np.ceil(P / n)) + 1
        big = np.tile(g, 2 * reps + 1)
        gp = big[reps * n - P: reps * n + n + P]
    else:
        gp = np.concatenate([np.ones(P), g, np.ones(P)])
    w = hd + la
    sm = sliding_min(gp, w)                 # sm[j] = min gp[j : j+w]
    # hfull[k] = min gp[k-hd : k+la]  ->  sm[k - hd]
    k = np.arange(P - la, P + n)
    hfull = sm[k - hd]
    c = np.concatenate([[0.0], np.cumsum(hfull)])
    # s[m] = mean(hfull over k in [P+m-la+1, P+m])  (index into hfull: k-(P-la))
    m = np.arange(n)
    hi_i = (P + m) - (P - la) + 1
    lo_i = hi_i - la
    s = (c[hi_i] - c[lo_i]) / la
    return np.minimum(s, 1.0)


def limit(x: np.ndarray, ceiling_db: float = -1.5, knee_db: float = 3.0,
          circular: bool = False, det: np.ndarray | None = None) -> np.ndarray:
    if det is None:
        det = np.max(np.abs(np.atleast_2d(x)), axis=0)
    g = limiter_gain(det, ceiling_db, knee_db, circular=circular)
    return x * g


# ---------------------------------------------------------------- loudness

def kweight_rms_db(x: np.ndarray) -> float:
    """Approximate K-weighted (BS.1770 style) loudness of a mono/stereo signal."""
    x2 = np.atleast_2d(x)
    y = filt(x2, lambda f: H_highshelf(f, 1500.0, 4.0) * H_hp(f, 60.0, 0.5), circular=True)
    ms = np.mean(np.sum(y ** 2, axis=0) / 1.0)
    return -0.691 + 10.0 * np.log10(max(ms, 1e-20))


def loudness_gated(x: np.ndarray, block: float = 0.4) -> float:
    """BS.1770-style gated loudness (absolute -70, relative -10 LU gates)."""
    x2 = np.atleast_2d(x)
    y = filt(x2, lambda f: H_highshelf(f, 1500.0, 4.0) * H_hp(f, 60.0, 0.5), circular=True)
    p = np.sum(y ** 2, axis=0)
    bn = int(block * SR)
    nb = len(p) // bn
    if nb < 1:
        return kweight_rms_db(x)
    ms = p[: nb * bn].reshape(nb, bn).mean(axis=1)
    lk = -0.691 + 10 * np.log10(ms + 1e-20)
    keep = lk > -70.0
    if not np.any(keep):
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(ms[keep])) - 10.0
    keep &= lk > rel
    return float(-0.691 + 10 * np.log10(np.mean(ms[keep])))


def true_peak(x: np.ndarray, os: int = 4) -> float:
    """4x oversampled peak (FFT interpolation, circular)."""
    x2 = np.atleast_2d(x)
    n = x2.shape[-1]
    best = 0.0
    for ch in x2:
        X = np.fft.rfft(ch)
        y = np.fft.irfft(X, n=n * os) * os
        best = max(best, float(np.max(np.abs(y))))
    return best


# ---------------------------------------------------------------- WAV I/O

def write_wav_f32(path: str, x: np.ndarray) -> None:
    x = np.atleast_2d(np.asarray(x, dtype=np.float32))
    ch, n = x.shape
    data = np.ascontiguousarray(x.T).astype("<f4").tobytes()
    fmt = struct.pack("<HHIIHH", 3, ch, SR, SR * ch * 4, ch * 4, 32)
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + 8 + len(fmt) + 8 + len(data)) + b"WAVE")
        fh.write(b"fmt " + struct.pack("<I", len(fmt)) + fmt)
        fh.write(b"data" + struct.pack("<I", len(data)) + data)
