"""Room for Trouble music: arrangement parts and every composition.

All chapter cues share 108 BPM, 4/4 and a 16-bar loop of exactly
16 * 4 * 24500 = 1,568,000 samples.  Loops are rendered circularly: note and
reverb tails that run past the loop end are folded back onto the start, so
the last sample flows straight into the first.

The welcome motif is root -> major third -> fifth with onsets on beats
0, 1/2 and 1 1/2 ("da da-DAAA"); in F it is F A C.
"""

from __future__ import annotations

import numpy as np

import instruments as I
from dsp import SR, convolve, dc_block, filt, H_hp, H_lp, kweight_rms_db, loudness_gated, make_ir, ns, \
    pan_gains, peak, rng, undb, db, H_peak, H_highshelf
from theory import (BEAT_S, BPM, Song, check_melody, ladder, nearest_in, parse_melody,
                    voice_lead, pc_of, MAJOR)

BEAT_N = 24500                    # samples per beat at 108 BPM (exact)
BAR_N = 4 * BEAT_N

MOTIF = [(0.0, 0, 0.5), (0.5, 4, 1.0), (1.5, 7, 2.5)]   # (beat, semitones, beats)

_IR_CACHE = {}


def room_ir(kind="hall"):
    if kind not in _IR_CACHE:
        if kind == "hall":
            _IR_CACHE[kind] = make_ir(rt60=1.6, length=3.2, predelay=0.016, damp_hz=4000.0, seed="hall")
        elif kind == "small":
            _IR_CACHE[kind] = make_ir(rt60=0.55, length=1.0, predelay=0.006, damp_hz=5000.0, seed="small")
        else:
            _IR_CACHE[kind] = make_ir(rt60=2.2, length=4.0, predelay=0.02, damp_hz=3800.0, seed="bloom")
    return _IR_CACHE[kind]


# ======================================================================= canvas

class Canvas:
    """Stereo accumulation buffer with a mono reverb send.

    loop=True: everything past `n` is folded onto the start at mix time.
    """

    def __init__(self, beats=None, seconds=None, loop=True, seed="cv", jitter=0.0035):
        if beats is not None:
            self.n = int(round(beats * BEAT_N))
        else:
            self.n = ns(seconds)
        self.loop = loop
        self.cap = self.n + ns(8.0)
        self.dry = np.zeros((2, self.cap))
        self.send = np.zeros(self.cap)
        self.r = rng("canvas", seed)
        self.jitter = jitter

    def _grow(self, end):
        if end > self.cap:
            extra = end - self.cap + ns(4.0)
            self.dry = np.pad(self.dry, ((0, 0), (0, extra)))
            self.send = np.pad(self.send, (0, extra))
            self.cap += extra

    def add(self, t_s, mono, gain=1.0, pan=0.0, send=0.15, human=True):
        if mono is None or len(mono) == 0 or gain == 0:
            return
        j = float(np.clip(self.r.normal(0.0, self.jitter), -0.009, 0.009)) if human else 0.0
        st = int(round((t_s + j) * SR))
        if self.loop:
            st %= self.n
        else:
            st = max(0, st)
        m = len(mono)
        end = st + m
        self._grow(end)
        seg = np.asarray(mono, dtype=float) * gain
        k_in = min(m, 22)
        k_out = min(m, 176)
        seg[:k_in] *= np.linspace(0.0, 1.0, k_in, endpoint=False) if k_in > 1 else 1.0
        seg[m - k_out:] *= 0.5 + 0.5 * np.cos(np.pi * (np.arange(k_out) + 1) / k_out)
        lg, rg = pan_gains(pan)
        self.dry[0, st:end] += seg * lg
        self.dry[1, st:end] += seg * rg
        if send:
            self.send[st:end] += seg * send

    def add_stereo(self, t_s, st2, gain=1.0):
        st = int(round(t_s * SR))
        if self.loop:
            st %= self.n
        m = st2.shape[1]
        self._grow(st + m)
        self.dry[:, st:st + m] += st2 * gain

    def _fold(self, x):
        if not self.loop:
            return x
        n = self.n
        out = x[..., :n].copy()
        pos = n
        while pos < x.shape[-1]:
            chunk = x[..., pos:pos + n]
            out[..., :chunk.shape[-1]] += chunk
            pos += n
        return out

    def mix(self, ir_kind="hall", wet=1.0):
        dry = self._fold(self.dry)
        send = self._fold(self.send)
        if self.loop:
            wetsig = convolve(send, room_ir(ir_kind), circular=True)
            out = dry + wet * wetsig
            return dc_block(out, 22.0, circular=True)
        ir = room_ir(ir_kind)
        wetsig = convolve(send, ir, circular=False)
        n = max(dry.shape[1], wetsig.shape[1])
        out = np.zeros((2, n))
        out[:, :dry.shape[1]] += dry
        out[:, :wetsig.shape[1]] += wet * wetsig
        return dc_block(out, 22.0)


def _lvl(level, bar):
    if level is None:
        return 1.0
    if callable(level):
        return float(level(bar))
    return float(level.get(bar, 0.0))


def bars_level(spec, nbars):
    """spec: list of (first_bar, last_bar, gain) with 1-based inclusive bars."""
    d = {}
    for a, b, g in spec:
        for bar in range(a - 1, b):
            d[bar] = g
    return lambda bar: d.get(bar % nbars, 0.0)


ROLE_LU = {"calm": 0.0, "move": -2.5, "busy": -7.0, "celeb": -0.5}
CHAPTER_LU = {
    1: ROLE_LU,
    2: ROLE_LU,
    3: {"calm": 0.0, "move": -3.0, "busy": -8.5, "celeb": -1.0},
    4: {"calm": 0.0, "move": -2.5, "busy": -6.5, "celeb": -0.5},
    5: {"calm": 0.0, "move": -2.5, "busy": -6.0, "celeb": -0.5},
    6: {"calm": 0.0, "move": -2.0, "busy": -5.5, "celeb": 0.0},
}
ENDING_LU = {"calm": 0.0, "move": -2.0, "busy": -6.0, "celeb": 0.0}


def balance(stems: dict, offsets: dict) -> dict:
    """Scale each stem so its gated K-loudness sits at its role offset from calm."""
    ref = loudness_gated(stems["calm"])
    return {k: v * undb(ref + offsets[k] - loudness_gated(v)) for k, v in stems.items()}


# ======================================================================= parts

