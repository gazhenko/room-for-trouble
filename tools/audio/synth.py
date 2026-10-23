#!/usr/bin/env python3
"""Room for Trouble - deterministic procedural audio generator.

Renders every music cue, sound effect and voice syllable from code (no
samples), masters them, encodes Ogg Vorbis with oggenc, decodes the result
with oggdec to verify it, and writes assets/export/audio/audio_manifest.json
plus REGISTER.md.

    tools/audio/.venv/bin/python tools/audio/synth.py

Options: --jobs N, --only ID[,ID...] (substring match, for iteration; skips
manifest/cleanup), --keep-wav DIR, --report FILE.json (full QA metrics).
"""

from __future__ import annotations

import argparse
import itertools
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zlib
from concurrent.futures import ProcessPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

from dsp import (SR, db, dc_block, fade, kweight_rms_db, limit, limiter_gain, peak, true_peak,  # noqa: E402
                 write_wav_f32)

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DEFAULT = os.path.join(REPO, "assets", "export", "audio")
RES_PREFIX = "res://assets/export/audio/"
OGGENC = shutil.which("oggenc") or "/opt/homebrew/bin/oggenc"
OGGDEC = shutil.which("oggdec") or "/opt/homebrew/bin/oggdec"

BPM = 108
BEAT_N = 24500
STEMS = ("calm", "move", "busy", "celeb")
LOUDNESS_LIMIT_DB = -1.0          # hard requirement on every decoded file
MUSIC_CEILING = -2.0              # pre-encode limiter ceiling (sample peak)

STINGERS = {
    # id: (builder name, length seconds)
    "sting_shift_start": ("build_sting_shift_start", 3.3),
    "sting_wrap": ("build_sting_wrap", 3.2),
    "sting_postcard": ("build_sting_postcard", 2.6),
    "sting_unlock": ("build_sting_unlock", 2.1),
    "sting_results": ("build_sting_results", 4.2),
    "sting_star": ("build_sting_star", 0.8),
}


# ======================================================================= encode + verify

def serial_of(cid: str) -> int:
    return zlib.crc32(cid.encode()) & 0x7FFFFFFF


def encode(x: np.ndarray, cid: str, out_path: str, tmp: str, quality: int, keep: str | None) -> None:
    wav = os.path.join(tmp, cid + ".wav")
    write_wav_f32(wav, x)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    subprocess.run([OGGENC, "-Q", "-q", str(quality), "-s", str(serial_of(cid)), "-o", out_path, wav], check=True)
    if keep:
        os.makedirs(keep, exist_ok=True)
        shutil.copy(wav, os.path.join(keep, cid + ".wav"))
    os.remove(wav)


def decode(path: str, channels: int) -> np.ndarray:
    raw = subprocess.run([OGGDEC, "-Q", "-R", "-b", "16", "-e", "0", "-s", "1", "-o", "-", path],
                         check=True, capture_output=True).stdout
    y = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return y.reshape(-1, channels).T


def seam_metrics(y: np.ndarray) -> dict:
    """Click check for loops: the wrap-around step vs. the signal's own steps."""
    y2 = np.atleast_2d(y)
    d = np.abs(np.diff(y2, axis=1))
    typical = float(np.percentile(d, 99.9))
    jump = float(np.max(np.abs(y2[:, 0] - y2[:, -1])))
    w = int(0.05 * SR)
    head = float(np.sqrt(np.mean(y2[:, :w] ** 2)))
    tail = float(np.sqrt(np.mean(y2[:, -w:] ** 2)))
    # typical adjacent-window RMS change, for context
    nwin = y2.shape[1] // w
    wr = np.sqrt(np.mean(y2[:, : nwin * w].reshape(y2.shape[0], nwin, w) ** 2, axis=(0, 2)))
    steps = np.abs(np.diff(20 * np.log10(wr + 1e-9)))
    return dict(seam_jump=jump, seam_jump_vs_p999=jump / (typical + 1e-12),
                seam_rms_step_db=abs(20 * np.log10((head + 1e-9) / (tail + 1e-9))),
                rms_step_p95_db=float(np.percentile(steps, 95)))


