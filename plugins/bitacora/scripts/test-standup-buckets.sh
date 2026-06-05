#!/usr/bin/env bash
# Deterministic tests for standup-buckets.sh. Reference epochs (UTC noon) reused
# from test-since-window.sh:
#   2024-01-04 Thu, 2024-01-05 Fri, 2024-01-06 Sat, 2024-01-07 Sun,
#   2024-01-08 Mon, 2024-01-09 Tue.  Plus Friday UTC midnight as a boundary case.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SB="$DIR/standup-buckets.sh"
fail=0

check() {  # desc, expected, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$SB" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local code
  bash "$SB" "$@" >/dev/null 2>&1; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

check "Thu noon"               "19726 Thursday"  1704326400
check "Fri noon"               "19727 Friday"    1704456000
check "Sat noon"               "19728 Saturday"  1704542400
check "Sun noon"               "19729 Sunday"    1704628800
check "Mon noon"               "19730 Monday"    1704715200
check "Tue noon"               "19731 Tuesday"   1704801600
check "Fri midnight (boundary)" "19727 Friday"   1704412800

check_err "missing epoch"
check_err "non-numeric"  abc
check_err "negative"     -5

exit $fail
