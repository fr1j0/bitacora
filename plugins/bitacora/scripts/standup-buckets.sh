#!/usr/bin/env bash
# standup-buckets.sh — map a UTC epoch to its day index and full weekday name.
#
# Usage:  standup-buckets.sh <epoch>
#   epoch : a timestamp in epoch seconds (non-negative integer).
# Output : prints "<day_index> <Weekday>" to stdout, e.g. "19727 Friday".
#          day_index = epoch / 86400 (UTC midnight buckets); Weekday is the full
#          English name (Monday .. Sunday). Exit 0.
# Errors : missing / non-numeric / negative epoch -> one-line reason on stderr, exit 2.
#
# Pure integer arithmetic in UTC, so there is no GNU/BSD `date` divergence. 1970-01-01
# was a Thursday (ISO weekday 4); for day index d, iso_weekday = ((d + 3) % 7) + 1
# (Mon=1 .. Sun=7).
#
# The --standup render (session-status SKILL.md §7) calls this once for "now" to learn
# today's day index, then once per in-window [CTX] `created` epoch; it buckets a [CTX]
# into Today (day index == today's) or the past bucket (day index < today's), and labels
# the past bucket Yesterday / <weekday> / Earlier from the distinct day indices it holds.
set -uo pipefail

epoch="${1:-}"
day=86400

if [[ -z "$epoch" ]]; then
  echo "standup-buckets: missing epoch (expected non-negative integer seconds)" >&2
  exit 2
fi
if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
  echo "standup-buckets: bad epoch '$epoch' (expected non-negative integer seconds)" >&2
  exit 2
fi

idx=$(( epoch / day ))
wd=$(( ( (idx + 3) % 7 ) + 1 ))   # 1=Mon .. 7=Sun
names=(_ Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
echo "$idx ${names[$wd]}"
