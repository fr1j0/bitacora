#!/usr/bin/env bash
# handoff-pending.sh — pure decision function for the statusLine indicator.
#
# Decides whether the "✎ handoff pending" segment should render for the current
# ticket-branch session. Pure (no I/O); the script that sources this gathers
# the inputs from git/filesystem.
#
# Usage:
#   . handoff-pending.sh
#   if handoff_pending "$is_ticket" "$tree_dirty" "$last_commit_ts" "$marker_ts" "$now_ts"; then
#     echo "show it"
#   fi
#
# Inputs (all strings; integer ones must be epoch seconds, default "0"):
#   is_ticket       — "true" if current branch matches project_key_pattern
#   tree_dirty      — "true" if `git status --porcelain` is non-empty
#   last_commit_ts  — epoch seconds of HEAD commit (0 if no commits)
#   marker_ts       — epoch seconds from .bitacora/last-handoff (0 if absent)
#   now_ts          — current epoch seconds (defaults to marker_ts when omitted,
#                     which conservatively suppresses the dirty clause)
#
# Truth: is_ticket AND (
#          last_commit_ts > marker_ts                         # un-handed-off commits
#          OR (tree_dirty AND now_ts - marker_ts > grace)     # dirt the last handoff didn't capture
#        )
#
# Why the grace window: a handoff writes a [CTX] comment but does NOT commit the
# working tree, so the tree stays dirty right after every handoff. A bare
# "dirty ⇒ pending" rule (the pre-#101 behavior) therefore fired forever after a
# handoff — a guaranteed false positive. A dirty tree has no timestamp of its own,
# so we can't tell dirt captured *by* the last handoff from dirt introduced *after*
# it. The grace window resolves the ambiguity: a dirty tree only counts as pending
# once the last handoff is older than `grace` seconds — recent dirt is treated as
# the work that handoff just captured. Grace defaults to 300s; override with
# BITACORA_HANDOFF_GRACE.
#
# Returns 0 (true) when the indicator should render, 1 (false) otherwise.

handoff_pending() {
  local is_ticket="$1" tree_dirty="$2" last_commit_ts="$3" marker_ts="$4" now_ts="${5:-$4}"
  local grace="${BITACORA_HANDOFF_GRACE:-300}"
  [ "$is_ticket" = "true" ] || return 1
  [ "$last_commit_ts" -gt "$marker_ts" ] && return 0
  if [ "$tree_dirty" = "true" ] && [ "$(( now_ts - marker_ts ))" -gt "$grace" ]; then
    return 0
  fi
  return 1
}
