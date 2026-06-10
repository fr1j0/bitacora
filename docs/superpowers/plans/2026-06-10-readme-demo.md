# README Demo GIF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ~60s animated GIF at the top of the README showing the handoff → `/clear` → resume round-trip, generated deterministically from a scripted scenario.

**Architecture:** A stdlib-only Python generator (`demo/generate.py`) emits an asciinema `.cast` v2 file directly from a scenario data structure — no live recording. A validator (`demo/validate_cast.py`) checks the cast's structure and duration. `demo/build.sh` chains generator → validator → `agg` GIF render and enforces a 3 MB size budget. The GIF and cast are committed; the README embeds the GIF with an honesty caption.

**Tech Stack:** Python 3 (stdlib only), bash, `agg` (`brew install agg`). No asciinema install needed.

**Spec:** `docs/superpowers/specs/2026-06-10-readme-demo-design.md` (all D-numbers below refer to its Key decisions table).

**Branch:** `feature/readme-demo` (already created off `main`; the spec commit is on it).

**Repo:** `~/Projects/bitacora` — all paths below are relative to the repo root. Run `cd ~/Projects/bitacora` first.

---

### Task 1: Cast validator (the test, written first)

The validator is the executable spec for what the generator must produce: a valid cast v2 header, JSON-lines events, monotonic timestamps, `"o"` events only, and a total duration in the 40–80s window. It doubles as a build-time check in Task 3.

**Files:**
- Create: `demo/validate_cast.py`

- [ ] **Step 1: Write the validator**

```python
#!/usr/bin/env python3
"""Validate an asciinema .cast v2 file: JSON-lines, v2 header, "o" events,
monotonic timestamps. Prints event count and duration; exits non-zero on a
structural error or a duration outside the 40-80s README-demo target."""
import json
import sys


def main(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    if not lines:
        print(f"error: {path} is empty", file=sys.stderr)
        return 1
    header = json.loads(lines[0])
    if header.get("version") != 2:
        print("error: not a cast v2 header", file=sys.stderr)
        return 1
    if not (header.get("width") and header.get("height")):
        print("error: header missing width/height", file=sys.stderr)
        return 1
    last = -1.0
    for i, line in enumerate(lines[1:], start=2):
        ev = json.loads(line)
        if not (isinstance(ev, list) and len(ev) == 3):
            print(f"error: line {i}: not a 3-element event", file=sys.stderr)
            return 1
        t, kind, data = ev
        if kind != "o":
            print(f"error: line {i}: unexpected event type {kind!r}", file=sys.stderr)
            return 1
        if not isinstance(data, str):
            print(f"error: line {i}: event data is not a string", file=sys.stderr)
            return 1
        if t < last:
            print(f"error: line {i}: timestamps not monotonic ({t} < {last})",
                  file=sys.stderr)
            return 1
        last = t
    print(f"ok: {len(lines) - 1} events, duration {last:.1f}s")
    if not 40 <= last <= 80:
        print(f"error: duration {last:.1f}s outside 40-80s target", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
```

- [ ] **Step 2: Run it against the not-yet-existing cast to verify it fails**

