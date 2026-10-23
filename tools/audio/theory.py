"""Music theory helpers: chord symbols, timelines, voice leading, and a small
scale-degree melody notation with a harmony checker.

Melody notation (one string, bars separated by "|"):
    token  = [#|b]degree[' or , ...]duration[.]
    degree = 1..7 of the major key; "'" = octave up, "," = octave down
    duration: w=4 h=2 q=1 e=1/2 s=1/4 t=1/3 (triplet eighth), "." dots it
    "r<dur>" is a rest, "~<dur>" extends (ties) the previous note.
Every bar must add up to exactly 4 beats; the parser asserts it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

BPM = 108.0
BEAT_S = 60.0 / BPM
BEATS_PER_BAR = 4

NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
MAJOR = [0, 2, 4, 5, 7, 9, 11]
QUALITIES = {
    "": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11),
    "m7": (0, 3, 7, 10), "sus4": (0, 5, 7), "sus2": (0, 2, 7), "add9": (0, 4, 7, 14),
    "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9), "dim": (0, 3, 6), "m7b5": (0, 3, 6, 10),
    "9": (0, 4, 7, 10, 14), "maj9": (0, 4, 7, 11, 14), "m9": (0, 3, 7, 10, 14),
    "7sus4": (0, 5, 7, 10),
}
_CHORD_RE = re.compile(r"^([A-G][#b]?)(maj9|maj7|m7b5|m9|m7|m6|7sus4|sus4|sus2|add9|dim|m|9|7|6)?"
                       r"(?:/([A-G][#b]?))?$")


def pc_of(name: str) -> int:
    pc = NOTE_PC[name[0]]
    for ch in name[1:]:
        pc += 1 if ch == "#" else -1
    return pc % 12


@dataclass(frozen=True)
class Chord:
    symbol: str
    root: int
    ivs: tuple
    bass: int

    @property
    def pcs(self) -> frozenset:
        return frozenset((self.root + i) % 12 for i in self.ivs)

    @property
    def core(self) -> tuple:
        """Chord tones for voicing (9ths kept, but as pitch classes)."""
        return tuple(sorted({(self.root + i) % 12 for i in self.ivs}))

    def allowed_melody(self) -> frozenset:
        ok = set(self.pcs)
        q = self.ivs
        if 6 not in q:                       # 9th is a gentle colour except on dim chords
            ok.add((self.root + 2) % 12)
        if q in ((0, 4, 7), (0, 4, 7, 11)):  # added 6th on major
            ok.add((self.root + 9) % 12)
        if q == (0, 4, 7, 10):               # 13th on dominants
            ok.add((self.root + 9) % 12)
        ok.add(self.bass)
        return frozenset(ok)


def parse_chord(sym: str) -> Chord:
    m = _CHORD_RE.match(sym)
    if not m:
        raise ValueError(f"bad chord symbol {sym!r}")
    root = pc_of(m.group(1))
    ivs = QUALITIES[m.group(2) or ""]
    bass = pc_of(m.group(3)) if m.group(3) else root
    return Chord(sym, root, ivs, bass)


@dataclass
class Segment:
    start: float      # beats
    dur: float        # beats
    chord: Chord
    index: int = 0


@dataclass
class Song:
    key: str
    bars_spec: list
    segments: list = field(default_factory=list)

    def __post_init__(self):
        self.key_pc = pc_of(self.key)
        segs = []
        for b, spec in enumerate(self.bars_spec):
            syms = spec.split()
            d = BEATS_PER_BAR / len(syms)
            for j, s in enumerate(syms):
                segs.append(Segment(b * BEATS_PER_BAR + j * d, d, parse_chord(s), len(segs)))
        self.segments = segs

    @property
    def bars(self) -> int:
        return len(self.bars_spec)

    @property
    def beats(self) -> float:
        return self.bars * BEATS_PER_BAR

    def seg_at(self, beat: float) -> Segment:
        beat = beat % self.beats
        for s in self.segments:
            if s.start <= beat + 1e-9 < s.start + s.dur:
                return s
        return self.segments[-1]

    def chord_at(self, beat: float) -> Chord:
        return self.seg_at(beat).chord


# ------------------------------------------------------------- voice leading

def _voicings(chord: Chord, n: int, lo: int, hi: int):
    pcs = list(chord.core)
    root = chord.root
    fifth = (root + 7) % 12
    if len(pcs) > n:                       # drop the fifth (then the root) when crowded
        for drop in (fifth, root):
            if len(pcs) > n and drop in pcs and drop != chord.bass:
                pcs.remove(drop)
    multisets = []
    if len(pcs) == n:
        multisets.append(pcs)
    else:
        for dbl in [root, fifth] + pcs:
            if dbl in pcs:
                ms = pcs + [dbl] * (n - len(pcs))
                if ms not in multisets:
                    multisets.append(ms)
    out = set()
    for ms in multisets:
        choices = []
        for pc in ms:
            choices.append([m for m in range(lo, hi + 1) if m % 12 == pc])

        def rec(i, acc):
            if i == len(choices):
                v = tuple(sorted(acc))
                if len(set(v)) < len(v):
                    return
                gaps = [b - a for a, b in zip(v, v[1:])]
                if gaps and max(gaps) > 12:
                    return
                if v[0] < 55 and gaps and gaps[0] < 3:
                    return
                out.add(v)
                return
            for m in choices[i]:
                rec(i + 1, acc + [m])

        rec(0, [])
    return sorted(out)


def voice_lead(chords, n=4, lo=53, hi=72, center=None, passes=2):
    """Smoothest voicing sequence; run twice so the loop seam is also smooth."""
    center = center if center is not None else (lo + hi) / 2
    prev = None
    result = []
    for p in range(passes):
        result = []
        for ch in chords:
            cands = _voicings(ch, n, lo, hi)
            if not cands:
                raise ValueError(f"no voicing for {ch.symbol} in {lo}..{hi}")

            def cost(v):
                c = 0.35 * abs(sum(v) / len(v) - center)
                gaps = [b - a for a, b in zip(v, v[1:])]
                c += 2.5 * sum(1 for g in gaps if g == 1) + 0.8 * sum(1 for g in gaps if g == 2)
                if prev is not None:
                    c += sum(abs(a - b) for a, b in zip(v, prev))
                    c += 0.6 * max(0, abs(v[-1] - prev[-1]) - 4)
                return c

            best = min(cands, key=cost)
            result.append(best)
            prev = best
    return result


def ladder(chord: Chord, lo: int, hi: int, with_ninth=False):
    pcs = set(chord.pcs) if with_ninth else {(chord.root + i) % 12 for i in chord.ivs if i < 12}
    return [m for m in range(lo, hi + 1) if m % 12 in pcs]


def nearest_in(cands, target):
    return min(cands, key=lambda m: (abs(m - target), m))


# ------------------------------------------------------------- melody

_DUR = {"w": 4.0, "h": 2.0, "q": 1.0, "e": 0.5, "s": 0.25, "t": 1.0 / 3.0}
_TOK = re.compile(r"^([#b]?)([1-7])([',]*)([whqest])(\.?)$")


def _dur(s: str) -> float:
    d = _DUR[s[0]]
    if s.endswith("."):
        d *= 1.5
    return d


def parse_melody(text: str, key: str, ref: int, bar_offset: int = 0):
    """Return a list of [start_beat, dur_beats, midi] (mutable for ties)."""
    key_pc = pc_of(key)
    assert ref % 12 == key_pc, f"melody ref {ref} is not the tonic of {key}"
    events = []
    bars = [b.strip() for b in text.split("|")]
    for bi, bar in enumerate(bars):
        t0 = (bi + bar_offset) * BEATS_PER_BAR
        t = t0
        for tok in bar.split():
            if tok[0] == "r":
                t += _dur(tok[1:])
                continue
            if tok[0] == "~":
                d = _dur(tok[1:])
                events[-1][1] += d
                t += d
                continue
            m = _TOK.match(tok)
            if not m:
                raise ValueError(f"bad melody token {tok!r} in bar {bi + 1}")
            acc, deg, octs, dch, dot = m.groups()
            semis = MAJOR[int(deg) - 1] + (1 if acc == "#" else -1 if acc == "b" else 0)
            semis += 12 * (octs.count("'") - octs.count(","))
            d = _dur(dch + dot)
            events.append([t, d, ref + semis])
            t += d
        if abs((t - t0) - BEATS_PER_BAR) > 1e-6:
            raise ValueError(f"bar {bi + 1 + bar_offset} of melody sums to {t - t0} beats: {bar!r}")
    return events


def check_melody(events, song: Song, label: str):
    """Structural notes (on beats 1/3, at a chord change, or >= 1 beat long)
    must be chord tones or gentle tensions.  Returns a list of problems."""
    problems = []
    for st, d, m in events:
        pc = m % 12
        for seg in song.segments:
            a = max(st, seg.start)
            b = min(st + d, seg.start + seg.dur)
            if b - a <= 1e-9:
                continue
            strong = False
            if abs(a - seg.start) < 1e-9:
                strong = True
            for beat in (0.0, 2.0):
                bpos = (a // 4) * 4 + beat
                if a - 1e-9 <= bpos < b - 1e-9:
                    strong = True
                if bpos + 4 < b - 1e-9 and bpos + 4 >= a:
                    strong = True
            if b - a >= 1.5 - 1e-9:
                strong = True
            if strong and pc not in seg.chord.allowed_melody():
                problems.append(f"{label}: bar {int(st // 4) + 1} beat {st % 4 + 1:.2f} "
                                f"midi {m} over {seg.chord.symbol}")
    return problems
