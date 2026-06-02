#!/usr/bin/env bash
# since-window.sh — resolve a --standup --since token to a UTC cutoff epoch.
#
# Usage:  since-window.sh <token> [now_epoch]
#   token     : <N>d  (N>=1, e.g. 1d 2d 7d)  |  last-working-day
#   now_epoch : optional reference "now" in epoch seconds (default: current time).
#               Tests inject it for determinism.
# Output : prints the cutoff epoch (seconds) to stdout. A [CTX] comment whose
#          `created` epoch is >= the cutoff is "in the window". Exit 0.
# Errors : unknown/malformed token -> one-line reason on stderr, exit 2.
#
# All math is pure integer arithmetic in UTC, so there is no GNU/BSD `date`
# divergence. 1970-01-01 was a Thursday (ISO weekday 4); for a day index
# d = epoch / 86400, iso_weekday = ((d + 3) % 7) + 1  (Mon=1 .. Sun=7).
# "last-working-day" walks back from yesterday to the most recent Mon–Fri and
# returns that day's UTC midnight (so a Monday standup picks up Friday + weekend).
set -uo pipefail

token="${1:-}"
now="${2:-$(date +%s)}"
day=86400

if [[ -z "$token" ]]; then
  echo "since-window: missing token (expected <N>d or last-working-day)" >&2
  exit 2
fi

case "$token" in
  last-working-day)
    today_mid=$(( (now / day) * day ))
    off=1
    while :; do
      d=$(( today_mid / day - off ))
      wd=$(( ( (d + 3) % 7 ) + 1 ))   # 1=Mon .. 7=Sun
      if (( wd <= 5 )); then break; fi
      off=$(( off + 1 ))
    done
    echo $(( today_mid - off * day ))
    ;;
  *d)
    n="${token%d}"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= 36500 )); then
      echo $(( now - n * day ))
    else
      echo "since-window: bad day count in '$token' (expected <N>d, 1<=N<=36500)" >&2
      exit 2
    fi
    ;;
  *)
    echo "since-window: unknown token '$token' (expected <N>d or last-working-day)" >&2
    exit 2
    ;;
esac
