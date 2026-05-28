#!/usr/bin/env bash
# handoff-pending.sh — pure decision function for the statusLine indicator.
#
# Decides whether the "✎ handoff pending" segment should render for the current
# ticket-branch session. Pure (no I/O); the script that sources this gathers
# the four inputs from git/filesystem.
#
# Usage:
#   . handoff-pending.sh
#   if handoff_pending "$is_ticket" "$tree_dirty" "$last_commit_ts" "$marker_ts"; then
#     echo "show it"
#   fi
#
# Inputs (all strings; integer ones must be epoch seconds, default "0"):
#   is_ticket       — "true" if current branch matches project_key_pattern
#   tree_dirty      — "true" if `git status --porcelain` is non-empty
#   last_commit_ts  — epoch seconds of HEAD commit (0 if no commits)
#   marker_ts       — epoch seconds from .bitacora/last-handoff (0 if absent)
#
# Returns 0 (true) when the indicator should render, 1 (false) otherwise.
# Truth: is_ticket AND (tree_dirty OR last_commit_ts > marker_ts)

handoff_pending() {
  local is_ticket="$1" tree_dirty="$2" last_commit_ts="$3" marker_ts="$4"
  [ "$is_ticket" = "true" ] || return 1
  [ "$tree_dirty" = "true" ] && return 0
  [ "$last_commit_ts" -gt "$marker_ts" ] && return 0
  return 1
}