def part_pad(cv, song, kind="warm", n=4, lo=53, hi=72, vel=0.5, gain=1.0, send=0.35,
             spread=0.55, att=0.45, rel=0.7, level=None, center=None):
    vo = voice_lead([s.chord for s in song.segments], n, lo, hi, center)
    notes = []
    active = {}
    for seg, v in zip(song.segments, vo):
        L = _lvl(level, int(seg.start // 4))
        new = {}
        for m in v:
            if L <= 0:
                continue
            a = active.get(m)
            if a is not None and abs(a[0] + a[1] - seg.start) < 1e-6 and abs(a[3] - L) < 1e-6:
                a[1] += seg.dur
                new[m] = a
            else:
                note = [seg.start, seg.dur, m, L]
                notes.append(note)
                new[m] = note
        active = new
    for i, (st, d, m, L) in enumerate(notes):
        pan = spread * (((m - lo) / max(hi - lo, 1)) * 2.0 - 1.0)
        y = I.pad(m, d * BEAT_S + 0.04, vel * L, var=i % 3, kind=kind, att=att, rel=rel)
        cv.add(st * BEAT_S, y, gain, pan, send, human=False)
    return vo


def _bass_line(song, lo, hi, start=None):
    prev = start if start is not None else (lo + hi) / 2
    out = []
    for _ in range(2):
        out = []
        for seg in song.segments:
            cands = [m for m in range(lo, hi + 1) if m % 12 == seg.chord.bass]
            m = nearest_in(cands, prev * 0.7 + (lo + hi) / 2 * 0.3)
            out.append(m)
            prev = m
    return out


def part_piano(cv, song, style="roll", lo=55, hi=74, n=3, vel=0.5, gain=1.0, send=0.3,
               with_bass=True, bass_lo=36, bass_hi=52, pedal=0.25, level=None, center=None,
               pan=0.0, roll=0.022):
    vo = voice_lead([s.chord for s in song.segments], n, lo, hi, center)
    bl = _bass_line(song, bass_lo, bass_hi)
    r = rng("piano_part", song.key, style, lo, hi)
    for i, (seg, v) in enumerate(zip(song.segments, vo)):
        bar = int(seg.start // 4)
        L = _lvl(level, bar)
        if L <= 0:
            continue
        t0 = seg.start * BEAT_S
        dur = seg.dur * BEAT_S
        hv = lambda x: x * L * (1.0 + r.normal(0, 0.04))
        if style == "roll":
            if with_bass:
                cv.add(t0, I.felt_piano(bl[i], dur, hv(vel * 0.95), i, pedal), gain, pan - 0.15, send)
            for j, m in enumerate(v):
                cv.add(t0 + roll * (j + 1), I.felt_piano(m, dur * (0.95 if seg.dur < 4 else 0.5),
                                                       hv(vel * (0.78 + 0.06 * j)), i + j, pedal),
                       gain, pan + 0.12 * (j - 1), send)
            if seg.dur >= 4:
                for j, m in enumerate(v[1:]):
                    cv.add(t0 + 2 * BEAT_S + roll * j,
                           I.felt_piano(m, dur * 0.48, hv(vel * 0.55), i + j + 1, pedal),
                           gain, pan + 0.12 * j, send)
        elif style == "lullaby":
            if with_bass:
                cv.add(t0, I.felt_piano(bl[i], dur, hv(vel * 0.9), i, pedal), gain, pan - 0.15, send)
            for j, m in enumerate(v):
                cv.add(t0 + 0.06 * (j + 1), I.felt_piano(m, dur, hv(vel * 0.7), i + j, pedal),
                       gain, pan + 0.1 * (j - 1), send)
            if seg.dur >= 4:
                cv.add(t0 + 2.5 * BEAT_S, I.felt_piano(v[-1], dur * 0.4, hv(vel * 0.45), i, pedal),
                       gain, pan + 0.2, send)
        elif style == "offbeat":
            beats = [1.0, 3.0] if seg.dur >= 4 else [1.0]
            for b in beats:
                for j, m in enumerate(v):
                    cv.add(t0 + b * BEAT_S + 0.008 * j,
                           I.felt_piano(m, 0.42 * BEAT_S, hv(vel * (0.8 + 0.05 * j)), i + j, 0.0),
                           gain, pan + 0.1 * (j - 1), send)
        elif style == "pulse":
            # gentle repeated chord on every beat (festival bed)
            for b in np.arange(0.0, seg.dur, 1.0):
                acc = 1.0 if b in (0.0, 2.0) else 0.72
                if with_bass and b == 0.0:
                    cv.add(t0, I.felt_piano(bl[i], dur, hv(vel * 0.9), i, pedal), gain, pan - 0.15, send)
                for j, m in enumerate(v):
                    cv.add(t0 + b * BEAT_S + 0.01 * j,
                           I.felt_piano(m, 0.8 * BEAT_S, hv(vel * acc * 0.8), i + j, 0.05),
                           gain, pan + 0.1 * (j - 1), send)
    return vo


def part_bass(cv, song, style="half", lo=33, hi=50, vel=0.6, gain=1.0, send=0.06, level=None,
              inst="bass", pan=0.0):
    bl = _bass_line(song, lo, hi)
    segs = song.segments
    key_pcs = {(song.key_pc + s) % 12 for s in MAJOR}
    r = rng("bass_part", song.key, style)

    def play(beat, m, d, v, L):
        vv = v * L * (1.0 + r.normal(0, 0.04))
        if inst == "pluck":
            y = I.pluck(m, d * BEAT_S, vv, var=int(beat), t60=1.6, bright=0.25, body=1.5)
        else:
            y = I.bass(m, d * BEAT_S, vv, var=int(beat), style="bouncy" if style == "bouncy" else "round")
        cv.add(beat * BEAT_S, y, gain, pan, send)

    for i, seg in enumerate(segs):
        L = _lvl(level, int(seg.start // 4))
        if L <= 0:
            continue
        root = bl[i]
        nxt = bl[(i + 1) % len(segs)]
        fifth = root + 7 if root + 7 <= hi + 4 else root - 5
        b0 = seg.start
        if style == "whole":
            play(b0, root, seg.dur - 0.08, vel, L)
        elif style == "half":
            play(b0, root, min(seg.dur, 2.0) - 0.1, vel, L)
            if seg.dur >= 4:
                tone = fifth if (seg.chord.root == seg.chord.bass) else root
                play(b0 + 2, tone, 1.9, vel * 0.85, L)
        elif style in ("bouncy", "walk"):
            if seg.dur >= 4:
                third = root + (seg.chord.ivs[1] if len(seg.chord.ivs) > 1 else 4)
                if seg.chord.root != seg.chord.bass:
                    third = root + 12 if root + 12 <= hi + 7 else root
                cands = [nxt - 1, nxt + 1, nxt - 2, nxt + 2]
                appr = next((c for c in cands if c % 12 in key_pcs and c != root), nxt - 1)
                second = root + 12 if style == "bouncy" else third
                pattern = [(0, root, 0.62, 1.0), (1, second, 0.4, 0.62), (2, fifth, 0.62, 0.9),
                           (3, appr, 0.45, 0.7)]
            else:
                pattern = [(0, root, 0.62, 1.0), (1, fifth, 0.45, 0.7)]
            for b, m, d, a in pattern:
                play(b0 + b, m, d, vel * a, L)


def part_arp(cv, song, inst, pattern, lo, hi, center, vel=0.6, gain=1.0, send=0.25, pan=0.0,
             level=None, pan_walk=0.0, seed="arp", with_ninth=False, **kw):
    """pattern: list of (beat_in_bar, ladder_offset, accent, dur_beats)."""
    r = rng("arp", seed, song.key)
    anchors = {}
    prev = center
    for bar in range(song.bars):
        L = _lvl(level, bar)
        if L <= 0:
            continue
        for k, (b, off, acc, d) in enumerate(pattern):
            beat = bar * 4 + b
            seg = song.seg_at(beat)
            lad = ladder(seg.chord, lo, hi, with_ninth)
            if seg.index not in anchors:
                tgt = 0.55 * prev + 0.45 * center
                anchors[seg.index] = lad.index(nearest_in(lad, tgt))
                prev = lad[anchors[seg.index]]
            m = lad[int(np.clip(anchors[seg.index] + off, 0, len(lad) - 1))]
            v = vel * acc * L * (1.0 + r.normal(0, 0.05))
            ds = d * BEAT_S
            if inst == "marimba":
                y = I.marimba(m, v, var=k, dur=ds + 0.3)
            elif inst == "pluck":
                y = I.pluck(m, ds, v, var=k, t60=kw.get("t60", 1.6), bright=kw.get("bright", 0.45),
                            body=kw.get("body", 1.0))
            elif inst == "celesta":
                y = I.celesta(m, v, var=k, dur=ds + 0.4)
            elif inst == "glass":
                y = I.glass(m, v, var=k, dur=ds + 0.6)
            elif inst == "glock":
                y = I.glock(m, v, var=k, dur=ds + 0.6)
            else:
                raise ValueError(inst)
            p = pan + pan_walk * (((m - lo) / max(hi - lo, 1)) * 2 - 1)
            cv.add(beat * BEAT_S, y, gain, p, send)


def part_lead(cv, song, text, ref, inst="clarinet", vel=0.75, gain=1.0, send=0.3, pan=0.0,
              octave=0, level=None, double=None, double_oct=12, double_gain=0.3, double_min=1.5,
              answer=None, answer_gain=0.25, label="lead", bar_offset=0, events=None, **lead_kw):
    ev = events if events is not None else parse_melody(text, song.key, ref, bar_offset)
    probs = check_melody(ev, song, label)
    if probs:
        raise ValueError("melody/harmony clash:\n  " + "\n  ".join(probs))
    r = rng("lead_part", label)
    notes = []
    for st, d, m in ev:
        bar = int(st // 4)
        L = _lvl(level, bar)
        if L <= 0:
            continue
        pos = st % 4
        acc = 1.0 + (0.07 if pos == 0 else 0.03 if pos == 2 else 0.0) + (0.04 if d >= 2 else 0.0)
        phrase = 0.94 + 0.06 * np.sin(np.pi * ((st % 8) / 8.0))
        v = vel * acc * phrase * L * (1.0 + r.normal(0, 0.025))
        notes.append((st * BEAT_S, d * BEAT_S, m + octave, v))
    if not notes:
        return
    if inst in ("clarinet", "flute", "whistle"):
        y = I.render_lead(notes, inst, seed=label, **lead_kw)
        cv.add(0.0, y, gain, pan, send, human=False)
    else:
        for k, (t, d, m, v) in enumerate(notes):
            fn = {"celesta": I.celesta, "glock": I.glock, "glass": I.glass, "marimba": I.marimba}[inst]
            cv.add(t, fn(m, v, var=k, dur=d + 0.6), gain, pan, send)
    if double:
        fn = {"celesta": I.celesta, "glock": I.glock, "glass": I.glass, "marimba": I.marimba}[double]
        for k, (t, d, m, v) in enumerate(notes):
            if d >= double_min * BEAT_S - 1e-6:
                cv.add(t, fn(m + double_oct, v * 0.9, var=k, dur=d + 0.8), gain * double_gain,
                       pan + 0.25, send * 1.3)
    if answer:
        fn = {"celesta": I.celesta, "glock": I.glock, "glass": I.glass, "marimba": I.marimba}[answer]
        for k, (t, d, m, v) in enumerate(notes):
            if d >= 2 * BEAT_S - 1e-6:
                beat = t / BEAT_S
                seg = song.seg_at(beat + 1.0)
                lad = [x for x in ladder(seg.chord, m + 5, m + 24) if x > m + 4]
                if len(lad) >= 2:
                    for j, (off, x) in enumerate([(1.0, lad[0]), (1.5, lad[1])]):
                        cv.add(t + off * BEAT_S, fn(x, v * (0.75 - 0.1 * j), var=k + j, dur=1.2),
                               gain * answer_gain, pan - 0.35, send * 1.4)


# --------------------------------------------------------------- grooves

def _hits(pat):
    out = []
    for i, ch in enumerate(pat):
        if ch.isdigit() and ch != "0":
            out.append((i, int(ch) / 9.0))
    return out


def part_groove(cv, song, lines, steps=16, level=None, seed="groove"):
    """lines: list of dicts {inst, pat, fill(optional), gain, pan, send, ...}.

    Bars 8 and 16 (and every 8th bar) use `fill` when given.
    """
    r = rng("groove", seed, song.key)
    step_beats = 4.0 / steps
    for bar in range(song.bars):
        L = _lvl(level, bar)
        if L <= 0:
            continue
        for ln in lines:
            pat = ln.get("fill") if (bar % 8 == 7 and ln.get("fill")) else ln["pat"]
            if ln.get("bars") and (bar + 1) not in ln["bars"]:
                continue
            for i, v in _hits(pat):
                beat = bar * 4 + i * step_beats
                vv = v * L * (1.0 + r.normal(0, 0.07))
                inst = ln["inst"]
                var = int(r.integers(0, 4))
                if inst == "tap":
                    y = I.brush_tap(vv, var)
                elif inst == "swell":
                    d = ln.get("len", 1.0) * BEAT_S
                    y = I.brush_swell(d, vv, var)
                    cv.add(beat * BEAT_S - d, y, ln["gain"], ln.get("pan", 0.0), ln.get("send", 0.2))
                    continue
                elif inst == "shk":
                    y = I.shaker(vv, var, ln.get("length", 0.09))
                elif inst == "wbh":
                    y = I.woodblock(ln.get("freq", 1180.0), vv, var, ln.get("tone", 0.0))
                elif inst == "wbl":
                    y = I.woodblock(ln.get("freq", 760.0), vv, var, ln.get("tone", 0.5))
                elif inst == "kick":
                    y = I.soft_kick(vv, var)
                elif inst == "tamb":
                    y = I.tambourine(vv, var)
                elif inst == "clap":
                    y = I.clap(vv, var)
                elif inst == "squeak":
                    ch = song.chord_at(beat)
                    m = nearest_in(ladder(ch, 86, 98), 91)
                    from dsp import midi_hz
                    y = I.squeak(midi_hz(m), 0.15, vv, var, up=ln.get("up", 2.0))
                else:
                    raise ValueError(inst)
                cv.add(beat * BEAT_S, y, ln["gain"], ln.get("pan", 0.0), ln.get("send", 0.15))


# ======================================================================= chapters

CHAPTERS = {
    1: dict(
        name="Open Arms", key="F", ref=65,
        bars=["F", "Dm", "Bb", "C", "F", "Am", "Bb", "Gm7 C", "Dm", "Am", "Bb", "F",
              "Bb", "G7", "Gm7", "C7"],
        melody=("1e 3q 5h ~e | 6q. 5e 3h | 4e 6q 1'h ~e | 7q 6e 7e 5h | 1e 3q 5q 6e 5q | "
                "7q. 5e 3h | 4e 6q 1'q 2'e 1'q | 6q 4e 2e 5h | 6q 1'q 3'q. 2'e | 3'q 2'e 1'e 7h | "
                "1'q. 6e 4h | 5q. 3e 1h | 4e 6q 1'h ~e | 2'q 1'q 6q #4q | 4h 6q 1'q | 5h 4e 3e 2q"),
    ),
    2: dict(
        name="A Warm Welcome", key="D", ref=62,
        bars=["D", "Bm7", "Gmaj7", "A", "D", "F#m", "G", "Em7 D/F#", "Gmaj7", "Gm", "D/F#", "B7",
              "Em7", "E7", "G", "A7"],
        melody=("5,e 1e 3q 5h | 6q 1'e 6e 5h | 4q 6q 3'h | 2'q 1'e 7e 5h | 5,e 1e 3q 5q 6q | "
                "5q. 3e 7,h | 1q 4q 6q 1'q | 6q 4e 2e 3h | 4q. 6e 1'h | b6q 5e 4e 1h | "
                "3q 2e 3e 5h | 6q. 5e #1'h | 2'q 1'e 6e 4h | #4q 6q 2'q 1'q | 6q. 4e 1h | 4q 3q 2q 7,q"),
    ),
    3: dict(
        name="Quiet-ish Hours", key="Bb", ref=70,
        bars=["Bb", "Eb/Bb", "Bb", "F/A", "Gm", "Eb", "Cm7", "F7", "Bb", "D7", "Gm", "Eb",
              "Ebm", "Bb/F", "Cm7", "F7"],
        melody=("1q. 3e 5h | 6q 5q 4h | 3q. 2e 1h | 2q 7,q 5,h | 6,q. 1e 3h | 4q 3q 1h | "
                "2q. 4e 6h | 5q 4q 2q 7,q | 1q. 3e 5h | 3h #5q 7q | 1'h. 6q | 6q 5e 4e 1h | "
                "b6q 4q 1h | 3q. 2e 1h | 2q 4q 6q. 5e | 4q 2q 7,h"),
    ),
    4: dict(
        name="Growing Room", key="G", ref=67,
        bars=["G", "Em7", "Cadd9", "D", "G/B", "C", "Am7", "Dsus4 D", "Em", "Bm7", "C", "G/B",
              "Am7", "A7", "Cmaj7", "D7"],
        melody=("1q. 3q. 5q | 6q. 5q. 3q | 4q. 6q. 1'q | 2'q. 1'e 7q 5q | 1q. 3q. 5q | "
                "6q. 1'q. 2'q | 1'h 6q 4q | 1'q 2'q 7h | 3'q. 1'q. 6q | 5q. 7q. 2'q | 1'h. 6q | "
                "5q. 3q. 1q | 2q. 4q. 6q | #4q. 6q. 1'q | 3'h 1'q 6q | 5q 4q 2q 7,q"),
    ),
    5: dict(
        name="The Other End", key="C", ref=72,
        bars=["C", "G/B", "Am", "F", "C", "E7", "Am", "D7 G", "F", "G", "Em7", "Am", "Dm7", "Bb",
              "F", "G7"],
        melody=("1q. 3e 5q 1'q | 7q. 5e 2q 5q | 6q. 3e 1q 3q | 4q. 6e 1'h | 1'q. 7e 5q 3q | "
                "#5q. 7e 2'q 7q | 1'h 6q 3q | #4q 6q 5q 2q | 1'h 6h | 2'q. 1'e 7q 5q | 7q. 5e 3q 5q | "
                "6q. 5e 3h | 4q. 6e 1'q 6q | b7h 4q 2q | 1q. 3e 4q 6q | 5q 4q 2q 7,q"),
    ),
    6: dict(
        name="Room for Everyone", key="Eb", ref=75,
        bars=["Eb", "Bb/D", "Cm", "Ab", "Eb", "G7", "Cm", "F7 Bb7", "Eb", "Ab", "Fm7", "Gm7",
              "Ab", "Abm", "Eb/Bb", "Bb7"],
        melody=("1e 3q 5h ~e | 5q 4e 3e 2h | 1e 3q 6h ~e | 6q 5e 4e 1h | 1e 3q 5q 6e 5q | "
                "3q. 2e 7,q #5,q | 6,q 1q 3q 6q | #4q 6q 5q 4q | 3h. 1q | 4q. 6e 1'h | 6q 4q 2q 1q | "
                "2q 3q 5q 7q | 1'h 6q 4q | b6q 4q 1h | 3q 2e 1e 5,h | 7,q 2q 4q 2q"),
    ),
}

# arpeggio patterns: (beat, ladder offset, accent, duration in beats)
ALBERTI = [(0.0, 0, 1.0, 0.5), (0.5, 2, 0.62, 0.5), (1.0, 1, 0.78, 0.5), (1.5, 2, 0.62, 0.5),
           (2.0, 3, 0.9, 0.5), (2.5, 2, 0.62, 0.5), (3.0, 1, 0.78, 0.5), (3.5, 2, 0.62, 0.5)]
GUITAR = [(0.0, 0, 1.0, 1.0), (0.5, 2, 0.6, 0.5), (1.0, 3, 0.75, 0.5), (1.5, 1, 0.55, 0.5),
          (2.0, 2, 0.85, 0.5), (2.5, 3, 0.6, 0.5), (3.0, 1, 0.7, 0.5), (3.5, 3, 0.55, 0.5)]
ROCK_TRIP = [(b + i / 3.0, o, a, 0.5) for b in range(4)
             for i, (o, a) in enumerate([(0, 1.0 if b % 2 == 0 else 0.85), (1, 0.6), (2, 0.66)])]
ROCK_TRIP = [(b, (o + (1 if int(b) % 2 else 0)), a, d) for b, o, a, d in ROCK_TRIP]
GROW_332 = [(0.0, 0, 1.0, 1.0), (0.5, 2, 0.55, 0.5), (1.0, 3, 0.6, 0.5), (1.5, 1, 0.9, 1.0),
            (2.0, 3, 0.55, 0.5), (2.5, 2, 0.6, 0.5), (3.0, 4, 0.85, 0.5), (3.5, 2, 0.55, 0.5)]
TRAVEL = [(0.0, 0, 1.0, 0.5), (0.5, 2, 0.6, 0.5), (1.0, 4, 0.8, 0.5), (1.5, 2, 0.6, 0.5),
          (2.0, 1, 0.9, 0.5), (2.5, 3, 0.6, 0.5), (3.0, 4, 0.8, 0.5), (3.5, 3, 0.6, 0.5)]
OFFBEAT_STAB = [(0.5, 0, 0.8, 0.25), (1.5, 1, 0.7, 0.25), (2.5, 0, 0.8, 0.25), (3.5, 1, 0.7, 0.25)]
FESTIVAL = [(0.0, 0, 1.0, 0.5), (0.5, 1, 0.6, 0.5), (1.0, 2, 0.75, 0.5), (1.5, 3, 0.6, 0.5),
            (2.0, 4, 0.9, 0.5), (2.5, 3, 0.6, 0.5), (3.0, 2, 0.75, 0.5), (3.5, 1, 0.6, 0.5)]
STRUM = [(1.0 + 0.03 * j, j, 0.62, 0.8) for j in range(4)] + [(3.0 + 0.03 * j, j, 0.6, 0.8) for j in range(4)]


def chapter_song(c):
    spec = CHAPTERS[c]
    return Song(spec["key"], spec["bars"])


def build_chapter(c):
    """Return {stem: stereo array} (pre-master) for chapter c."""
    spec = CHAPTERS[c]
    song = chapter_song(c)
    beats = song.beats
    ref = spec["ref"]
    mel = spec["melody"]
    S = {k: Canvas(beats=beats, loop=True, seed=f"ch{c}_{k}") for k in ("calm", "move", "busy", "celeb")}
    lab = f"ch{c}"
    if c == 1:
        part_pad(S["calm"], song, "warm", 4, 53, 70, vel=0.4, gain=0.128, send=0.4)
        part_piano(S["calm"], song, "roll", 57, 74, 3, vel=0.55, gain=0.62, send=0.3, bass_lo=36, bass_hi=50)
        part_bass(S["calm"], song, "half", 33, 48, vel=0.55, gain=0.42)
        part_arp(S["move"], song, "marimba", ALBERTI, 65, 89, 76, vel=0.62, gain=0.5, send=0.22, pan_walk=0.35)
        part_groove(S["busy"], song, [
            dict(inst="swell", pat="....4.......4...", gain=0.30, pan=-0.2, send=0.2),
            dict(inst="tap", pat="....6.......6...", fill="....6.......6.5.", gain=0.34, pan=-0.15),
            dict(inst="shk", pat="2.4.2.4.2.4.2.4.", gain=0.308, pan=0.35),
            dict(inst="wbh", pat="..............3.", fill="..........3.3.4.", gain=0.24, pan=0.3,
                 freq=1180.0),
            dict(inst="kick", pat="5.......3.......", gain=0.30),
            dict(inst="squeak", pat="................", fill="...............3", gain=0.10, pan=0.4,
                 bars=[16]),
        ])
        part_lead(S["celeb"], song, mel, ref, "clarinet", vel=0.78, gain=0.42, send=0.32, pan=0.05,
                  double="glock", double_gain=0.22, label=lab)
    elif c == 2:
        part_pad(S["calm"], song, "warm", 4, 52, 69, vel=0.48, gain=0.160, send=0.4, att=0.6, rel=0.9)
        part_piano(S["calm"], song, "roll", 55, 72, 3, vel=0.42, gain=0.5, send=0.3, with_bass=False,
                   roll=0.03)
        part_bass(S["calm"], song, "whole", 33, 48, vel=0.55, gain=0.45)
        part_arp(S["move"], song, "pluck", GUITAR, 57, 81, 67, vel=0.62, gain=0.55, send=0.22,
                 pan=-0.15, pan_walk=0.3, t60=1.8, bright=0.5)
        part_arp(S["move"], song, "glass", [(1.5, 3, 0.6, 1.0), (3.5, 2, 0.5, 1.0)], 76, 93, 84,
                 vel=0.42, gain=0.16, send=0.45, pan=0.4, level=bars_level([(9, 16, 1.0)], 16))
        part_groove(S["busy"], song, [
            dict(inst="swell", pat="....4.......4...", gain=0.28, pan=-0.2, send=0.2),
            dict(inst="tap", pat="....6.......6...", fill="....6.......6.4.", gain=0.32, pan=-0.15),
            dict(inst="shk", pat="3.2.3.2.3.2.3.2.", gain=0.280, pan=0.35),
            dict(inst="wbl", pat="...........3....", fill="......3....3.3..", gain=0.20, pan=0.3,
                 freq=820.0, tone=0.6),
            dict(inst="kick", pat="4...............", gain=0.28),
        ])
        part_lead(S["celeb"], song, mel, ref, "clarinet", vel=0.78, gain=0.45, send=0.3, pan=-0.05,
                  answer="glass", answer_gain=0.30, label=lab, cutoff=2300.0)
    elif c == 3:
        part_pad(S["calm"], song, "warm", 4, 53, 70, vel=0.38, gain=0.136, send=0.45, att=0.8, rel=1.1)
        part_piano(S["calm"], song, "lullaby", 58, 74, 3, vel=0.42, gain=0.55, send=0.38,
                   bass_lo=34, bass_hi=50, pedal=0.6)
        part_bass(S["calm"], song, "whole", 34, 48, vel=0.42, gain=0.34)
        part_arp(S["move"], song, "pluck", ROCK_TRIP, 58, 82, 70, vel=0.5, gain=0.5, send=0.3,
                 pan_walk=0.4, t60=2.2, bright=0.3, body=1.2)
        part_groove(S["busy"], song, [
            dict(inst="swell", pat="...3.....3..", gain=0.26, pan=-0.2, send=0.25, len=1.0),
            dict(inst="tap", pat="...4.....4..", fill="...4.....4.3", gain=0.26, pan=-0.15),
            dict(inst="shk", pat="..2..1..2..1", gain=0.224, pan=0.35, length=0.08),
            dict(inst="wbl", pat="............", fill="......3.....", gain=0.16, pan=0.3,
                 freq=640.0, tone=1.0),
        ], steps=12)
        part_lead(S["celeb"], song, mel, ref, "celesta", vel=0.62, gain=0.36, send=0.4, pan=0.1,
                  octave=12, label=lab)
        part_lead(S["celeb"], song, mel, ref, "clarinet", vel=0.55, gain=0.24, send=0.4, pan=-0.1,
                  label=lab + "_clar", cutoff=1900.0, attack=0.11, vib_cents=6.0)
    elif c == 4:
        part_pad(S["calm"], song, "airy", 4, 52, 71, vel=0.46, gain=0.144, send=0.4, att=0.6, rel=0.9)
        part_piano(S["calm"], song, "roll", 55, 72, 3, vel=0.36, gain=0.38, send=0.3, with_bass=False)
        part_bass(S["calm"], song, "half", 31, 47, vel=0.6, gain=0.5, inst="pluck")
        part_arp(S["move"], song, "pluck", GROW_332, 55, 81, 66, vel=0.6, gain=0.52, send=0.24,
                 pan=-0.2, pan_walk=0.3, t60=2.0, bright=0.55)
        part_arp(S["move"], song, "pluck", [(0.75, 3, 0.45, 0.25), (2.25, 4, 0.45, 0.25)], 67, 88, 78,
                 vel=0.5, gain=0.3, send=0.3, pan=0.45, t60=1.0, bright=0.7, seed="arp_hi")
        part_groove(S["busy"], song, [
            dict(inst="shk", pat="4.2.2.4.2.2.4.2.", gain=0.336, pan=0.35, length=0.11),
            dict(inst="swell", pat="....3.......3...", gain=0.24, pan=-0.25, send=0.2),
            dict(inst="tap", pat="....5.......5...", gain=0.28, pan=-0.15),
            dict(inst="wbl", pat="3.....3.....2...", fill="3.....3...3.3.3.", gain=0.2, pan=-0.3,
                 freq=520.0, tone=1.0),
            dict(inst="kick", pat="4...............", gain=0.26),
        ])
        part_lead(S["celeb"], song, mel, ref, "flute", vel=0.75, gain=0.4, send=0.36, pan=0.05,
                  double="glock", double_gain=0.18, double_min=2.0, label=lab, breath=0.05,
                  vib_cents=11.0, attack=0.07, cutoff=3200.0)
    elif c == 5:
        part_pad(S["calm"], song, "warm", 3, 55, 71, vel=0.36, gain=0.104, send=0.35)
        part_piano(S["calm"], song, "offbeat", 58, 74, 3, vel=0.5, gain=0.45, send=0.22)
        part_bass(S["calm"], song, "bouncy", 33, 50, vel=0.62, gain=0.5)
        part_arp(S["move"], song, "marimba", TRAVEL, 64, 88, 74, vel=0.6, gain=0.48, send=0.2,
                 pan=0.15, pan_walk=0.35)
        part_arp(S["move"], song, "pluck", OFFBEAT_STAB, 62, 79, 70, vel=0.5, gain=0.3, send=0.2,
                 pan=-0.4, t60=0.8, bright=0.6, seed="stab")
        part_groove(S["busy"], song, [
            dict(inst="wbh", pat="5...4...5...4...", fill="5...4...5.4.4.4.", gain=0.24, pan=0.3,
                 freq=1250.0),
            dict(inst="wbl", pat="..3...3...3...3.", gain=0.2, pan=-0.3, freq=830.0, tone=0.4),
            dict(inst="shk", pat="2121212121212121", gain=0.238, pan=0.4, length=0.07),
            dict(inst="tap", pat="....5.......5...", gain=0.28, pan=-0.1),
            dict(inst="kick", pat="5.......4.......", gain=0.3),
            dict(inst="squeak", pat="................", fill="..............3.", gain=0.10, pan=-0.4,
                 bars=[8, 16], up=3.0),
        ])
        part_lead(S["celeb"], song, mel, ref, "clarinet", vel=0.74, gain=0.38, send=0.28, pan=0.0,
                  double="glock", double_gain=0.2, double_min=2.0, label=lab, cutoff=2400.0)
    elif c == 6:
        part_pad(S["calm"], song, "warm", 4, 51, 70, vel=0.42, gain=0.128, send=0.4)
        part_piano(S["calm"], song, "pulse", 55, 72, 3, vel=0.42, gain=0.44, send=0.28,
                   bass_lo=34, bass_hi=50)
        part_bass(S["calm"], song, "bouncy", 31, 48, vel=0.58, gain=0.48)
        part_arp(S["move"], song, "marimba", FESTIVAL, 63, 87, 74, vel=0.58, gain=0.44, send=0.22,
                 pan=0.2, pan_walk=0.3)
        part_arp(S["move"], song, "pluck", STRUM, 55, 74, 63, vel=0.5, gain=0.3, send=0.25, pan=-0.35,
                 t60=1.2, bright=0.5, seed="strum")
        part_arp(S["move"], song, "celesta", [(0.0, 2, 0.6, 1.0), (1.5, 3, 0.5, 0.5)], 82, 96, 88,
                 vel=0.4, gain=0.18, send=0.45, pan=0.5, level=bars_level([(2, 2, 1), (4, 4, 1),
                                                                            (6, 6, 1), (8, 8, 1),
                                                                            (10, 10, 1), (12, 12, 1),
                                                                            (14, 14, 1), (16, 16, 1)], 16))
        part_groove(S["busy"], song, [
            dict(inst="kick", pat="5.......4.......", gain=0.3),
            dict(inst="tamb", pat="....5.......5...", gain=0.2, pan=0.35),
            dict(inst="shk", pat="3.2.3.2.3.2.3.2.", gain=0.252, pan=-0.35),
            dict(inst="swell", pat="....3.......3...", gain=0.22, pan=-0.2, send=0.2),
            dict(inst="tap", pat="....4.......4...", gain=0.22, pan=-0.1),
            dict(inst="clap", pat="............4...", gain=0.16, pan=0.1, send=0.3, bars=list(range(9, 17))),
            dict(inst="wbh", pat="..............3.", fill="..........3.4.4.", gain=0.2, pan=0.3,
                 freq=1100.0),
        ])
        part_lead(S["celeb"], song, mel, ref, "clarinet", vel=0.74, gain=0.36, send=0.3, pan=-0.08,
                  double="glock", double_gain=0.2, double_min=2.0, label=lab, cutoff=2500.0)
        part_lead(S["celeb"], song, mel, ref, "flute", vel=0.62, gain=0.22, send=0.35, pan=0.15,
                  label=lab + "_fl", level=bars_level([(9, 16, 1.0)], 16), breath=0.04, vib_cents=10.0)
    out = {k: cv.mix("hall", wet=0.9 if c != 3 else 1.1) for k, cv in S.items()}
    return balance(out, CHAPTER_LU[c])


# ======================================================================= title / ending / planning

TITLE_BARS = (["Fmaj7", "Bb/F", "Fmaj7", "Gm7 C7"]
              + ["F", "Dm7", "Bb", "C", "Am7", "D7", "Gm7", "C7"]
              + ["F", "Dm7", "Bb", "C", "Am7", "D7", "Gm7 C7", "F"]
              + ["Bb", "C", "Am7", "Dm", "Gm7", "A7", "Dm7", "C7"]
              + ["F", "Dm7", "Bb", "C", "Am7", "D7", "Gm7 C7", "F"]
              + ["Bbmaj7", "Am7", "Gm7", "Fmaj7", "Bbmaj7", "Am7", "Gm7", "Csus4 C"]
              + ["F", "Bb/F", "F", "C7"])

_A1 = "1e 3q 5h ~e | 6q 5e 6e 1'h | 6q 1'q 6q 4q | 5h. rq | 3q 5e 7e 5h | 6q. #1'e 3'h | 2'q 1'q 6q 4q | 5h 4q 3q"
_A2 = ("1e 3q 5h ~e | 6q 5e 6e 1'h | 6q 1'q 2'q 1'q | 2'h. 7q | 3'q 2'e 1'e 7h | #1'q 6q 5q 3q | "
       "4q 2q 5q 7,q")
_B = "4q 6q 1'h | 2'q. 1'e 7h | 5q 7q 3'h | 1'h 6h | 2'q. 1'e 6q 4q | 3q #5q 7q 2'q | 1'h 6q 5q | 4q 3q 2h"

TITLE_MELODY = ("rw | rw | rw | rw | " + _A1 + " | " + _A2 + " | 1h. rq | " + _B + " | " + _A2
                + " | 1q 3q 5q 1'q | " + " | ".join(["rw"] * 8)
                + " | 1e 3q 5h ~e | 6q. 5e 4h | 3q. 2e 1h | rq 5,q 7,q 2q")

ENDING_BARS = (["Fmaj7", "Bbmaj7", "Fmaj7", "C7sus4 C7"]
               + ["F", "Dm7", "Bb", "C", "Am7", "D7", "Gm7", "C7"]
               + ["F", "Dm7", "Bb", "C", "Am7", "D7", "Gm7 C7", "F"]
               + ["Bb", "C", "Am7", "Dm", "Gm7", "A7", "Dm7", "C7"]
               + ["F", "F/C", "Bb", "C7", "F", "Dm7", "Gm7", "C7"])

ENDING_MELODY = ("rw | rw | rw | rw | " + _A1 + " | " + _A2 + " | 1h. rq | " + _B
                 + " | 1h 3h | 5w | 4h 6h | 5h. rq | 1e 3q 5h ~e | 6q. 5e 3h | 4q 2q 6h | 5h 4e 3e 2q")


def _motif_bells(cv, song, bars_roots, inst="glock", gain=0.3, vel=0.7, send=0.45, pan=0.25):
    """bars_roots: list of (bar_1based, root_midi)."""
    fn = {"glock": I.glock, "celesta": I.celesta, "glass": I.glass}[inst]
    for bar, root in bars_roots:
        for k, (b, semi, d) in enumerate(MOTIF):
            cv.add(((bar - 1) * 4 + b) * BEAT_S, fn(root + semi, vel * (0.9 + 0.08 * k), var=k, dur=d * BEAT_S + 1.0),
                   gain, pan, send)


def build_title():
    song = Song("F", TITLE_BARS)
    nb = song.bars
    S = {k: Canvas(beats=song.beats, loop=True, seed=f"title_{k}") for k in ROLE_LU}
    lv = lambda spec: bars_level(spec, nb)
    part_pad(S["calm"], song, "warm", 4, 53, 70, vel=0.4, gain=0.128, send=0.4,
             level=lv([(1, 36, 1.0), (37, 44, 1.15), (45, 48, 1.0)]))
    part_piano(S["calm"], song, "roll", 57, 74, 3, vel=0.5, gain=0.55, send=0.32, bass_lo=36, bass_hi=50,
               level=lv([(1, 4, 0.85), (5, 36, 1.0), (37, 44, 1.1), (45, 48, 0.95)]))
    part_bass(S["calm"], song, "half", 33, 48, vel=0.55, gain=0.4, level=lv([(5, 36, 1.0), (41, 48, 0.9)]))
    part_arp(S["move"], song, "marimba", ALBERTI, 65, 89, 76, vel=0.6, gain=0.4, send=0.22, pan_walk=0.35,
             level=lv([(13, 20, 0.9), (29, 36, 1.0), (45, 48, 0.8)]))
    part_arp(S["move"], song, "pluck", GUITAR, 57, 81, 67, vel=0.58, gain=0.42, send=0.22, pan=-0.2, pan_walk=0.3,
             level=lv([(21, 28, 1.0)]))
    part_groove(S["busy"], song, [
        dict(inst="swell", pat="....4.......4...", gain=0.24, pan=-0.2, send=0.2),
        dict(inst="tap", pat="....6.......6...", fill="....6.......6.5.", gain=0.27, pan=-0.15),
        dict(inst="shk", pat="2.4.2.4.2.4.2.4.", gain=0.238, pan=0.35),
        dict(inst="wbh", pat="..............3.", fill="..........3.3.4.", gain=0.18, pan=0.3),
        dict(inst="kick", pat="5.......3.......", gain=0.22),
    ], level=lv([(13, 36, 1.0), (45, 48, 0.85)]))
    part_groove(S["busy"], song, [
        dict(inst="swell", pat="....3.......3...", gain=0.2, pan=-0.2, send=0.25),
    ], level=lv([(5, 12, 0.9), (37, 44, 0.7)]), seed="title_light")
    part_lead(S["celeb"], song, TITLE_MELODY, 65, "clarinet", vel=0.76, gain=0.36, send=0.32, pan=0.05,
              double="glock", double_gain=0.2, double_min=2.0, label="title",
              level=lv([(5, 20, 1.0), (29, 36, 1.0), (45, 48, 1.0)]))
    part_lead(S["celeb"], song, TITLE_MELODY, 65, "flute", vel=0.72, gain=0.36, send=0.36, pan=0.12,
              label="title_fl", level=lv([(21, 28, 1.0), (29, 36, 0.55)]), breath=0.045, vib_cents=10.0)
    # motif quotes: F-A-C over F/Bbmaj7 bars, Bb-D-F over Bb and Gm7, C-E-G over Am7
    _motif_bells(S["celeb"], song, [(1, 77), (3, 77), (37, 77), (40, 77), (41, 77), (43, 82)],
                 "glock", gain=0.28)
    _motif_bells(S["celeb"], song, [(2, 82), (20, 77), (38, 72), (42, 72)], "celesta", gain=0.2, vel=0.6, pan=-0.3)
    mixes = balance({k: cv.mix("hall", 0.95) for k, cv in S.items()}, ROLE_LU)
    return sum(mixes.values())


def build_ending():
    song = Song("F", ENDING_BARS)
    nb = song.bars
    S = {k: Canvas(beats=song.beats, loop=True, seed=f"ending_{k}") for k in ROLE_LU}
    lv = lambda spec: bars_level(spec, nb)
    part_pad(S["calm"], song, "warm", 4, 53, 70, vel=0.42, gain=0.136, send=0.42)
    part_piano(S["calm"], song, "roll", 57, 74, 3, vel=0.52, gain=0.5, send=0.32, bass_lo=36, bass_hi=50,
               level=lv([(1, 20, 1.0), (21, 28, 0.9), (29, 36, 1.0)]))
    part_piano(S["calm"], song, "pulse", 55, 70, 3, vel=0.36, gain=0.3, send=0.28, with_bass=False,
               level=lv([(21, 36, 1.0)]))
    part_bass(S["calm"], song, "half", 33, 48, vel=0.55, gain=0.4, level=lv([(5, 20, 1.0), (29, 36, 1.0)]))
    part_bass(S["calm"], song, "bouncy", 33, 48, vel=0.55, gain=0.42, level=lv([(21, 28, 1.0)]))
    part_arp(S["move"], song, "marimba", ALBERTI, 65, 89, 76, vel=0.6, gain=0.42, send=0.22, pan_walk=0.35,
             level=lv([(5, 12, 0.8), (13, 20, 1.0), (29, 36, 1.0)]))
    part_arp(S["move"], song, "marimba", FESTIVAL, 63, 87, 74, vel=0.58, gain=0.4, send=0.22, pan=0.2,
             pan_walk=0.3, level=lv([(21, 28, 1.0)]), seed="end_fest")
    part_arp(S["move"], song, "pluck", STRUM, 55, 74, 63, vel=0.5, gain=0.26, send=0.25, pan=-0.35,
             t60=1.2, bright=0.5, seed="end_strum", level=lv([(13, 36, 1.0)]))
    part_groove(S["busy"], song, [
        dict(inst="swell", pat="....4.......4...", gain=0.24, pan=-0.2, send=0.2),
        dict(inst="tap", pat="....6.......6...", fill="....6.......6.5.", gain=0.27, pan=-0.15),
        dict(inst="shk", pat="2.4.2.4.2.4.2.4.", gain=0.238, pan=0.35),
        dict(inst="kick", pat="5.......3.......", gain=0.24),
        dict(inst="wbh", pat="..............3.", fill="..........3.3.4.", gain=0.18, pan=0.3),
    ], level=lv([(5, 36, 1.0)]))
    part_groove(S["busy"], song, [
        dict(inst="tamb", pat="....5.......5...", gain=0.17, pan=0.35),
        dict(inst="clap", pat="............4...", gain=0.13, pan=0.1, send=0.3),
    ], level=lv([(21, 36, 1.0)]), seed="end_fest")
    part_lead(S["celeb"], song, ENDING_MELODY, 65, "clarinet", vel=0.78, gain=0.37, send=0.32, pan=0.05,
              double="glock", double_gain=0.24, double_min=2.0, label="ending",
              level=lv([(5, 20, 1.0), (21, 28, 0.9), (29, 36, 1.05)]))
    part_lead(S["celeb"], song, ENDING_MELODY, 65, "flute", vel=0.66, gain=0.3, send=0.36, pan=0.15,
              label="ending_fl", level=lv([(13, 20, 0.6), (21, 28, 1.0), (29, 36, 0.8)]), breath=0.045)
    _motif_bells(S["celeb"], song, [(1, 77), (3, 77), (29, 77), (31, 82), (33, 77), (33, 89)], "glock", gain=0.28)
    _motif_bells(S["celeb"], song, [(2, 77), (20, 77), (35, 70)], "celesta", gain=0.2, vel=0.6, pan=-0.3)
    mixes = balance({k: cv.mix("hall", 1.0) for k, cv in S.items()}, ENDING_LU)
    return sum(mixes.values())


PLANNING_BARS = ["Fmaj7", "Dm7", "Bbmaj7", "Csus4", "Am7", "Dm7", "Gm7", "Bb/C"]


def build_planning():
    song = Song("F", PLANNING_BARS)
    cv = Canvas(beats=song.beats, loop=True, seed="planning")
    part_pad(cv, song, "warm", 4, 53, 70, vel=0.42, gain=0.160, send=0.5, att=1.0, rel=1.3)
    vo = voice_lead([s.chord for s in song.segments], 4, 57, 76)
    bl = _bass_line(song, 36, 50)
    r = rng("planning_piano")
    # sparse, thoughtful broken chords: bass, then three chord tones spread over the bar
    shapes = [[(0.0, "b"), (1.0, 1), (2.0, 3), (3.5, 2)],
              [(0.0, "b"), (1.5, 2), (2.5, 3)],
              [(0.0, "b"), (1.0, 2), (2.0, 3), (3.0, 1)],
              [(0.0, "b"), (2.0, 2), (3.0, 3)]]
    for i, (seg, v) in enumerate(zip(song.segments, vo)):
        t0 = seg.start * BEAT_S
        for b, w in shapes[i % 4]:
            m = bl[i] if w == "b" else v[w]
            vel = (0.46 if w == "b" else 0.4) * (1.0 + r.normal(0, 0.05))
            d = (4.0 - b) * BEAT_S
            cv.add(t0 + b * BEAT_S, I.felt_piano(m, d, vel, i + b, 0.6), 0.6,
                   -0.2 if w == "b" else 0.15 * (w - 1.5), 0.4)
    # a slow, quiet hint of the welcome motif up high in bars 1 and 5
    for bar, notes in ((1, [(0.0, 77), (1.5, 81), (3.0, 84)]), (5, [(0.0, 76), (1.5, 81), (3.0, 84)])):
        for k, (b, m) in enumerate(notes):
            cv.add(((bar - 1) * 4 + b) * BEAT_S, I.felt_piano(m, 1.6 * BEAT_S, 0.3, k, 0.6), 0.5, 0.25, 0.5)
    return cv.mix("hall", 1.15)


# ======================================================================= stingers

def _sting_canvas(seconds, seed):
    return Canvas(seconds=seconds, loop=False, seed=seed, jitter=0.0)


def build_sting_shift_start():
    """Three-note welcome motif, onsets exactly at 0.0, 1.0 and 2.0 s."""
    cv = _sting_canvas(3.3, "sting_shift")
    notes = [77, 81, 84]          # F5 A5 C6
    for k, m in enumerate(notes):
        t = float(k)
        last = k == 2
        cv.add(t, I.glock(m, 0.82, var=k, dur=1.3 if not last else 1.6), 0.5, 0.1, 0.35, human=False)
        cv.add(t, I.felt_piano(m - 12, 0.9 if not last else 1.2, 0.62, k, 0.3), 0.55, -0.1, 0.3, human=False)
        cv.add(t, I.marimba(m - 12, 0.6, var=k, dur=1.0), 0.25, 0.0, 0.2, human=False)
    # 'go' bloom under the third note: soft F major pad and low F
    for j, m in enumerate([53, 57, 60, 65]):
        cv.add(2.0, I.pad(m, 0.8, 0.5, var=j, att=0.18, rel=0.35), 0.16, -0.3 + 0.2 * j, 0.4, human=False)
    cv.add(2.0, I.felt_piano(41, 1.0, 0.55, 0, 0.3), 0.4, -0.15, 0.25, human=False)
    return cv.mix("hall", 0.8)


def build_sting_wrap():
    """Gentle 'time's up, well done': falling motif then a warm plagal close."""
    cv = _sting_canvas(3.2, "sting_wrap")
    for k, (t, m) in enumerate([(0.0, 84), (0.28, 81), (0.56, 77)]):
        cv.add(t, I.glock(m, 0.6, var=k, dur=1.2), 0.3, 0.2, 0.4, human=False)
    line = [(0.0, 0.26, 72, 0.6), (0.28, 0.26, 69, 0.62), (0.56, 0.6, 65, 0.66), (1.2, 1.4, 69, 0.6)]
    cv.add(0.0, I.render_lead(line, "clarinet", seed="wrap", release=0.25), 0.3, 0.0, 0.3, human=False)
    # Bb/F -> F (plagal "amen"), felt piano
    for j, m in enumerate([53, 58, 62, 65]):
        cv.add(0.56 + 0.02 * j, I.felt_piano(m, 0.62, 0.45, j, 0.2), 0.45, -0.15 + 0.1 * j, 0.3, human=False)
    for j, m in enumerate([41, 53, 57, 60, 65]):
        cv.add(1.2 + 0.03 * j, I.felt_piano(m, 1.5, 0.5, j, 0.5), 0.45, -0.2 + 0.1 * j, 0.35, human=False)
    for j, m in enumerate([53, 57, 60]):
        cv.add(1.2, I.pad(m, 1.2, 0.45, var=j, att=0.3, rel=0.6), 0.12, -0.2 + 0.2 * j, 0.4, human=False)
    return cv.mix("hall", 0.9)


def build_sting_postcard():
    """Sparkly reveal: rising celesta arpeggio into a shimmering bell chord."""
    cv = _sting_canvas(2.5, "sting_postcard")
    seq = [77, 81, 84, 89, 93, 96]
    for k, m in enumerate(seq):
        cv.add(0.065 * k, I.celesta(m, 0.5 + 0.05 * k, var=k, dur=1.0), 0.3, -0.4 + 0.16 * k, 0.45, human=False)
    for j, m in enumerate([77, 81, 84, 89]):
        cv.add(0.45 + 0.012 * j, I.glock(m, 0.6, var=j, dur=1.8), 0.22, -0.3 + 0.2 * j, 0.5, human=False)
    cv.add(0.45, I.felt_piano(53, 1.6, 0.45, 0, 0.4), 0.4, -0.1, 0.3, human=False)
    for j, m in enumerate([57, 60, 65]):
        cv.add(0.45, I.felt_piano(m, 1.6, 0.42, j, 0.4), 0.38, 0.1 * j, 0.3, human=False)
    # airy shimmer: soft high noise swell
    from sfx import shimmer
    cv.add(0.3, shimmer(1.6, seed="postcard"), 0.05, 0.0, 0.3, human=False)
    return cv.mix("hall", 1.0)


def build_sting_unlock():
    cv = _sting_canvas(2.0, "sting_unlock")
    for k, m in enumerate([72, 77, 81, 84]):
        cv.add(0.09 * k, I.marimba(m, 0.6 + 0.06 * k, var=k, dur=0.8), 0.42, -0.3 + 0.2 * k, 0.25, human=False)
    cv.add(0.36, I.glock(89, 0.75, var=0, dur=1.5), 0.32, 0.2, 0.45, human=False)
    cv.add(0.36, I.celesta(84, 0.6, var=1, dur=1.5), 0.25, -0.2, 0.45, human=False)
    from sfx import shimmer
    cv.add(0.3, shimmer(1.1, seed="unlock"), 0.04, 0.0, 0.3, human=False)
    return cv.mix("hall", 0.9)


def build_sting_results():
    """The motif at tempo, then IV-I with the bells ringing over the top."""
    cv = _sting_canvas(4.0, "sting_results")
    line = [(b * BEAT_S, d * BEAT_S * 0.98, 65 + s, 0.75) for b, s, d in MOTIF]
    cv.add(0.0, I.render_lead(line, "clarinet", seed="results", release=0.2), 0.36, 0.0, 0.3, human=False)
    _motif_bells(cv, None, [(1, 77)], "glock", gain=0.3, vel=0.72)
    for j, m in enumerate([41, 53, 57, 60]):
        cv.add(0.0 + 0.02 * j, I.felt_piano(m, 1.4, 0.48, j, 0.3), 0.42, -0.15 + 0.1 * j, 0.3, human=False)
    t2 = 4 * BEAT_S
    for j, m in enumerate([46, 58, 62, 65]):        # Bb
        cv.add(t2 - 2 * BEAT_S + 0.02 * j, I.felt_piano(m, 2 * BEAT_S, 0.45, j, 0.2), 0.4, -0.15 + 0.1 * j, 0.3,
               human=False)
    for j, m in enumerate([41, 53, 57, 60, 65, 69]):  # F
        cv.add(t2 + 0.025 * j, I.felt_piano(m, 1.4, 0.5, j, 0.5), 0.42, -0.25 + 0.1 * j, 0.35, human=False)
    cv.add(t2, I.glock(89, 0.7, var=2, dur=1.6), 0.26, 0.3, 0.5, human=False)
    cv.add(t2 + 0.25 * BEAT_S, I.glock(84, 0.55, var=3, dur=1.4), 0.2, -0.3, 0.5, human=False)
    for j, m in enumerate([53, 57, 60]):
        cv.add(t2, I.pad(m, 1.2, 0.45, var=j, att=0.25, rel=0.6), 0.13, -0.2 + 0.2 * j, 0.4, human=False)
    cv.add(t2, I.render_lead([(0.0, 1.1, 69, 0.66)], "clarinet", seed="results_end", release=0.3),
           0.3, 0.0, 0.3, human=False)
    return cv.mix("hall", 0.95)


def build_sting_star():
    """Single bright note on F5; the game pitch-shifts it per star."""
    cv = _sting_canvas(0.8, "sting_star")
    cv.add(0.0, I.glock(77, 0.8, var=0, dur=0.62), 0.5, 0.0, 0.3, human=False)
    cv.add(0.0, I.celesta(89, 0.5, var=1, dur=0.55), 0.18, 0.0, 0.35, human=False)
    return cv.mix("small", 0.6)
