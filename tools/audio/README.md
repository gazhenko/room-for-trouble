# Room for Trouble procedural audio

All music, sound effects and voice syllables in `assets/export/audio/` come from
code in this folder. Nothing is sampled or downloaded, and no commercial melody
is quoted. Every random source uses a fixed seed, and `oggenc` gets a fixed
stream serial per cue, so a rebuild is byte-identical.

## Regenerate

Run from the repository root:

```sh
python3 -m venv tools/audio/.venv
tools/audio/.venv/bin/pip install -r tools/audio/requirements.txt
tools/audio/.venv/bin/python tools/audio/synth.py
```

Requirements:

- Python 3.14
- numpy, pinned in `requirements.txt`
- `oggenc` and `oggdec` from vorbis-tools (`brew install vorbis-tools`)

A full build takes about 40 s on a 10-core Mac. The script writes the following
into `assets/export/audio/`:

- `music/*.ogg` (Ogg Vorbis `-q 5`, stereo)
- `sfx/*.ogg` (`-q 4`, mono)
- `voice/*.ogg` (`-q 4`, mono)
- `audio_manifest.json`
- `REGISTER.md`

It also deletes any stale `.ogg` in those three folders. Intermediate WAVs only
ever exist in a temporary directory.

Options:

| Option | Effect |
| --- | --- |
| `--jobs N` | Number of worker processes. |
| `--only ch3,bell` | Render only ids containing these substrings, for iteration. Skips the manifest, register and cleanup. |
| `--report qa.json` | Write the full QA metrics. |
| `--keep-wav DIR` | Keep the pre-encode float WAVs. |

The exit code is non-zero if any check fails.

## What the script verifies

Every file is decoded again with `oggdec` (the reference decoder) and checked:

- the exact sample count matches what was rendered
- sample peak and 4x-oversampled true peak are both at or below −1 dBFS
- there is no DC offset and no NaN/Inf
- loops are click-free: the wrap-around step is compared with the 99.9th
  percentile of the file's own sample steps
- for music loops, the RMS step across the seam is compared with the RMS step
  across every other bar line in the loop

For each chapter it also sums the four decoded stems, and every one of their 15
subsets. Each sum must stay at or below −1 dBFS.

The countdown stinger's onsets are measured and must land at 0, 1 and 2 s.

## Layout

| File | Contents |
| --- | --- |
| `dsp.py` | FFT-domain analog-prototype filters (circular for loops), STFT time-varying filters, vectorised Karplus–Strong, synthetic stereo room IR, soft-knee look-ahead limiter, K-weighted loudness, true peak, float WAV writer. |
| `instruments.py` | Felt piano (soft hammer, string pairs, fast decay of high partials), marimba, woodblock, plucked strings (Karplus–Strong), celesta, glockenspiel, glassy bells, lobby desk bell, warm/airy pads, soft and bouncy bass, clarinet/flute lead lines (odd harmonics, delayed gentle vibrato, soft attack, breath), brush taps, brush swells (filtered-noise swells), shaker, soft kick, tambourine, claps, suitcase squeak. |
| `theory.py` | Chord symbols, voice leading (minimal motion, and run twice so the loop seam is smooth too), scale-degree melody notation, and a melody/harmony clash checker that fails the build on a clash. |
| `music.py` | Arrangement parts, the six chapters, the title, planning and ending loops, and the stingers. |
| `sfx.py` | Every SFX, guest, staff and incident cue, plus the formant-synthesised voice syllables. |
| `synth.py` | Parallel rendering, mastering, encoding, verification, manifest and register. |

## Musical design

All cues run at 108 BPM in 4/4, so one beat is exactly 24,500 samples.

The welcome motif is root, major third, fifth, with onsets on beats 0, ½ and 1½
("da da-DAAA"). In F it is F A C. It appears in these cues:

- the lobby bell (`sfx/bell_ring`, desk bell F6 A6 C7)
- the title (intro, breakdown and outro bells, and the theme's opening)
- `sting_shift_start`: F5 A5 C6, exactly 1.0 s apart for the 3-2-1 countdown
- `sting_results`
- `ending`: the full motif plus an augmented statement in the finale
- the opening of chapters 1 and 6

The six chapters share one structure:

- 16 bars; each stem is exactly 1,568,000 samples.
- Four phase-aligned stems: calm (pad, felt piano, bass), move (ostinato), busy
  (brushes, woodblocks, shaker) and celeb (melody plus bells).
- The stems share one chord timeline, so any combination is consonant.
- Loops are rendered circularly: note tails, reverb and filters wrap past the
  end back onto the start.

| Chapter | Key | Character |
| --- | --- | --- |
| 1 "Open Arms" | F | Marimba Alberti and felt piano, clarinet lead. |
| 2 "A Warm Welcome" | D | Clarinet answered by glassy bells; borrowed iv (Gm) as the cool colour. |
| 3 "Quiet-ish Hours" | B♭ | Lullaby: 12/8-feel rocking harp, celesta lead doubled by a soft clarinet, mastered quieter. |
| 4 "Growing Room" | G | Plucked-string 3+3+2 ostinato, airy flute lead. |
| 5 "The Other End" | C | Bouncy oom-pah bass, woodblock clip-clop, ♭VII lift. |
| 6 "Room for Everyone" | E♭ | Festival: pulse piano, strums, tambourine, claps, clarinet with flute in the second half. |

### Levels

| Material | Level |
| --- | --- |
| Chapter stems | Balanced by gated K-loudness per role. Loudest stem peaks near −6.5 dBFS (−8.5 dBFS in chapter 3). |
| Title, ending, planning | Matched to the chapters' full-mix loudness. |
| Stingers | −3 dBFS peak; `sting_star` −5 dBFS. |
| SFX and voices | −3 to −6 dBFS peak. Sustained tonal cues sit nearer −6 so they don't jump out above foley. |
| UI | −8 dBFS. |
| Voice syllables | All 220 Hz and matched in K-loudness. |

For the chapter stems, one linked soft-knee limiter driven by the worst-case
subset sum keeps every stem combination under −2 dBFS before encoding.

## Manifest

`assets/export/audio/audio_manifest.json` holds a `cues` array. Every cue has:

- `id`, `path` (`res://…`)
- `bus`: `Music`, `Effects`, `Voices` or `UI`
- `loop`
- `length_s`, plus the exact `samples`, `sample_rate` and `channels`
- `peak_dbfs` and `true_peak_dbfs`, both measured on the decoded file

Music cues also carry `bpm`, `bars`, `chapter` (0 for non-chapter cues) and
`stem`. `stem` is one of `calm`, `move`, `busy` or `celeb` for chapters, `full`
for the title, planning and ending, and `sting` for stingers.

A few cues carry extra fields:

| Cue | Extra fields |
| --- | --- |
| `sting_shift_start` | `onsets_s` |
| `sting_star` | `base_note: "F5"`. Pitch scales 1, 1.26 and 1.498 play the motif. |
| Voice syllables | `syllable`, `base_hz` |

Godot imports `.ogg` files with looping off, so the player should set
`AudioStreamOggVorbis.loop` from the manifest's `loop` flag. Crossfade chapter
stems only on bar boundaries, which fall every 98,000 samples.
