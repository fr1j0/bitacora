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
