#!/usr/bin/env bash
# Fixture-contract lint for the multi-ticket /status renders.
#
# Asserts the committed examples/multi-*.txt obey the rules SKILL.md §7 declares,
# over the shared 4-ticket scenario. Deterministic — NO LLM, NO Jira. It guards
# fixture/spec drift and the portfolio->digest terminology decision. It does NOT
# test live rendering, audience-altitude behavior (exec hash-stripping, pm
# plain-language), real JQL, or the audience x query combos beyond the three
# `self` fixtures — that is the M1–M8 render half in
# docs/superpowers/checklists/MANUAL-ACCEPTANCE.md.
#
# Brittle by design: a fixture reformat forces a deliberate update here.
#
# Scenario constants (change here if the fixtures' scenario changes):
#   reporting: AUTH-12, DATA-77, UI-30   no-[CTX]: PERF-9   external dep: PLATFORM-4
#   coverage:  "4 tickets (3 reporting, 1 no [CTX])"
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
EX="$DIR/../skills/session-status/examples"
SW="$DIR/since-window.sh"
AGG="$EX/multi-aggregate.txt"
BLK="$EX/multi-blocked.txt"
STD="$EX/multi-standup.txt"
COVERAGE="4 tickets (3 reporting, 1 no [CTX])"
ALLOWED="AUTH-12 DATA-77 UI-30 PERF-9 PLATFORM-4"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

check_has() {    # file, substring, label
  if grep -Fq -- "$2" "$1"; then pass "$3"
  else bad "$3 (missing '$2' in $(basename "$1"))"; fi
}
check_hasnot() { # file, substring, label
  if grep -Fq -- "$2" "$1"; then bad "$3 (unexpected '$2' in $(basename "$1"))"
  else pass "$3"; fi
}

# 0. fixtures exist
for f in "$AGG" "$BLK" "$STD"; do
  [ -f "$f" ] || bad "fixture missing: $f"
done

# 1. cross-fixture coverage consistency — same scenario described identically
for f in "$AGG" "$BLK" "$STD"; do
  check_has "$f" "$COVERAGE" "coverage line consistent in $(basename "$f")"
done

# 2. terminology guard — multi-ticket default is the cross-ticket digest, not a "portfolio"
for f in "$AGG" "$BLK" "$STD"; do
  check_hasnot "$f" "portfolio" "no 'portfolio' in $(basename "$f")"
done
check_has    "$AGG" "By ticket:" "aggregate uses 'By ticket:'"
check_hasnot "$AGG" "By child:"  "aggregate avoids 'By child:'"

# 3. ticket-key universe — every ABC-123 key must be in the allowed set
keyfail=0
for f in "$AGG" "$BLK" "$STD"; do
  while read -r key; do
    [ -n "$key" ] || continue
    case " $ALLOWED " in
      *" $key "*) : ;;
      *) bad "unexpected ticket key '$key' in $(basename "$f")"; keyfail=1 ;;
    esac
  done < <(grep -oE '[A-Z][A-Z0-9]+-[0-9]+' "$f" | sort -u)
done
[ "$keyfail" -eq 0 ] && pass "ticket-key universe within {$ALLOWED}"

# 4. aggregate lens
check_has "$AGG" "Health:" "aggregate has a Health line"
check_has "$AGG" "Not yet reporting: PERF-9" "aggregate surfaces the no-[CTX] ticket (never dropped)"

# 5. --blocked lens — only the blocked ticket appears, with staleness + clear-count
check_has    "$BLK" "Blocked —"      "blocked header present"
check_has    "$BLK" "AUTH-12"        "blocked lists AUTH-12 (the blocked ticket)"
check_hasnot "$BLK" "DATA-77"        "blocked omits non-blocked DATA-77"
check_hasnot "$BLK" "UI-30"          "blocked omits non-blocked UI-30"
check_has    "$BLK" "stale 2d"       "blocked shows staleness (stale 2d)"
check_has    "$BLK" "Clear: 2 of 3"  "blocked clear-count math (2 of 3)"

# 6. --standup lens — since 1d window; only DATA-77 moved; no-[CTX] ticket absent
check_has    "$STD" "Standup — since 1d"            "standup header carries the window token"
check_has    "$STD" "DATA-77"                       "standup Moved lists DATA-77"
check_has    "$STD" "No movement: AUTH-12, UI-30"   "standup No-movement lists the non-movers"
check_hasnot "$STD" "PERF-9"                        "standup omits the no-[CTX] ticket from movement lines"

# 7. since-window smoke — --standup rides this helper
if "$SW" 1d 1704801600 >/dev/null 2>&1 && "$SW" last-working-day 1704801600 >/dev/null 2>&1; then
  pass "since-window.sh resolves 1d and last-working-day"
else
  bad "since-window.sh smoke failed"
fi

exit $fail
