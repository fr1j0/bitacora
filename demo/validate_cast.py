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
