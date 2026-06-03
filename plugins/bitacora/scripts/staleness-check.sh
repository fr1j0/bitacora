#!/usr/bin/env bash
# staleness-check.sh — decide whether a ticket's latest [CTX] is "behind" the
# ticket's own activity (Bitácora staleness signal). Pure arithmetic on UTC epoch
# seconds; no Jira calls — the caller (session-resume / session-status) extracts the
# timestamps and passes them in.
#
# Usage:
#   staleness-check.sh --ctx-epoch <N> --updated-epoch <N> [--grace <token>]
#
#   --ctx-epoch     creation time (epoch s) of the ticket's latest compliant [CTX].
#   --updated-epoch the ticket's `updated` time (epoch s) from the Jira API.
#   --grace         drift tolerance as <N>h | <N>d (default 2d).
#
# Output : "fresh", or "stale <D>d" where D = floor((updated - ctx) / 86400). exit 0.
# Errors : missing/invalid args -> one-line reason on stderr, exit 2.
#
# Stale iff: updated > ctx AND (updated - ctx) > grace. Magnitude D is whole days of
# drift. updated <= ctx (the [CTX] is the latest activity, or clock skew) -> fresh.
set -uo pipefail

ctx="" updated="" grace="2d"

while (( $# )); do
  case "$1" in
    --ctx-epoch)     ctx="${2:-}"; shift 2 ;;
    --updated-epoch) updated="${2:-}"; shift 2 ;;
    --grace)         grace="${2:-}"; shift 2 ;;
    *) echo "staleness-check: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ "$ctx" =~ ^[0-9]+$ ]]     || { echo "staleness-check: --ctx-epoch must be epoch seconds" >&2; exit 2; }
[[ "$updated" =~ ^[0-9]+$ ]] || { echo "staleness-check: --updated-epoch must be epoch seconds" >&2; exit 2; }

# Resolve the grace token (<N>h | <N>d) to seconds.
case "$grace" in
  *h) unit=3600;  n="${grace%h}" ;;
  *d) unit=86400; n="${grace%d}" ;;
  *)  echo "staleness-check: bad --grace '$grace' (expected <N>h or <N>d)" >&2; exit 2 ;;
esac
if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )); then
  grace_sec=$(( n * unit ))
else
  echo "staleness-check: bad --grace '$grace' (expected <N>h or <N>d)" >&2; exit 2
fi

if (( updated <= ctx )); then echo fresh; exit 0; fi
drift=$(( updated - ctx ))
if (( drift > grace_sec )); then
  echo "stale $(( drift / 86400 ))d"
else
  echo fresh
fi
exit 0