def bar_steps(y: np.ndarray, bar_n: int, w: int = 2205) -> dict:
    """RMS step (dB) across every bar line, the seam (bar 0) included, so the
    seam can be compared with the loop's own bar lines."""
    y2 = np.atleast_2d(y)
    n = y2.shape[1]
    steps = []
    for b0 in range(0, n, bar_n):
        before = np.take(y2, np.arange(b0 - w, b0) % n, axis=1)
        after = np.take(y2, np.arange(b0, b0 + w) % n, axis=1)
        steps.append(abs(20 * np.log10((np.sqrt(np.mean(after ** 2)) + 1e-9) /
                                       (np.sqrt(np.mean(before ** 2)) + 1e-9))))
    others = steps[1:]
    return dict(seam_bar_step_db=round(steps[0], 2), other_bar_steps_median_db=round(float(np.median(others)), 2),
                other_bar_steps_max_db=round(float(np.max(others)), 2))


def verify(path: str, x: np.ndarray, loop: bool, bar_n: int | None = None) -> dict:
    ch = 1 if x.ndim == 1 else x.shape[0]
    y = decode(path, ch)
    exp_n = x.shape[-1]
    info = dict(samples=int(y.shape[-1]), expected_samples=int(exp_n), channels=ch,
                peak_dbfs=round(db(peak(y)), 2), true_peak_dbfs=round(db(true_peak(y)), 2),
                pre_peak_dbfs=round(db(peak(x)), 2),
                dc_max=float(np.max(np.abs(np.mean(np.atleast_2d(y), axis=1)))),
                nan=bool(np.isnan(x).any() or np.isinf(x).any()),
                loudness_lufs=round(kweight_rms_db(y), 1), bytes=os.path.getsize(path))
    if loop:
        info.update(seam_metrics(y))
        if bar_n:
            info.update(bar_steps(y, bar_n))
        info["pre_seam_jump"] = float(np.max(np.abs(np.atleast_2d(x)[:, 0] - np.atleast_2d(x)[:, -1])))
    problems = []
    if info["samples"] != exp_n:
        problems.append(f"length {info['samples']} != {exp_n}")
    if info["peak_dbfs"] > LOUDNESS_LIMIT_DB or info["true_peak_dbfs"] > LOUDNESS_LIMIT_DB:
        problems.append(f"peak {info['peak_dbfs']} / true {info['true_peak_dbfs']} dBFS")
    if info["dc_max"] > 1e-3:
        problems.append(f"DC {info['dc_max']:.2e}")
    if info["nan"]:
        problems.append("NaN/Inf")
    if loop and info["seam_jump_vs_p999"] > 1.5:
        problems.append(f"seam jump {info['seam_jump']:.4f} ({info['seam_jump_vs_p999']:.2f}x p99.9)")
    info["problems"] = problems
    return info, y


# ======================================================================= mastering

def master_loop(x: np.ndarray, target_lufs: float, ceiling: float = MUSIC_CEILING) -> np.ndarray:
    x = dc_block(x, 22.0, circular=True)
    g = 10 ** ((target_lufs - kweight_rms_db(x)) / 20.0)
    x = x * g
    return limit(x, ceiling, 3.0, circular=True)


CREST_DB = {"calm": 2.5, "move": 1.5, "busy": 3.0, "celeb": 1.0}


def worst_subset_detector(arr: np.ndarray) -> np.ndarray:
    """Per-sample largest |sum| over every subset of stems: max(sum of positive
    parts, sum of negative parts), taken over both channels."""
    pos = np.sum(np.maximum(arr, 0.0), axis=0)
    neg = np.sum(np.maximum(-arr, 0.0), axis=0)
    return np.max(np.maximum(pos, neg), axis=0)


