#!/usr/bin/env bash
# Tests statusline.sh — pure function + full-render fixtures.
# (Full-render section is added in Task 4.)
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE_DIR="$DIR/../statusline"
STATUSLINE="$STATUSLINE_DIR/statusline.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# --- Part 1: handoff_pending pure function ------------------------------------
. "$STATUSLINE_DIR/handoff-pending.sh"

# handoff_pending(is_ticket, tree_dirty, last_commit_ts, marker_ts) -> 0/1
if   handoff_pending true  true  100 0   ; then pass "pure: ticket + dirty tree → on"     ; else bad "pure: ticket+dirty"      ; fi
if   handoff_pending true  false 200 100 ; then pass "pure: ticket + commit > marker → on"; else bad "pure: commit>marker"     ; fi
if ! handoff_pending true  false 100 200 ; then pass "pure: ticket + clean + marker > commit → off"; else bad "pure: marker>commit"; fi
if ! handoff_pending false true  100 0   ; then pass "pure: non-ticket branch → off"      ; else bad "pure: non-ticket"        ; fi
if   handoff_pending true  true  0   0   ; then pass "pure: no marker, work present → on" ; else bad "pure: no marker"         ; fi
if ! handoff_pending true  false 100 100 ; then pass "pure: commit == marker → off"       ; else bad "pure: commit==marker"    ; fi

if [ "$fail" -eq 0 ]; then echo "All statusline tests passed."; else echo "Some tests FAILED."; fi
exit "$fail"
