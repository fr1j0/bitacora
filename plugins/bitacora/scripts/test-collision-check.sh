#!/usr/bin/env bash
# Deterministic tests for collision-check.sh. A fixed reference "now" is injected
# via --now so results never depend on the wall clock.
#   NOW = 2024-01-09 12:00:00 UTC = 1704801600
#   Default window 48h → cutoff = NOW - 172800 = 1704628800 (2024-01-07 12:00 UTC).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CC="$DIR/collision-check.sh"
fail=0

check() {  # desc, expected_stdout, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$CC" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local out code
  out="$(bash "$CC" "$@" 2>/dev/null)"; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

NOW=1704801600              # 2024-01-09 12:00 UTC
H3=$((NOW - 10800))         # 3h ago  (within 48h)
H2=$((NOW - 7200))          # 2h ago
CUTOFF=1704628800           # NOW - 48h (exact boundary)
JUST_OUT=$((CUTOFF - 1))    # 1s before the 48h boundary
TWO_DAYS=$((NOW - 172800))  # exactly 48h ago (== CUTOFF)

check "author=me → clear"                    clear     --me u1 --latest-author u1 --latest-epoch "$H3" --now "$NOW"
check "takeover (no mine-epoch), in window"  collision --me u1 --latest-author u2 --latest-epoch "$H3" --now "$NOW"
check "other newer than mine, in window"     collision --me u1 --latest-author u2 --latest-epoch "$H2" --mine-epoch "$H3" --now "$NOW"
check "mine newer than other → clear"        clear     --me u1 --latest-author u2 --latest-epoch "$H3" --mine-epoch "$H2" --now "$NOW"
check "other at 48h boundary → collision"    collision --me u1 --latest-author u2 --latest-epoch "$CUTOFF" --now "$NOW"
check "other 1s past window → clear"         clear     --me u1 --latest-author u2 --latest-epoch "$JUST_OUT" --now "$NOW"
check "1d window, 2d-old other → clear"      clear     --me u1 --latest-author u2 --latest-epoch "$TWO_DAYS" --window 1d --now "$NOW"
check "7d window, 2d-old other → collision"  collision --me u1 --latest-author u2 --latest-epoch "$TWO_DAYS" --window 7d --now "$NOW"

check_err "missing --me"             --latest-author u2 --latest-epoch "$H3" --now "$NOW"
check_err "missing --latest-author"  --me u1 --latest-epoch "$H3" --now "$NOW"
check_err "non-numeric latest-epoch" --me u1 --latest-author u2 --latest-epoch abc --now "$NOW"
check_err "bad window token"         --me u1 --latest-author u2 --latest-epoch "$H3" --window 48x --now "$NOW"

exit $fail