def master_chapter(stems: dict, stem_peak: float, sum_ceiling: float = MUSIC_CEILING,
                   max_gr: float = 2.0) -> tuple[dict, dict]:
    """One common gain for the (already balanced) stems so the loudest stem peaks
    at `stem_peak`, after gentle per-stem crest control; then one linked
    soft-knee limiter driven by the worst-case subset sum so every combination
    of the four stems stays under the ceiling (gain capped so the limiter never
    has to do more than `max_gr` dB)."""
    st = {k: dc_block(v, 22.0, circular=True) for k, v in stems.items()}
    st = {k: limit(v, db(peak(v)) - CREST_DB[k], 3.0, circular=True) for k, v in st.items()}
    g_db = stem_peak - max(db(peak(v)) for v in st.values())
    det0 = worst_subset_detector(np.stack([st[k] for k in STEMS]))
    g_db = min(g_db, sum_ceiling + max_gr - db(np.max(det0)))
    g = 10 ** (g_db / 20.0)
    st = {k: v * g for k, v in st.items()}
    det = det0 * g
    gain = limiter_gain(det, sum_ceiling, 3.0, circular=True)
    out = {k: st[k] * gain for k in STEMS}
    stats = dict(worst_subset_pre_db=round(db(np.max(det)), 2),
                 max_gain_reduction_db=round(-db(np.min(gain)), 2))
    return out, stats


def master_sting(x: np.ndarray, length: float, peak_db: float = -3.0) -> np.ndarray:
    n = int(round(length * SR))
    x = x[:, :n]
    if x.shape[1] < n:
        x = np.pad(x, ((0, 0), (0, n - x.shape[1])))
    x = dc_block(x, 22.0)[:, :n]
    # long gentle tail fade so the reverb never stops abruptly
    fo = min(0.45, length * 0.3)
    x = remove_mean(fade(x, 0.003, fo))
    x = limit(x, peak_db + 0.5, 3.0)
    return x * (10 ** (peak_db / 20.0) / peak(x))


def trim_tail(x: np.ndarray, floor_db: float = -75.0, min_len: float = 0.05) -> np.ndarray:
    a = np.abs(x)
    thr = peak(x) * 10 ** (floor_db / 20.0)
    idx = np.nonzero(a > thr)[0]
    end = int(idx[-1]) + int(0.01 * SR) if len(idx) else len(x)
    return x[: max(int(min_len * SR), min(len(x), end))]


def remove_mean(x: np.ndarray) -> np.ndarray:
    """Zero the mean without touching the (already faded) end points: subtract a
    scaled smooth window instead of a constant."""
    n = x.shape[-1]
    w = np.sin(np.pi * (np.arange(n) + 0.5) / n) ** 2
    c = np.sum(x, axis=-1, keepdims=True) / np.sum(w)
    return x - c * w


def master_sfx(x: np.ndarray, target: float, loop: bool, length: float | None = None) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    if loop:
        x = dc_block(x, 25.0, circular=True)
        x = x - np.mean(x)
        x = limit(x, db(peak(x)) - 1.0, 3.0, circular=True)
        return x * (10 ** (target / 20.0) / peak(x))
    if length:
        n = int(round(length * SR))
        x = np.pad(x, (0, max(0, n - len(x))))[:n]
    else:
        x = trim_tail(x)
    x = dc_block(x, 25.0)[: len(x)]
    x = fade(x, 0.003, 0.006 if len(x) < SR * 0.4 else 0.02)
    x = remove_mean(x)
    # gentle soft-knee limiting: tame only the very top transient (<= ~1 dB)
    x = limit(x, db(peak(x)) - 1.0, 3.0)
    x = x * (10 ** (target / 20.0) / peak(x))
    return x


def sfx_target(x: np.ndarray, target: float, bus: str) -> float:
    """Sustained tonal cues are much louder than foley at the same peak; use the
    -3..-6 dBFS window to even that out (half of any excess over -14 LUFS)."""
    if bus == "UI":
        return target
    lufs = kweight_rms_db(x) + (target - db(peak(x)))
    # aim inside the window with a little margin for codec peak drift
    return float(np.clip(target - 0.5 * max(0.0, lufs - (-14.0)), -5.6, -3.4))


# ======================================================================= jobs

def _entry(cid, rel, bus, loop, x, info, **extra):
    e = dict(id=cid, path=RES_PREFIX + rel, bus=bus, loop=loop,
             length_s=round(x.shape[-1] / SR, 6), peak_dbfs=info["peak_dbfs"])
    e.update(extra)
    e["samples"] = info["samples"]
    e["sample_rate"] = SR
    e["channels"] = info["channels"]
    e["true_peak_dbfs"] = info["true_peak_dbfs"]
    return e


