# Family playtest report

## Status: no human playtest sessions have been conducted

The brief asks for at least three 15–30 minute family usability sessions (§24.3):
- mixed adult and child abilities
- two adults or friends who are unfamiliar with the game
- a solo first-time player

These sessions have **not** happened. The build was made in an automated development
environment with no access to players, children or physical controllers. Nothing in this
repository should be read as evidence that families enjoy the game, understand it, or find it
fair. Those are open questions until real sessions are run.

The game is ready for those sessions. This document gives the procedure, the observation
sheet, and what automated testing does and does not tell us.

## What automated testing shows (and doesn't)

The reference driver (`src/dev/reference_bot.gd`) plays all 24 shifts at 1–4 player counts and
Busy pace, plus six deliberately imperfect runs. The full results are in
`docs/REFERENCE_RUNS.md`. The runs show:

- **Every shift finishes at every player count**, and progress unlocks even after poor
  runs. There are no soft locks, and no shift needs two humans.
- **Recovery works mechanically.** In the imperfect runs (a dropped ticket, a teammate
  absent for 45–60 s, the team distracted for 40 s) the shift still finishes, recoveries
  happen and the next story unlocks.
- **Pressure is bounded.** The director never ran more than two incidents at once, and
  stock never ran out in any run.

They do **not** show whether:
- a 7-year-old can find a useful job within 30 s
- players understand curtains versus vents
- incidents cause laughter or confusion
- anyone wants another round

The bot never laughs, never gets confused and never feels left out.

## Procedure for the first three sessions

**Before the session**
1. Use a packaged build on the target machine. Start a fresh profile by deleting
   `profiles/couch.json*` in the user-data folder, or use a new OS user.
2. Prepare controllers: at least two controllers plus the keyboard. Charge or connect them.
3. Ask for ordinary consent from each adult, and from parents for any children. Explain that
   it is the game being tested, not them, and that anyone can stop at any time. Collect no
   personal data about children: no names, ages to the year, photos or recordings of faces.
   Use "Child A, about 8" style notes.

**During the session (15–30 minutes)**
1. Let the group choose **Play Together → This Couch**, join seats and accept Nana's offer
   to play T01. Give no other instructions.
2. After the tutorial, **observe without coaching.** Only answer "how do I quit" or
   controller hardware questions.
3. Play L01–L03 (session 1), L05–L07 (session 2, starting from a prepared profile with
   chapter 1 complete), or whatever the solo player chooses (session 3).
4. Note timestamps for the moments on the sheet below. Do not interrupt to ask questions
   mid-shift.

**After the session (5 minutes)**
Ask each participant:
- "What was your favourite thing you did?"
- "Was anything confusing?"
- For curtains and vents: "What does the curtain do? What does the little arrow gate do?"
- "Would you like to play another shift?"

Record the answers verbatim, or as close as possible.

## Observation sheet

| Question (§24.3) | Session 1 | Session 2 | Session 3 |
|---|---|---|---|
| Did the beginner find one useful job within 30 s? (time to first useful action) | | | |
| Can players explain curtain versus vent gate? | | | |
| Did someone voluntarily rescue or finish another person's work? (count and example) | | | |
| Did incidents create laughter, or confusion and loss of control? (timestamps) | | | |
| Could the group continue after a poor result without feeling shut out? | | | |
| Did every participant report one contribution they felt good about? | | | |
| Did the group voluntarily ask for another shift? | | | |
| Silent or frustrated moments, or anyone stuck in a boring job (what and when) | | | |
| Readability problems (text, icons, glyphs, colours) | | | |
| Controller or hardware problems | | | |

## Acting on findings

The brief's rule: if a player cannot explain what happened, improve feedback **before**
increasing a timer. Record every resulting change in `docs/TUNING_LOG.md`. Give the level or
system, the previous and new values, the observed issue, the affected player counts, the
invariants rechecked, and the test or replay evidence. Then re-run:

```bash
python3 tools/validate_manifest.py data/campaign_manifest.json
godot --headless --path . --script res://tests/run_all.gd
godot --headless --path . --script res://tools/dev/reference_runs.gd
```

## Session log

*(empty — add one section per real session: date, group make-up without personal data,
build hash from `VERSION.txt`, levels played, and the completed observation sheet)*
