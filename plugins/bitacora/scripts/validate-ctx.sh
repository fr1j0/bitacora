#!/usr/bin/env bash
# validate-ctx.sh — classify a Jira comment against the [CTX] format spec.
#
# Usage:  validate-ctx.sh [FILE]    (reads stdin if FILE is omitted)
# Output: one of  compliant | malformed | not-in-format   (stdout)
# Exit:   0 compliant | 1 malformed | 2 not-in-format
#
# Rule (v1):
#   - Trimmed text MUST START WITH "[CTX]" (startswith, NOT substring) else not-in-format.
#   - compliant requires a "Status:" line AND a "Next:" line.
#   - Starts with "[CTX]" but missing Status/Next → malformed.
# NOTE: no date in the header — the comment's own created timestamp is authoritative.
# NOTE: "Status:"/"Next:" are matched at column 0 — leading spaces disqualify a line.
# NOTE: input is used as-is otherwise; CRLF (\r) line endings are accepted (treated as content).
set -euo pipefail

if [[ $# -ge 1 && ! -f "$1" ]]; then
  echo "validate-ctx: cannot read file: $1" >&2
  exit 3
fi

input="$(cat "${1:-/dev/stdin}")"

# Strip leading whitespace (including newlines) for the startswith check.
trimmed="${input#"${input%%[![:space:]]*}"}"

# Quoted "[CTX]" makes the brackets literal in the case glob.
case "$trimmed" in
  '[CTX]'*) : ;;                       # starts with [CTX] — continue checks
  *) echo "not-in-format"; exit 2 ;;
esac

has_status=false
has_next=false
while IFS= read -r line; do
  case "$line" in
    "Status:"*) has_status=true ;;
    "Next:"*)   has_next=true ;;
  esac
done <<< "$input"

if $has_status && $has_next; then
  echo "compliant"; exit 0
else
  echo "malformed"; exit 1
fi