def job_chapter(c, out, tmp, keep):
    import music as M
    stems = M.build_chapter(c)
    st, stats = master_chapter(stems, -8.5 if c == 3 else -6.5)
    entries, reports, decoded = [], [], {}
    bars = M.chapter_song(c).bars
    for k in STEMS:
        cid = f"ch{c}_{k}"
        rel = f"music/{cid}.ogg"
        x = st[k].astype(np.float32)
        assert x.shape[1] == bars * 4 * BEAT_N
        encode(x, cid, os.path.join(out, rel), tmp, 5, keep)
        info, y = verify(os.path.join(out, rel), x, True, 4 * BEAT_N)
        decoded[k] = y
        entries.append(_entry(cid, rel, "Music", True, x, info, bpm=BPM, bars=bars, chapter=c, stem=k,
                              chapter_name=M.CHAPTERS[c]["name"], key=M.CHAPTERS[c]["key"]))
        reports.append(dict(id=cid, kind="music", **info))
    # summed-stem check on the decoded files: every combination
    worst = (-200.0, None)
    for r_ in range(1, 5):
        for combo in itertools.combinations(STEMS, r_):
            s = sum(decoded[k] for k in combo)
            p = db(peak(s))
            if p > worst[0]:
                worst = (p, combo)
    full = sum(decoded[k] for k in STEMS)
    sum_info = dict(id=f"ch{c}_sum", kind="sum", full_peak_dbfs=round(db(peak(full)), 2),
                    full_true_peak_dbfs=round(db(true_peak(full)), 2),
                    worst_subset=list(worst[1]), worst_subset_peak_dbfs=round(worst[0], 2),
                    full_loudness_lufs=round(kweight_rms_db(full), 1),
                    calm_loudness_lufs=round(kweight_rms_db(decoded["calm"]), 1), **stats,
                    seam=seam_metrics(full), bars=bar_steps(full, 4 * BEAT_N))
    sum_info["problems"] = ([] if max(sum_info["full_peak_dbfs"], sum_info["full_true_peak_dbfs"],
                                      sum_info["worst_subset_peak_dbfs"]) <= LOUDNESS_LIMIT_DB
                            else ["summed stems exceed -1 dBFS"])
    reports.append(sum_info)
    return entries, reports


def job_music(name, out, tmp, keep):
    import music as M
    if name == "title_loop":
        x = master_loop(M.build_title(), -14.5)
        meta = dict(bpm=BPM, bars=len(M.TITLE_BARS), chapter=0, stem="full")
        loop = True
    elif name == "planning":
        x = master_loop(M.build_planning(), -18.5)
        meta = dict(bpm=BPM, bars=len(M.PLANNING_BARS), chapter=0, stem="full")
        loop = True
    elif name == "ending":
        x = master_loop(M.build_ending(), -14.0)
        meta = dict(bpm=BPM, bars=len(M.ENDING_BARS), chapter=0, stem="full")
        loop = True
    else:
        builder, length = STINGERS[name]
        x = master_sting(getattr(M, builder)(), length, -5.0 if name == "sting_star" else -3.0)
        meta = dict(bpm=60 if name == "sting_shift_start" else BPM, bars=None, chapter=0, stem="sting")
        if name == "sting_star":
            meta["base_note"] = "F5"
        if name == "sting_shift_start":
            meta["onsets_s"] = [0.0, 1.0, 2.0]
        loop = False
    rel = f"music/{name}.ogg"
    x = x.astype(np.float32)
    encode(x, name, os.path.join(out, rel), tmp, 5, keep)
    info, y = verify(os.path.join(out, rel), x, loop, 4 * BEAT_N if loop else None)
    if name == "sting_shift_start":
        info["onsets_s"] = detect_onsets(y)
        info["onsets_pre_encode_s"] = detect_onsets(x)
    return [_entry(name, rel, "Music", loop, x, info, **meta)], [dict(id=name, kind="music", **info)]


