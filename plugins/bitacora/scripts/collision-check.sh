#!/usr/bin/env bash
# collision-check.sh — decide whether a teammate's [CTX] would be buried by a
# /handoff write (Bitácora collision detection). Pure arithmetic on UTC epoch
# seconds; no Jira calls — the caller (session-handoff skill) extracts the author
# accountIds and timestamps from the ticket's comments and passes them in.
#
# Usage:
#   collision-check.sh [--self] --me <accountId> --latest-author <accountId> \
#       --latest-epoch <N> [--mine-epoch <N>] [--now <N>] [--window <token>]
#
#   --me            accountId of the current Atlassian user (about to write).
#   --latest-author accountId who authored the ticket's most-recent [CTX].
#   --latest-epoch  creation time (epoch seconds) of that most-recent [CTX].
#   --mine-epoch    creation time of the current user's own most-recent [CTX] on
#                   the ticket; OMIT if the user has none (takeover case).
#   --now           reference "now" in epoch seconds (default: current time).
#                   Tests inject it for determinism.
#   --window        collision window as <N>h or <N>d (default 48h).
#
# Output : prints "collision" or "clear" to stdout, exit 0.
# Errors : missing/invalid args -> one-line reason on stderr, exit 2.
#
# Default (teammate) mode — a collision is reported iff ALL hold:
#   1. --latest-author != --me           (the newest context is someone else's)
#   2. --latest-epoch  >  --mine-epoch    (or --mine-epoch omitted: a takeover)
#   3. --latest-epoch  >= now - window    (the context is recent)
#
# --self mode — a self-collision is reported iff BOTH hold (a duplicate re-handoff):
#   1. --latest-author == --me           (the newest context is mine)
#   2. --latest-epoch  >= now - window    (it is recent)
set -uo pipefail

me="" latest_author="" latest_epoch="" mine_epoch="" now="" window="48h" self=false

while (( $# )); do
  case "$1" in
    --me)            me="${2:-}"; shift 2 ;;
    --latest-author) latest_author="${2:-}"; shift 2 ;;
    --latest-epoch)  latest_epoch="${2:-}"; shift 2 ;;
    --mine-epoch)    mine_epoch="${2:-}"; shift 2 ;;
    --now)           now="${2:-}"; shift 2 ;;
    --window)        window="${2:-}"; shift 2 ;;
    --self)          self=true; shift ;;
    *) echo "collision-check: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -z "$me" ]]            && { echo "collision-check: missing --me" >&2; exit 2; }
[[ -z "$latest_author" ]] && { echo "collision-check: missing --latest-author" >&2; exit 2; }
[[ "$latest_epoch" =~ ^[0-9]+$ ]] || { echo "collision-check: --latest-epoch must be epoch seconds" >&2; exit 2; }
if [[ -n "$mine_epoch" && ! "$mine_epoch" =~ ^[0-9]+$ ]]; then
  echo "collision-check: --mine-epoch must be epoch seconds" >&2; exit 2
fi
[[ -z "$now" ]] && now="$(date +%s)"
[[ "$now" =~ ^[0-9]+$ ]] || { echo "collision-check: --now must be epoch seconds" >&2; exit 2; }

# Resolve the window token (<N>h | <N>d) to seconds.
case "$window" in
  *h) unit=3600;  n="${window%h}" ;;
  *d) unit=86400; n="${window%d}" ;;
  *)  echo "collision-check: bad --window '$window' (expected <N>h or <N>d)" >&2; exit 2 ;;
esac
if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )); then
  win=$(( n * unit ))
else
  echo "collision-check: bad --window '$window' (expected <N>h or <N>d)" >&2; exit 2
fi

# --self mode: self-collision — report collision iff the newest [CTX] is MINE and recent.
# (Mirror of the teammate rule; --mine-epoch is irrelevant here — when the newest [CTX] is
# mine, that IS my recent self-handoff.)
if [[ "$self" == "true" ]]; then
  [[ "$latest_author" == "$me" ]] || { echo clear; exit 0; }
  cutoff=$(( now - win ))
  if (( latest_epoch >= cutoff )); then echo collision; else echo clear; fi
  exit 0
fi
# 1. Newest context is mine → no collision.
if [[ "$latest_author" == "$me" ]]; then echo clear; exit 0; fi
# 2. Newest context is not newer than my own last [CTX] → no collision.
if [[ -n "$mine_epoch" ]] && (( latest_epoch <= mine_epoch )); then echo clear; exit 0; fi
# 3. Recent enough?
cutoff=$(( now - win ))
if (( latest_epoch >= cutoff )); then echo collision; else echo clear; fi
exit 0