Run: `python3 demo/validate_cast.py demo/bitacora-demo.cast`
Expected: FAIL — `FileNotFoundError` traceback (the generator doesn't exist yet; this is the red state).

- [ ] **Step 3: Commit**

```bash
git add demo/validate_cast.py
git commit -m "test(demo): cast v2 validator for the README demo"
```

---

### Task 2: Cast generator with the four-scene scenario

Deterministic emitter: a running time accumulator, no wall clock, no randomness (spec D4). The scenario implements the spec's storyboard — title card, mid-work, handoff with on-screen `[CTX]` draft and confirm gate, `/clear`, resume briefing, outro. The on-screen `[CTX]` and briefing shapes are condensed from the shipped v1 format (`docs/JIRA_AGENT_COMMENT_FORMAT.md`, `plugins/bitacora/skills/session-resume/SKILL.md` §4) — never a shape the plugin wouldn't produce.

**Files:**
- Create: `demo/generate.py`

- [ ] **Step 1: Write the generator**

```python
#!/usr/bin/env python3
"""Generate the README demo cast (asciinema v2) from the SCENARIO below.

Deterministic: no wall clock, no randomness -- same input, same bytes out.
Regenerate after editing SCENARIO:
    python3 demo/generate.py > demo/bitacora-demo.cast
or just run demo/build.sh, which also renders the GIF.
"""
import json
import sys

WIDTH, HEIGHT = 100, 30
TYPE_DELAY = 0.045   # seconds per simulated keystroke
LINE_DELAY = 0.06    # seconds between lines of block output

RESET = "\x1b[0m"
BOLD = "\x1b[1m"
DIM = "\x1b[2m"
ORANGE = "\x1b[38;2;217;119;87m"   # Claude orange #D97757
GREEN = "\x1b[38;5;114m"
CLEAR = "\x1b[2J\x1b[H"

PROMPT = ORANGE + "❯ " + RESET          # ❯
DOT = GREEN + "⏺" + RESET               # ⏺


def o(s): return ORANGE + s + RESET
def b(s): return BOLD + s + RESET
def d(s): return DIM + s + RESET


# Scenario ops:
#   ("pause", seconds)  hold the frame
#   ("type", text)      prompt + per-keystroke typing + newline
#   ("print", text)     block output, one line per "\n"
#   ("clear",)          wipe the screen

TITLE = [
    ("clear",),
    ("print", ""),
    ("print", "  " + o(b("Bitácora")) + "  " + d("— every bit of context, logged.")),
    ("print", "  " + d("A [CTX] handoff surviving /clear, in one take:")),
    ("print", ""),
    ("pause", 2.5),
]

SCENE_MIDWORK = [
    ("print", d("  # mid-task on NIMBUS-142 — \"Add retry logic to webhook dispatcher\"")),
    ("print", ""),
    ("pause", 1.0),
    ("type", "retry logic is done and tests pass — I have a meeting, let's wrap up"),
    ("pause", 0.8),
    ("print", DOT + " Nice — exponential backoff retry is in, 14/14 dispatcher tests green."),
    ("print", ""),
    ("pause", 1.5),
]

SCENE_HANDOFF = [
    ("type", "/bitacora:handoff"),
    ("pause", 1.0),
    ("print", DOT + " Reconstructing session… 1 ticket touched."),
    ("print", ""),
    ("pause", 0.8),
    ("print", "  Draft " + b("[CTX]") + " for " + b("NIMBUS-142") + ":"),
    ("print", ""),
    ("print", "    " + b("[CTX] Status update")),
    ("print", ""),
    ("print", "    Status: In Progress"),
    ("print", ""),
    ("print", "    Done:"),
    ("print", ""),
    ("print", "    - Exponential backoff retry in webhook dispatcher (14/14 tests green)"),
    ("print", ""),
    ("print", "    Decisions:"),
    ("print", ""),
    ("print", "    - Capped jittered backoff over fixed interval — avoids thundering herd"),
    ("print", ""),
    ("print", "    Next:"),
    ("print", ""),
    ("print", "    - Dead-letter queue for exhausted retries"),
    ("print", ""),
    ("pause", 6.0),
    ("print", "  Write to NIMBUS-142?  " + d("[approve all] · [review individually] · [cancel]")),
    ("pause", 1.5),
    ("type", "approve all"),
    ("pause", 1.0),
    ("print", DOT + " " + GREEN + "✓" + RESET + " [CTX] posted to NIMBUS-142"),
    ("print", ""),
    ("pause", 2.0),
]

SCENE_CLEAR = [
    ("type", "/clear"),
    ("pause", 0.5),
    ("clear",),
    ("print", ""),
    ("print", d("  ✻ New session — context cleared. Nothing in the window.")),
    ("print", ""),
    ("pause", 2.5),
]

SCENE_RESUME = [
    ("type", "/bitacora:resume NIMBUS-142"),
    ("pause", 1.2),
    ("print", DOT + " Resuming " + b("NIMBUS-142") + " — \"Add retry logic to webhook dispatcher\""),
    ("print", "  " + d("Jira status: In Progress · Last touched: 16 hours ago")),
    ("print", ""),
    ("pause", 0.6),
    ("print", "  " + b("Where you left off:") + "  Retry logic done; dispatcher tests green"),
    ("print", "  " + b("Decisions:") + "           Capped jittered backoff — avoids thundering herd"),
    ("print", "  " + b("Next:") + "                Dead-letter queue for exhausted retries"),
    ("print", ""),
    ("print", "  " + o("Suggested next step:") + " implement the dead-letter queue"),
    ("print", ""),
    ("pause", 4.0),
    ("type", "pick up the next step"),
    ("pause", 1.0),
    ("print", DOT + " Starting on the dead-letter queue for exhausted retries…"),
    ("print", ""),
    ("pause", 2.5),
]

OUTRO = [
    ("clear",),
    ("print", ""),
    ("print", ""),
    ("print", "    " + o(b("Every bit of context, logged."))),
    ("print", ""),
    ("print", "    " + d("github.com/fr1j0/bitacora")),
    ("print", ""),
    ("pause", 3.5),
]

SCENARIO = TITLE + SCENE_MIDWORK + SCENE_HANDOFF + SCENE_CLEAR + SCENE_RESUME + OUTRO


def emit(scenario, out=sys.stdout):
    header = {
        "version": 2,
        "width": WIDTH,
        "height": HEIGHT,
        "title": "Bitácora — handoff → /clear → resume",
        "env": {"TERM": "xterm-256color", "SHELL": "/bin/zsh"},
    }
    out.write(json.dumps(header, ensure_ascii=False) + "\n")
    t = 0.0

    def ev(data):
        out.write(json.dumps([round(t, 3), "o", data], ensure_ascii=False) + "\n")

    for op in scenario:
        kind = op[0]
        if kind == "pause":
            t += op[1]
        elif kind == "clear":
            ev(CLEAR)
        elif kind == "type":
            ev(PROMPT)
            t += 0.3
            for ch in op[1]:
                ev(ch)
                t += TYPE_DELAY
            ev("\r\n")
            t += 0.2
        elif kind == "print":
            for line in op[1].split("\n"):
                ev(line + "\r\n")
                t += LINE_DELAY
        else:
            raise ValueError(f"unknown op: {kind!r}")


if __name__ == "__main__":
    emit(SCENARIO)
```

- [ ] **Step 2: Generate the cast and run the validator (red → green)**

```bash
python3 demo/generate.py > demo/bitacora-demo.cast
python3 demo/validate_cast.py demo/bitacora-demo.cast
```

Expected: `ok: <N> events, duration <D>s` with D between 40 and 80, exit 0. If the duration check fails, adjust the `("pause", …)` values in the scenario — reading pauses (the 6.0s on the `[CTX]` draft, the 4.0s on the briefing) are the right knobs, not typing speed.

- [ ] **Step 3: Spot-check determinism**

```bash
python3 demo/generate.py | shasum
python3 demo/generate.py | shasum
```

Expected: identical hashes on both runs.

- [ ] **Step 4: Commit (generator + cast)**

```bash
git add demo/generate.py demo/bitacora-demo.cast
git commit -m "feat(demo): deterministic cast generator for the README round-trip demo"
```

---

### Task 3: Build script and GIF render

**Files:**
- Create: `demo/build.sh`
- Create (generated): `demo/bitacora-demo.gif`

- [ ] **Step 1: Install agg if missing**

Run: `command -v agg || brew install agg`
Expected: a path to `agg` (after install if needed).

- [ ] **Step 2: Write the build script**

```bash
#!/usr/bin/env bash
# Regenerate the README demo: scenario -> .cast -> .gif, with a size budget.
# Usage: demo/build.sh   (from anywhere; it cd's to its own directory)
set -euo pipefail
cd "$(dirname "$0")"

MAX_BYTES=$((3 * 1024 * 1024))   # 3 MB budget (spec D8)

command -v agg >/dev/null 2>&1 || {
  echo "error: agg not found -- install with: brew install agg" >&2
  exit 1
}

python3 generate.py > bitacora-demo.cast
python3 validate_cast.py bitacora-demo.cast

rm -f bitacora-demo.gif
agg --font-size 16 --fps-cap 20 --theme asciinema \
    bitacora-demo.cast bitacora-demo.gif

bytes=$(wc -c < bitacora-demo.gif | tr -d ' ')
if [ "$bytes" -gt "$MAX_BYTES" ]; then
  echo "error: bitacora-demo.gif is ${bytes} bytes -- over the ${MAX_BYTES}-byte budget" >&2
  exit 1
fi
echo "ok: bitacora-demo.gif (${bytes} bytes)"
```

- [ ] **Step 3: Make it executable and run it**

```bash
chmod +x demo/build.sh
demo/build.sh
```

Expected: `ok: bitacora-demo.gif (<bytes> bytes)`, exit 0. If over budget, lower `--fps-cap` to 15 or `--font-size` to 14 and re-run.

- [ ] **Step 4: Watch the GIF (human gate — spec Verification)**

Run: `open demo/bitacora-demo.gif`
Check: all four scenes legible at README width, the `[CTX]` draft holds long enough to skim, no garbled glyphs (❯ ⏺ ✻ ✓ á —), timing feels natural. Adjust scenario pauses and re-run `demo/build.sh` until it reads well. **This step requires the user's eyes — pause and ask them to watch it before proceeding.**

- [ ] **Step 5: Commit (script + GIF, regenerated cast if it changed)**

```bash
git add demo/build.sh demo/bitacora-demo.gif demo/bitacora-demo.cast
git commit -m "feat(demo): build script + rendered README demo GIF"
```

---

### Task 4: README embed

**Files:**
- Modify: `README.md` (insert directly after the closing `</div>` of the centered header block, before the `> **bit·ácora** —` quote — spec "README integration")

- [ ] **Step 1: Insert the embed + honesty caption**

Find this in `README.md`:

```markdown
</div>

> **bit·ácora** — Spanish for "ship's logbook"
```

Insert between the `</div>` and the quote, so it reads:

```markdown
</div>

<img src="demo/bitacora-demo.gif" alt="Bitácora demo: /bitacora:handoff writes a [CTX] comment to the ticket, /clear wipes the session, /bitacora:resume restores the context" width="100%">

*Scripted demo — output condensed for readability.*

> **bit·ácora** — Spanish for "ship's logbook"
```

(The italic caption is required — spec D6.)

- [ ] **Step 2: Preview the README render**

Run: `grep -n -B2 -A4 'bitacora-demo.gif' README.md`
Expected: the embed sits between `</div>` and the bit·ácora quote with blank lines around the image, caption, and quote. If a markdown previewer is handy (e.g. the GitHub web editor after push), confirm the GIF renders and animates.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): embed the round-trip demo GIF with honesty caption"
```

---

### Task 5: Release-hygiene reminder

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` (append a new section at the end of the file)