def detect_onsets(y, min_gap=0.25):
    """Onset times (s): frames whose 2 kHz+ band energy jumps > 5 dB above the
    previous 15 ms, refined to the first sample that clearly (1.5x) exceeds the
    ringing of earlier notes."""
    from dsp import filt, H_hp
    m = np.mean(np.atleast_2d(y), axis=0)
    h = filt(m, lambda f: H_hp(f, 2000.0))[: len(m)]
    hop = 220
    nf = len(h) // hop
    e = np.sum(h[: nf * hop].reshape(nf, hop) ** 2, axis=1)
    L = 10 * np.log10(e + 1e-14)
    top = np.max(L)
    Lp = np.concatenate([np.full(3, -140.0), L])      # silence before the file
    on, last = [], -1e9
    for k in range(nf):
        rise = Lp[k + 3] - np.max(Lp[k:k + 3])
        if rise > 5.0 and L[k] > top - 30.0 and (k * hop - last) / SR > min_gap:
            lo = max(0, (k - 1) * hop)
            # base = loudest ringing in the 15 ms before; onset = first clear exceedance
            base = np.max(np.abs(h[max(0, lo - 3 * hop): lo])) if lo > 0 else 0.0
            seg = np.abs(h[lo: lo + 3 * hop])
            thr = max(1.5 * base, 0.05 * np.max(seg))
            j = lo + int(np.argmax(seg > thr))
            on.append(round(j / SR, 4))
            last = j
    return on


def job_sfx(ids, out, tmp, keep):
    import sfx as S
    entries, reports = [], []
    for cid in ids:
        spec = S.CUES[cid]
        x = master_sfx(spec["fn"](), spec["target"], spec["loop"], spec["length"])
        tgt = sfx_target(x, spec["target"], spec["bus"])
        x = (x * 10 ** ((tgt - db(peak(x))) / 20.0)).astype(np.float32)
        rel = f"sfx/{cid}.ogg"
        encode(x, cid, os.path.join(out, rel), tmp, 4, keep)
        info, _ = verify(os.path.join(out, rel), x, spec["loop"])
        # correction passes so the *decoded* peak lands on target (codec peaks
        # drift a little with gain); keep the best attempt
        best = (abs(info["peak_dbfs"] - tgt), x, info)
        for _ in range(4):
            if best[0] <= 0.1:
                break
            x = (best[1] * 10 ** ((tgt - best[2]["peak_dbfs"]) / 20.0)).astype(np.float32)
            encode(x, cid, os.path.join(out, rel), tmp, 4, keep)
            info, _ = verify(os.path.join(out, rel), x, spec["loop"])
            if abs(info["peak_dbfs"] - tgt) < best[0]:
                best = (abs(info["peak_dbfs"] - tgt), x, info)
        if info is not best[2]:
            x, info = best[1], best[2]
            encode(x, cid, os.path.join(out, rel), tmp, 4, keep)
            info, _ = verify(os.path.join(out, rel), x, spec["loop"])
        # guard: Effects/Voices cues must decode inside -6..-3 dBFS
        lo, hi = (tgt - 0.35, tgt + 0.35) if spec["bus"] == "UI" else (-6.0, -3.0)
        for _ in range(6):
            if lo <= info["peak_dbfs"] <= hi:
                break
            step = (lo + 0.12 - info["peak_dbfs"]) if info["peak_dbfs"] < lo else (hi - 0.12 - info["peak_dbfs"])
            x = (x * 10 ** (step / 20.0)).astype(np.float32)
            encode(x, cid, os.path.join(out, rel), tmp, 4, keep)
            info, _ = verify(os.path.join(out, rel), x, spec["loop"])
        if not (lo <= info["peak_dbfs"] <= hi):
            info["problems"].append(f"decoded peak {info['peak_dbfs']} outside {lo:.2f}..{hi:.2f} dBFS")
        info["target_dbfs"] = round(tgt, 2)
        entries.append(_entry(cid, rel, spec["bus"], spec["loop"], x, info))
        reports.append(dict(id=cid, kind="sfx", **info))
    return entries, reports


