# Design — Scripted asciinema demo GIF for the README

**Date:** 2026-06-10
**Status:** Approved design, ready for implementation planning
**Touches:** new `demo/` directory (`generate.py`, `build.sh`, `bitacora-demo.cast`, `bitacora-demo.gif`), `README.md` (embed + caption)

## Summary

The hardest thing about Bitácora's pitch is that "Jira as a shared memory layer" is
abstract until you *see* a handoff survive `/clear`. The README has no demo today; a
~60–75s animated GIF at the top — showing the tight **handoff → `/clear` → resume**
round-trip — does more for adoption than any docs page, and was judged higher-leverage
than a documentation website while the command surface is still settling in `0.x`.

The demo is a **scripted replay, not a live recording**: a stdlib-only Python generator
emits an asciinema `.cast` v2 file directly from a scenario data structure, and `agg`
renders it to a GIF. Fully deterministic and regenerable — when `/handoff` or `/resume`
output changes in a release, edit the scenario block and re-run one script.

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Scripted replay, not a real session capture** | Real Claude Code takes vary per run, are slow to capture cleanly, and risk leaking real Jira/account data on screen. A curated replay is fully controlled and reproducible across `0.x` churn. Disclosed honestly (see D6). |
| D2 | **GIF via `agg`, embedded inline** | GitHub READMEs can't run the asciinema JS player. An inline GIF autoplays with zero clicks — README skimmers actually see it. asciinema.org link-outs lose most viewers to the click-through and add a third-party dependency. |
| D3 | **Tight round-trip only — no command tour** | One continuous story (~60–75s): mid-work → handoff → `/clear` → resume. The drafted `[CTX]` comment shown during handoff doubles as a demo of the format contract. A multi-command tour is longer, loses skimmers, and goes stale fastest while flags churn. |
| D4 | **Cast generator script (`demo/generate.py`), no live recording in the pipeline** | Emitting `.cast` v2 JSON directly from a scenario data structure is byte-deterministic, has no terminal/timing quirks, and needs no asciinema install. The alternative (demo-magic-style typed shell script under `asciinema rec`) hand-crafts the same strings with less determinism. |
| D5 | **Commit the `.gif` and `.cast` to the repo** | Self-contained — no third-party host, consistent with the project's no-external-trust stance. The `.cast` is tiny and lets anyone `asciinema play` it. GIF size budget keeps repo bloat bounded (D8). |
| D6 | **Honesty caption under the GIF** | Italic caption: *"Scripted demo — output condensed for readability."* A staged recording presented as real would cut against the trust posture (no telemetry, no auto-update, confirmation-gated writes) the README leads with. |
| D7 | **Fictional data only** | Ticket `NIMBUS-142` ("Add retry logic to webhook dispatcher"), no real Jira site URL, no real account names. Nothing on screen to redact, ever. |
| D8 | **Size budget < 3 MB, enforced by `build.sh`** | Inline GIFs over a few MB hurt README load time. Controlled via terminal geometry (100×30), fps cap, and scene length; the build fails loudly if exceeded so it can't regress silently. |
| D9 | **Approximate the Claude Code look, don't pixel-clone it** | Prompt marker, dim/bold ANSI, spinner line, Claude-orange accents — instantly recognizable, cheap to maintain. A pixel-faithful clone of the TUI (boxes, redraws) is fiddly in a hand-authored cast and breaks on every UI tweak. |

## Storyboard

One continuous fictional session on `NIMBUS-142`, four scenes:

1. **Mid-work (~8s)** — a session with visible context. User: *"retry logic is done and
   tests pass — I have a meeting, let's wrap up."* Establishes there is real state worth
   saving.
2. **Handoff (~25s)** — `/bitacora:handoff` runs. The drafted `[CTX]` comment renders on
   screen (`Status:` / `Done:` / `Decisions:` / `Next:` / `Parked:`), the confirmation
   gate appears (*"Write to NIMBUS-142?"*), user confirms, `✓ [CTX] posted to NIMBUS-142`.
   This scene also demos the format contract and the confirmation-gated-writes posture.
3. **The wipe (~5s)** — `/clear`. Fresh empty session; a visible beat of "all context
   gone."
4. **Resume (~20s)** — next session: `/bitacora:resume NIMBUS-142` → briefing renders
   (where you left off, decisions, next step). User: *"pick up the next step"* — Claude
   continues as if nothing happened. Closing frame: tagline (*Every bit of context,
   logged.*) + repo URL.

The on-screen `[CTX]` draft and resume briefing must match the **shipped v1 format**
(`docs/JIRA_AGENT_COMMENT_FORMAT.md` and the skill files are the source of truth) —
condensed for screen, but never showing a shape the plugin wouldn't actually produce.

## Mechanics

New `demo/` directory:

- **`demo/generate.py`** — stdlib-only Python. A scenario data structure at the top
  (lines, ANSI styling, per-event timing), an emitter below that writes a valid
  asciinema `.cast` v2 file (header + timed `"o"` events). User input is simulated with
  per-keystroke events; Claude output prints in blocks with natural pauses. No
  randomness, no wall-clock reads — same input, same bytes out.
- **`demo/build.sh`** — runs `generate.py` → `demo/bitacora-demo.cast`, then
  `agg` → `demo/bitacora-demo.gif` (geometry 100×30, dark theme, fps-capped). Exits
  non-zero if `agg` is missing (points at `brew install agg`), if rendering fails, or if
  the GIF exceeds the 3 MB budget.
- **Committed artifacts:** `generate.py`, `build.sh`, the `.cast`, and the `.gif`.

## README integration

GIF embedded directly under the badges/tagline block, before "At a glance":

```markdown
<img src="demo/bitacora-demo.gif" alt="Bitácora demo: /bitacora:handoff writes a [CTX] comment, /clear wipes the session, /bitacora:resume restores the context" width="100%">

*Scripted demo — output condensed for readability.*
```

## Maintenance

When a release changes `/handoff` or `/resume` user-visible output, edit the scenario
block in `generate.py` and re-run `demo/build.sh`. The release checklist (wherever
release steps live) gains one line: *"Does the README demo still match shipped output?
If not, regenerate."*

## Verification

`build.sh` is self-checking (agg present, render succeeds, size budget). Final gate is
human: watch the GIF once before committing — timing and readability are judgment calls
no script can make. No automated tests beyond that; it's a docs artifact.

## Out of scope

- A documentation website (revisit at v1.0 — generate from repo markdown, single source
  of truth).
- A worked-example walkthrough in `docs/` (good follow-up, separate effort).
- Demos of `status` / `digest` / `next` / `improve` (a command tour was considered and
  rejected, D3).
- Uploading to asciinema.org (rejected, D2/D5; can be added later without rework).
