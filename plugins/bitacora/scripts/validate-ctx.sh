#!/usr/bin/env bash
# validate-ctx.sh — classify a tracker comment against the [CTX] format spec.
# Tracker-agnostic: the same rules apply to Jira, GitHub, and GitLab comments.
#
# Usage:  validate-ctx.sh [FILE]    (reads stdin if FILE is omitted)
# Output: one of  compliant | malformed | not-in-format   (stdout)
# Exit:   0 compliant | 1 malformed | 2 not-in-format
#
# Rules:
#   - The first non-preamble line MUST START WITH "[CTX]", else not-in-format.
#     "Preamble" = zero or more leading lines that are blank or whose trimmed content
#     begins with `_`, `*`, or `(` (italic-markdown or parenthesized notes).
#     Established practice: a short housekeeping note above the [CTX] header.
#   - compliant requires a "Status:" line AND a "Next:" line.
#   - Starts with "[CTX]" but missing Status/Next → malformed.
#   - Also malformed if the body (including any preamble) contains:
#       * a tool-arg sentinel (e.g. "<parameter name=", "</commentBody>") — agent leak;
#       * a bare URL (an https?:// not wrapped as [label](url) or <url>) — wrap it on
#         every tracker (Jira won't auto-linkify; the others render fine but the wrapped
#         form keeps the [CTX] portable and consistent across backends).
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

# Skip leading preamble (blank lines + lines starting with _, *, or () before the
# [CTX] check. The first non-preamble line MUST start with "[CTX]".
first_real=""
while IFS= read -r line; do
  line="${line%$'\r'}"
  trimmed_line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$trimmed_line" ]] && continue
  case "$trimmed_line" in
    '_'*|'*'*|'('*) continue ;;
    *) first_real="$trimmed_line"; break ;;
  esac
done <<< "$input"

case "$first_real" in
  '[CTX]'*) : ;;                       # first real line starts with [CTX] — continue
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
  echo "validate-ctx: bare URL detected — wrap as [label](url) or <url> so it renders as a link on every tracker." >&2
  exit 1
fi

echo "compliant"
exit 0