def job_voice(out, tmp, keep):
    import sfx as S
    from dsp import rms
    raw = [S.make_syllable(i) for i in range(len(S.SYLLABLES))]
    # same loudness: match RMS over the voiced part, then one common gain
    prepared = []
    for x in raw:
        x = trim_tail(x, -70.0)
        x = dc_block(x, 25.0)
        x = x - np.mean(x)
        x = fade(x, 0.003, 0.006)
        x = remove_mean(x)
        a = np.abs(x)
        voiced = x[np.convolve(a > 0.1 * np.max(a), np.ones(441), mode="same") > 0]
        prepared.append(x / 10 ** (kweight_rms_db(voiced) / 20.0))
    common = 10 ** (-6.0 / 20.0) / max(peak(x) for x in prepared)
    entries, reports = [], []
    for i, x in enumerate(prepared):
        cid = f"syl_{i + 1:02d}"
        x = (x * common).astype(np.float32)
        rel = f"voice/{cid}.ogg"
        encode(x, cid, os.path.join(out, rel), tmp, 4, keep)
        info, _ = verify(os.path.join(out, rel), x, False)
        info["voiced_rms_dbfs"] = round(db(rms(x[np.abs(x) > 0.1 * np.max(np.abs(x))])), 2)
        c, v, d = S.SYLLABLES[i]
        entries.append(_entry(cid, rel, "Voices", False, x, info, syllable=c + v, base_hz=220.0))
        reports.append(dict(id=cid, kind="voice", **info))
    return entries, reports


# ======================================================================= main

MUSIC_ORDER = ["title_loop", "ending", "planning"] + list(STINGERS)


def expected_ids():
    import sfx as S
    ids = ["title_loop"] + [f"ch{c}_{k}" for c in range(1, 7) for k in STEMS] + ["planning"] + list(STINGERS) + ["ending"]
    ids += list(S.CUES)
    ids += [f"syl_{i:02d}" for i in range(1, 17)]
    return ids


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--only", default="")
    ap.add_argument("--keep-wav", default=None)
    ap.add_argument("--report", default=None, help="write the full QA report (JSON) to this path")
    args = ap.parse_args()

    t0 = time.time()
    out = os.path.abspath(args.out)
    tmp = tempfile.mkdtemp(prefix="rft_audio_")
    only = [s for s in args.only.split(",") if s]

    import sfx as S
    jobs = []
    for c in (6, 1, 5, 2, 4, 3):
        jobs.append(("chapter", c))
    jobs += [("music", m) for m in MUSIC_ORDER]
    sfx_ids = list(S.CUES)
    for i in range(0, len(sfx_ids), 4):
        jobs.append(("sfx", tuple(sfx_ids[i:i + 4])))
    jobs.append(("voice", None))
    if only:
        def want(j):
            kind, arg = j
            names = ([f"ch{arg}_{k}" for k in STEMS] if kind == "chapter" else
                     [arg] if kind == "music" else list(arg) if kind == "sfx" else ["syl_"])
            return any(o in n for o in only for n in names)
        jobs = [j for j in jobs if want(j)]

    entries, reports = [], []
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        futs = {}
        for kind, arg in jobs:
            if kind == "chapter":
                f = ex.submit(job_chapter, arg, out, tmp, args.keep_wav)
            elif kind == "music":
                f = ex.submit(job_music, arg, out, tmp, args.keep_wav)
            elif kind == "sfx":
                f = ex.submit(job_sfx, arg, out, tmp, args.keep_wav)
            else:
                f = ex.submit(job_voice, out, tmp, args.keep_wav)
            futs[f] = (kind, arg)
        for f in as_completed(futs):
            e, r = f.result()
            entries += e
            reports += r
    shutil.rmtree(tmp, ignore_errors=True)

    order = {cid: i for i, cid in enumerate(expected_ids())}
    entries.sort(key=lambda e: order.get(e["id"], 10 ** 6))
    reports.sort(key=lambda r: order.get(r["id"].replace("_sum", "_celeb"), 10 ** 6) + (0.5 if r["kind"] == "sum" else 0))

    problems = [(r["id"], p) for r in reports for p in r.get("problems", [])]
    if not only:
        missing = sorted(set(expected_ids()) - {e["id"] for e in entries})
        if missing:
            problems.append(("manifest", f"missing ids: {missing}"))
        write_manifest(out, entries)
        write_register(out, entries)
        cleanup(out, entries)
    if args.report:
        write_report(args.report, reports, time.time() - t0)
    print_summary(out, entries, reports, problems, time.time() - t0)
    return 1 if problems else 0


