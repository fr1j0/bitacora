#!/usr/bin/env bash
# precompact-handoff-check.sh — UserPromptSubmit hook for Bitácora's handoff
# guardrail.
#
# Filename keeps the original "PreCompact" friction title for searchability;
# the actual Claude Code event is UserPromptSubmit because /clear is a user-
# submitted prompt, not a compaction. See
#   docs/superpowers/specs/2026-05-29-handoff-guardrail-hook-design.md
# for the design rationale.
#
# Reads JSON from stdin, decides whether to block, emits JSON on stdout when
# blocking. Exits 0 in every branch (a non-zero hook would surface as a
# Claude Code error to the user). Fail-open everywhere: any infrastructure
# trouble proceeds with /clear.

set -uo pipefail   # no -e: errors are handled explicitly via guard chains

DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_HANDOFF_PENDING="$DIR/../statusline/handoff-pending.sh"

# 1. Read stdin (Claude Code's JSON input). Drop silently on read failure.
input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0

# 2. Need jq to parse the prompt; fail-open if unavailable.
command -v jq >/dev/null 2>&1 || exit 0

# 3. Extract the prompt body.
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"
[ -z "$prompt" ] && exit 0

# 4. Trim leading whitespace; check the /clear or /compact prefix.
trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
case "$trimmed" in
  '/clear'|'/clear '*|'/compact'|'/compact '*) ;;
  *) exit 0 ;;
esac

# 5. Repo detection (fail-open if not in a git repo).
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0

# 6. Marker file consumes one /clear and exits silently.
marker="$repo_root/.bitacora/skip-handoff-once"
if [ -e "$marker" ]; then
  rm -f -- "$marker" 2>/dev/null || true
  exit 0
fi

# 7. Branch must match a project key pattern (default: PROJ-1234 style).
project_key_pattern='[A-Z][A-Z0-9]+-[0-9]+'
branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
ticket_key="$(printf '%s' "$branch" | grep -oE "$project_key_pattern" | head -n 1)"
[ -z "$ticket_key" ] && exit 0

# 8. Source the handoff-pending decision function.
[ -r "$SOURCE_HANDOFF_PENDING" ] || exit 0
# shellcheck source=../statusline/handoff-pending.sh
. "$SOURCE_HANDOFF_PENDING"

# 9. Gather signals.
is_ticket="true"
tree_dirty="false"
if [ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null || true)" ]; then
  tree_dirty="true"
fi
last_commit_ts="$(git -C "$repo_root" log -1 --format=%ct 2>/dev/null || echo 0)"
[ -z "$last_commit_ts" ] && last_commit_ts=0
marker_ts=0
handoff_marker="$repo_root/.bitacora/last-handoff"
if [ -r "$handoff_marker" ]; then
  marker_ts="$(cat "$handoff_marker" 2>/dev/null || echo 0)"
  marker_ts="${marker_ts//[^0-9]/}"
  [ -z "$marker_ts" ] && marker_ts=0
fi

# 10. Decide. False ⇒ nothing to do.
if ! handoff_pending "$is_ticket" "$tree_dirty" "$last_commit_ts" "$marker_ts"; then
  exit 0
fi

# 11. Count commits since the marker (best-effort; 0 if anything goes sideways).
pending_commits=0
if [ "$last_commit_ts" -gt "$marker_ts" ]; then
  # --max-age (raw epoch) avoids `--since="@$marker_ts"` — git's approxidate
  # parser flakes intermittently on @<epoch>, returning an empty result for
  # repos that clearly contain matching commits.
  pending_commits="$(git -C "$repo_root" rev-list --count --max-age="$marker_ts" HEAD 2>/dev/null)"
  [ -z "$pending_commits" ] && pending_commits=0
fi

# 12. Render the block message.
msg="Bitácora: handoff pending on ${ticket_key}."
if [ "$last_commit_ts" -gt "$marker_ts" ] && [ "$pending_commits" -gt 0 ]; then
  msg="${msg}"$'\n'"  · ${pending_commits} commit(s) since the last handoff marker"
fi
if [ "$tree_dirty" = "true" ]; then
  msg="${msg}"$'\n'"  · uncommitted changes in the working tree"
fi
msg="${msg}"$'\n\n'"To preserve this session in Jira:"$'\n'"    /bitacora:handoff"$'\n\n'"To bypass this check for one /clear:"$'\n'"    touch .bitacora/skip-handoff-once"$'\n'"    /clear"

ctx="Bitácora blocked /clear: handoff pending on ${ticket_key}. The user should run /bitacora:handoff or touch .bitacora/skip-handoff-once before retrying."

# 13. Emit the block JSON (compact, single-line).
jq -c -n --arg msg "$msg" --arg ctx "$ctx" \
  '{decision:"block",stopReason:$msg,hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'

exit 0
