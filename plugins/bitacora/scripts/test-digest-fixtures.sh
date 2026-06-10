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
#   debt: DATA-77 carries a [debt] decision with follow-up DATA-81 (multi scenario);
#         CHECKOUT-101 carries one with follow-up CHECKOUT-104 (epic scenario)
#   recurrence: "peak traffic" recurs across CHECKOUT-101 + CHECKOUT-102 (epic scenario)
#   negative: multi-aggregate-nodebt.txt is a 2-ticket no-debt scope (section omitted)
#   coverage:  "4 tickets (3 reporting, 1 no [CTX])"
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
EX="$DIR/../skills/session-digest/examples"
SW="$DIR/since-window.sh"
AGG="$EX/multi-aggregate.txt"
BLK="$EX/multi-blocked.txt"
STD="$EX/multi-standup.txt"
EPE="$EX/epic-exec.txt"
EPG="$EX/epic-eng.txt"
SLK="$EX/multi-aggregate-slack.txt"
NDB="$EX/multi-aggregate-nodebt.txt"
COVERAGE="4 tickets (3 reporting, 1 no [CTX])"
ALLOWED="AUTH-12 DATA-77 UI-30 PERF-9 PLATFORM-4 DATA-81"

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
for f in "$AGG" "$BLK" "$STD" "$NDB"; do
  [ -f "$f" ] || bad "fixture missing: $f"
done

# 1. cross-fixture coverage consistency — same scenario described identically
for f in "$AGG" "$BLK" "$STD"; do
  check_has "$f" "$COVERAGE" "coverage line consistent in $(basename "$f")"
done

# 2. terminology guard — multi-ticket default is the cross-ticket digest, not a "portfolio"
for f in "$AGG" "$BLK" "$STD" "$NDB"; do
  check_hasnot "$f" "portfolio" "no 'portfolio' in $(basename "$f")"
done
check_has    "$AGG" "By ticket:" "aggregate uses 'By ticket:'"
check_hasnot "$AGG" "By child:"  "aggregate avoids 'By child:'"

# 3. ticket-key universe — every ABC-123 key must be in the allowed set
keyfail=0
for f in "$AGG" "$BLK" "$STD" "$NDB"; do
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

# 6. --standup lens — since 1d window, two-bucket day render.
#    AUTH-12 + DATA-77 moved yesterday; DATA-77 also moved today (appears in BOTH
#    buckets); UI-30 has a [CTX] but none in-window; PERF-9 has no [CTX] at all.
check_has    "$STD" "Standup — since 1d"   "standup header carries the window token"
check_has    "$STD" "Yesterday:"           "standup renders the past (Yesterday) bucket"
check_has    "$STD" "Today:"               "standup renders the Today bucket"
check_has    "$STD" "AUTH-12"              "standup lists AUTH-12 (moved yesterday)"
check_has    "$STD" "No movement: UI-30"   "standup No-movement lists the in-window non-mover"
check_hasnot "$STD" "PERF-9"               "standup omits the no-[CTX] ticket from movement lines"
check_hasnot "$STD" "Moved:"               "standup uses day buckets, not a flat Moved: block"
# DATA-77 spans both buckets → it must appear at least twice.
if (( $(grep -c "DATA-77" "$STD") >= 2 )); then
  pass "standup shows DATA-77 in both buckets (>=2 occurrences)"
else
  bad "standup should show DATA-77 in both Yesterday and Today (>=2 occurrences)"
fi

# 7. since-window smoke — --standup rides this helper
if "$SW" 1d 1704801600 >/dev/null 2>&1 && "$SW" last-working-day 1704801600 >/dev/null 2>&1; then
  pass "since-window.sh resolves 1d and last-working-day"
else
  bad "since-window.sh smoke failed"
fi

# 8. printed renders are BARE — links live only in the --copy-as-slack output (D1)
for f in "$AGG" "$BLK" "$STD" "$EPE" "$EPG"; do
  check_hasnot "$f" "](http" "printed render keeps bare keys ($(basename "$f"))"
done

# 9. --copy-as-slack output Slack-links the index keys as <…/browse/KEY|KEY> (D2); inline/tail bare (D3)
check_slack() {  # file, key, label
  if grep -Fq -- "/browse/$2|$2>" "$1"; then pass "$3"
  else bad "$3 (key $2 not Slack-linked in $(basename "$1"))"; fi
}
check_slack "$SLK" "AUTH-12" "slack digest Slack-links AUTH-12"
check_slack "$SLK" "DATA-77" "slack digest Slack-links DATA-77"
check_slack "$SLK" "UI-30"   "slack digest Slack-links UI-30"
check_hasnot "$SLK" "/browse/PERF-9|" "slack digest leaves Not-yet-reporting PERF-9 bare"

# 10. parked-debt ledger (D1/D5) — aggregate-only pivot on existing [debt] tags
check_has    "$AGG" "Parked debt:"      "aggregate (self) renders the Parked debt tail"
check_has    "$AGG" "follow-up DATA-81" "debt line carries the named follow-up"
check_has    "$SLK" "Parked debt:"      "slack render keeps the Parked debt section"
check_hasnot "$SLK" "/browse/DATA-81|"  "slack leaves debt-ledger keys bare (inline, not index)"
check_has    "$EPE" "Debt:"             "epic exec renders the Debt line"
check_has    "$EPG" "Parked debt:"      "epic eng renders the Parked debt line"
check_has    "$EPG" "CHECKOUT-104"      "epic eng debt line names the follow-up"
check_hasnot "$NDB" "Debt:"             "no-debt scenario omits the debt section entirely"
check_hasnot "$NDB" "Parked debt:"      "no-debt scenario omits the Parked debt section too"
check_hasnot "$BLK" "Parked debt:"      "--blocked does not grow a debt section"
check_hasnot "$STD" "Parked debt:"      "--standup does not grow a debt section"

# 11. risk-concentration recurrence flag (D3) — surface named once, tickets listed
check_has "$EPE" "Concentrated: peak traffic recurs across CHECKOUT-101 + CHECKOUT-102" "exec flags the concentrated surface"
check_has "$EPG" "Concentrated: peak traffic recurs across CHECKOUT-101 + CHECKOUT-102" "eng flags the concentrated surface"

exit $fail
