#!/usr/bin/env bash
# validate-ctx.sh — classify a Jira comment against the [CTX] format spec.
#
# Usage:  validate-ctx.sh [FILE]    (reads stdin if FILE is omitted)
# Output: one of  compliant | malformed | not-in-format   (stdout)
# Exit:   0 compliant | 1 malformed | 2 not-in-format
#
# Rules:
#   - Trimmed text MUST START WITH "[CTX]" (startswith, NOT substring) else not-in-format.
#   - compliant requires a "Status:" line AND a "Next:" line.
#   - Starts with "[CTX]" but missing Status/Next → malformed.
#   - Also malformed if the body contains:
#       * a tool-arg sentinel (e.g. "<parameter name=", "</commentBody>") — agent leak;
#       * a bare URL (an https?:// not wrapped as [label](url) or <url>) — Jira won't
#         auto-linkify, so it renders as plain text in the comment.
#     A one-line reason is printed to stderr for these classes.
# NOTE: no date in the header — the comment's own created timestamp is authoritative.
# NOTE: "Status:"/"Next:" are matched at column 0 — leading spaces disqualify a line.
# NOTE: input is used as-is otherwise; CRLF (\r) line endings are accepted (treated as content).
set -uo pipefail   # no -e: we exit with specific codes deliberately

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

if ! $has_status || ! $has_next; then
  echo "malformed"
  echo "validate-ctx: missing required Status: and/or Next: line." >&2
  exit 1
fi

# Tool-arg sentinel leak: the agent serialized part of its own MCP tool call
# into the body. No legitimate [CTX] needs these substrings.
if grep -qE '<parameter name=|</commentBody>|</invoke>|<invoke name=' <<< "$input"; then
  echo "malformed"
  echo "validate-ctx: tool-arg sentinel detected (e.g. <parameter name=, </commentBody>) — agent leak." >&2
  exit 1
fi

# Bare URL: an https?://… not wrapped in [label](url) or <url>.
# Strip the wrapped forms first, then look for any residual https?:// in the body.
stripped="$(sed -E -e 's/\[[^][]*\]\([^()]*\)//g' -e 's/<https?:\/\/[^>[:space:]]+>//g' <<< "$input")"
if grep -qE 'https?://' <<< "$stripped"; then
  echo "malformed"
  echo "validate-ctx: bare URL detected — wrap as [label](url) or <url> so Jira renders it as a link." >&2
  exit 1
fi

echo "compliant"
exit 0