def write_manifest(out, entries):
    man = dict(version=1, generator="tools/audio/synth.py", sample_rate=SR, bpm=BPM,
               beat_samples=BEAT_N, loop_bars_chapter=16,
               motif=dict(degrees=[1, 3, 5], semitones=[0, 4, 7], onsets_beats=[0.0, 0.5, 1.5],
                          home_key="F", notes=["F", "A", "C"]),
               cues=entries)
    text = json.dumps(man, indent=2)
    # keep short number lists on one line for readability
    import re
    text = re.sub(r"\[\s+([^\[\]{}]*?)\s+\]", lambda m: "[" + " ".join(m.group(1).split()) + "]", text)
    with open(os.path.join(out, "audio_manifest.json"), "w") as fh:
        fh.write(text + "\n")


def write_register(out, entries):
    lines = ["# Audio asset register", "",
             "Every file below is generated from code by `tools/audio/synth.py` (no samples, no third-party",
             "recordings, no recognisable commercial melodies). Regenerate with",
             "`tools/audio/.venv/bin/python tools/audio/synth.py` (see `tools/audio/README.md`).", "",
             "| File | Provenance | License | Final |", "| --- | --- | --- | --- |"]
    for e in entries:
        rel = e["path"][len(RES_PREFIX):]
        lines.append(f"| `{rel}` | original procedural synthesis, tools/audio/synth.py | "
                     f"project-original (CC0-compatible, owned by project) | yes |")
    with open(os.path.join(out, "REGISTER.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")


def cleanup(out, entries):
    keep = {os.path.normpath(os.path.join(out, e["path"][len(RES_PREFIX):])) for e in entries}
    for sub in ("music", "sfx", "voice"):
        d = os.path.join(out, sub)
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            p = os.path.normpath(os.path.join(d, fn))
            if fn.endswith(".ogg") and p not in keep:
                os.remove(p)


def write_report(path, reports, wall):
    with open(path, "w") as fh:
        json.dump(dict(wall_s=round(wall, 1), reports=reports), fh, indent=1, default=float)


def print_summary(out, entries, reports, problems, wall):
    total = 0
    for root, _, files in os.walk(out):
        for fn in files:
            total += os.path.getsize(os.path.join(root, fn))
    print(f"\nRendered {len(entries)} cues in {wall:.1f} s; assets/export/audio total {total / 1e6:.2f} MB")
    print(f"{'music id':22s} {'len s':>8s} {'peak':>7s} {'tpeak':>7s} {'LUFS~':>6s} {'seam':>6s}")
    for r in reports:
        if r["kind"] == "music":
            seam = f"{r['seam_jump_vs_p999']:.2f}" if "seam_jump_vs_p999" in r else "-"
            print(f"{r['id']:22s} {r['samples'] / SR:8.3f} {r['peak_dbfs']:7.2f} {r['true_peak_dbfs']:7.2f} "
                  f"{r['loudness_lufs']:6.1f} {seam:>6s}")
        elif r["kind"] == "sum":
            print(f"{'  sum ' + r['id'][:-4]:22s} {'':8s} {r['full_peak_dbfs']:7.2f} {r['full_true_peak_dbfs']:7.2f} "
                  f"{r['full_loudness_lufs']:6.1f}  worst subset {r['worst_subset_peak_dbfs']:.2f} "
                  f"{'+'.join(r['worst_subset'])}, GR {r['max_gain_reduction_db']} dB")
    other = [r for r in reports if r["kind"] in ("sfx", "voice")]
    if other:
        pk = [r["peak_dbfs"] for r in other]
        tp = [r["true_peak_dbfs"] for r in other]
        print(f"sfx/voice: {len(other)} files, peak {min(pk):.2f}..{max(pk):.2f} dBFS, true peak max {max(tp):.2f}")
    if problems:
        print("\nPROBLEMS:")
        for cid, p in problems:
            print(f"  {cid}: {p}")
    else:
        print("All checks passed.")


if __name__ == "__main__":
    sys.exit(main())
