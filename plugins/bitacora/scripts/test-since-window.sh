#!/usr/bin/env bash
# Deterministic tests for since-window.sh. A fixed reference "now" is injected as
# arg 2 so results never depend on the wall clock. Reference dates (UTC):
#   2024-01-05 = Friday, 2024-01-06 = Saturday, 2024-01-07 = Sunday,
#   2024-01-08 = Monday,  2024-01-09 = Tuesday.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SW="$DIR/since-window.sh"
fail=0

check() {  # desc, expected_epoch, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$SW" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local out code
  out="$(bash "$SW" "$@" 2>/dev/null)"; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

NOW_TUE=1704801600   # 2024-01-09 12:00:00 UTC (Tuesday)
NOW_MON=1704715200   # 2024-01-08 12:00:00 UTC (Monday)
NOW_SUN=1704628800   # 2024-01-07 12:00:00 UTC (Sunday)
NOW_SAT=1704542400   # 2024-01-06 12:00:00 UTC (Saturday)
NOW_FRI=1704456000   # 2024-01-05 12:00:00 UTC (Friday)
FRI_MID=1704412800   # 2024-01-05 00:00:00 UTC (Friday midnight)
MON_MID=1704672000   # 2024-01-08 00:00:00 UTC (Monday midnight)
THU_MID=1704326400   # 2024-01-04 00:00:00 UTC (Thursday midnight)

check "1d from Tue noon"        "$((NOW_TUE - 86400))"   1d "$NOW_TUE"
check "2d from Tue noon"        "$((NOW_TUE - 172800))"  2d "$NOW_TUE"
check "7d from Tue noon"        "$((NOW_TUE - 604800))"  7d "$NOW_TUE"
check "last-working-day on Tue" "$MON_MID" last-working-day "$NOW_TUE"
check "last-working-day on Mon" "$FRI_MID" last-working-day "$NOW_MON"
check "last-working-day on Sun" "$FRI_MID" last-working-day "$NOW_SUN"
check "last-working-day on Sat" "$FRI_MID" last-working-day "$NOW_SAT"
check "last-working-day on Fri" "$THU_MID" last-working-day "$NOW_FRI"

check_err "unknown token"    next-week          "$NOW_TUE"
check_err "zero days"        0d                 "$NOW_TUE"
check_err "non-numeric d"    xd                 "$NOW_TUE"
check_err "overflow day count" 99999999999999999d "$NOW_TUE"
check_err "missing token"

exit $fail
