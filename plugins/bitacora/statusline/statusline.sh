#!/usr/bin/env bash
# statusline.sh — Bitácora's Claude Code statusLine renderer.
#
# Reads JSON from stdin (Claude Code session info), prints one line:
#   <branch-or-ticket>  ·  ctx <bar> <pct>%  ·  ✎ handoff pending
#
# Each segment is omitted independently when its data is unavailable or its
# config toggle is false. At pct >= THRESHOLD (default 85) the meter — and
# the handoff segment when present — render in bold + red (or "⚠ " prefix
# when $NO_COLOR is set). Every git call is wrapped in `timeout 1` when GNU coreutils' `timeout` (or
# Homebrew's `gtimeout`) is available, so the statusLine cannot hang; on stock
# macOS the wrapper is a no-op and the git call runs unbounded (the worst case
# is bounded by how fast local git can read .git/). Always exits 0; never
# errors visibly.
#
# Configuration is env-var-driven for v1 (the user sources their .bitacora.yml
# externally if they wish; YAML parsing in pure bash is out of scope):
#   BITACORA_SHOW_BRANCH   (default: true)
#   BITACORA_SHOW_METER    (default: true)
#   BITACORA_SHOW_HANDOFF  (default: true)
#   BITACORA_THRESHOLD     (default: 85)

set -o pipefail  # do NOT set -u: "${arr[@]}" on an empty array errors in bash 3.x+

# Note: this resolves a symlink's *location*, not its target. The opt-in sync
# (see plan) copies both .sh files side-by-side, so `handoff-pending.sh` is
# always alongside this script — DIY symlinks won't find it.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/handoff-pending.sh"

SHOW_BRANCH="${BITACORA_SHOW_BRANCH:-true}"
SHOW_METER="${BITACORA_SHOW_METER:-true}"
SHOW_HANDOFF="${BITACORA_SHOW_HANDOFF:-true}"
THRESHOLD="${BITACORA_THRESHOLD:-85}"
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || THRESHOLD=85   # tolerate garbage env-var
KEY_PATTERN='[A-Z][A-Z0-9]+-[0-9]+'

# Resolve a timeout wrapper for git calls once. GNU coreutils ships `timeout`;
# Homebrew coreutils ships it as `gtimeout` on macOS; stock macOS has neither —
# fall back to no-wrapper so the statusLine still renders (no hang protection,
# but a fast-local git call against the resolved cwd is the worst case).
if   command -v timeout  >/dev/null 2>&1; then _TIMEOUT="timeout 1"
elif command -v gtimeout >/dev/null 2>&1; then _TIMEOUT="gtimeout 1"
else                                           _TIMEOUT=""
fi

# --- read stdin & cwd ---------------------------------------------------------
input="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

pct_raw="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)"

# --- helpers ------------------------------------------------------------------

# Round-nearest 0..100 to a 0..8 bar; render with █ filled, ░ empty.
render_bar() {
  local pct="$1" filled empty bar i
  filled=$(( (pct * 8 + 50) / 100 ))
  [ "$filled" -gt 8 ] && filled=8
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( 8 - filled ))
  bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty;  i++)); do bar+="░"; done
  printf '%s' "$bar"
}

# Wrap text in red+bold ANSI; with $NO_COLOR set, prefix with "⚠ " instead.
escalate() {
  local body="$1"
  if [ -n "${NO_COLOR:-}" ]; then
    printf '⚠ %s' "$body"
  else
    printf '\033[1;31m%s\033[0m' "$body"
  fi
}

# Time-boxed git for the resolved cwd.
git_in() { ${_TIMEOUT} git -C "$cwd" "$@" 2>/dev/null; }

# --- detect branch / ticket ---------------------------------------------------
branch="$(git_in symbolic-ref --short HEAD || true)"
is_ticket=false
ticket=""
if [ -n "$branch" ] && [[ "$branch" =~ $KEY_PATTERN ]]; then
  is_ticket=true
  ticket="${BASH_REMATCH[0]}"
fi

# --- build segments -----------------------------------------------------------
segments=()

if [ "$SHOW_BRANCH" = "true" ] && [ -n "$branch" ]; then
  if [ "$is_ticket" = "true" ]; then segments+=("$ticket"); else segments+=("$branch"); fi
fi

# Compute pct unconditionally — the handoff segment's escalation also reads it,
# so disabling the meter must not silently disable the handoff red.
pct=""
if [ -n "$pct_raw" ] && [[ "$pct_raw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  pct="${pct_raw%.*}"
fi

if [ "$SHOW_METER" = "true" ]; then
  if [ -n "$pct" ]; then
    meter_body="ctx $(render_bar "$pct") ${pct}%"
    if [ "$pct" -ge "$THRESHOLD" ]; then segments+=("$(escalate "$meter_body")"); else segments+=("$meter_body"); fi
  else
    segments+=("ctx ?")
  fi
fi

if [ "$SHOW_HANDOFF" = "true" ]; then
  tree_dirty=false
  [ -n "$(git_in status --porcelain)" ] && tree_dirty=true
  last_commit_ts="$(git_in log -1 --format=%ct)"
  [ -z "$last_commit_ts" ] && last_commit_ts=0
  marker_ts=0
  marker_path="$cwd/.bitacora/last-handoff"
  if [ -r "$marker_path" ]; then
    marker_ts="$(tr -dc '0-9' < "$marker_path" 2>/dev/null)"
    [ -z "$marker_ts" ] && marker_ts=0
  fi
  if handoff_pending "$is_ticket" "$tree_dirty" "$last_commit_ts" "$marker_ts"; then
    handoff_body="✎ handoff pending"
    if [ -n "$pct" ] && [ "$pct" -ge "$THRESHOLD" ]; then segments+=("$(escalate "$handoff_body")"); else segments+=("$handoff_body"); fi
  fi
fi

# --- print --------------------------------------------------------------------
if [ "${#segments[@]}" -eq 0 ]; then exit 0; fi
out="${segments[0]}"
for ((i=1; i<${#segments[@]}; i++)); do out+="  ·  ${segments[$i]}"; done
printf '%s\n' "$out"
exit 0
