#!/usr/bin/env bash
# Deterministic tests for staleness-check.sh. Fixed reference timestamps; no wall clock.
#   CTX = 2024-01-09 12:00:00 UTC = 1704801600
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SC="$DIR/staleness-check.sh"
fail=0

check() {  # desc, expected_stdout, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$SC" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local out code
  out="$(bash "$SC" "$@" 2>/dev/null)"; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

CTX=1704801600
D1=86400     # 1 day
D2=172800    # 2 days (the default grace)

check "updated == ctx → fresh"              fresh      --ctx-epoch "$CTX" --updated-epoch "$CTX"
check "updated < ctx (skew) → fresh"        fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX-3600))"
check "drift 1d within 2d grace → fresh"    fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX+D1))"
check "drift exactly 2d boundary → fresh"   fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX+D2))"
check "drift 2d+1s → stale 2d"              "stale 2d" --ctx-epoch "$CTX" --updated-epoch "$((CTX+D2+1))"
check "drift 4d → stale 4d"                 "stale 4d" --ctx-epoch "$CTX" --updated-epoch "$((CTX+4*D1))"
check "grace 12h, drift 1d → stale 1d"      "stale 1d" --ctx-epoch "$CTX" --updated-epoch "$((CTX+D1))" --grace 12h
check "grace 7d, drift 4d → fresh"          fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX+4*D1))" --grace 7d

check_err "missing --ctx-epoch"    --updated-epoch "$((CTX+D2+1))"
check_err "non-numeric --updated"  --ctx-epoch "$CTX" --updated-epoch abc
check_err "bad grace token"        --ctx-epoch "$CTX" --updated-epoch "$((CTX+D2+1))" --grace 2x

exit $fail
