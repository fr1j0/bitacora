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