- [ ] **Step 1: Append the release-hygiene section**

Add at the end of `MANUAL-ACCEPTANCE.md`:

```markdown
## Release hygiene

- [ ] **README demo still truthful:** if this release changed user-visible
      `/bitacora:handoff` or `/bitacora:resume` output, edit the scenario in
      `demo/generate.py` and re-run `demo/build.sh` so `demo/bitacora-demo.gif`
      matches what ships.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs(checklist): regenerate README demo when handoff/resume output changes"
```

---

### Task 6: Final verification and PR

- [ ] **Step 1: Full clean rebuild from scratch**

```bash
demo/build.sh
git status --short
```

Expected: build succeeds; `git status` shows no diff (the committed cast/GIF are byte-identical to a fresh build — determinism holds end-to-end). If the GIF differs, agg itself is non-deterministic across runs — in that case commit the fresh render and note it; the cast must still be identical.

- [ ] **Step 2: Push and open a PR**

```bash
git push -u origin feature/readme-demo
gh pr create --title "docs: scripted round-trip demo GIF in the README" --body "$(cat <<'EOF'
## Summary
- ~60s scripted asciinema demo (handoff → /clear → resume) embedded at the top of the README
- Deterministic cast generator + agg render pipeline in demo/ (no live recording, fictional data only)
- 3 MB size budget enforced by demo/build.sh; honesty caption under the GIF
- Release-hygiene checklist line: regenerate when handoff/resume output changes

Spec: docs/superpowers/specs/2026-06-10-readme-demo-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed. The GIF renders inline on the PR's Files view — watch it once there as the final check.
