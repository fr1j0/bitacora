#!/usr/bin/env bash
# bitacora-tracker.sh — uniform tracker verbs over a CLI backend. Dispatches on
# $TRACKER (github via gh now; gitlab via glab in a follow-up PR). Emits
# normalized JSON so consuming skills read one shape across backends. Jira (MCP)
# never enters this script.
#
# Usage: TRACKER=github bitacora-tracker.sh <verb> [args]
#   doctor                          — verify CLI + jq installed and authed (0 / 5)
#   whoami                          — current login
#   list-mine                       — open issues assigned to caller (JSON array)
#   view <id>                       — one issue (JSON object)
#   comments <id>                   — normalized JSON array [{author,createdAt,body}]
#   comment <id> --body-file <f>    — add a comment
#   edit-body <id> --body-file <f>  — replace the issue body
set -uo pipefail

die()  { echo "bitacora-tracker: $*" >&2; exit 2; }
tracker="${TRACKER:-}"
[[ -n "$tracker" ]] || die "TRACKER env not set (github|gitlab)"
verb="${1:-}"; shift || true

gh_backend() {
  case "$verb" in
    doctor)
      command -v gh >/dev/null || { echo "bitacora-tracker: gh not installed — https://cli.github.com" >&2; exit 5; }
      command -v jq >/dev/null || { echo "bitacora-tracker: jq not installed — https://jqlang.github.io/jq" >&2; exit 5; }
      gh auth status >/dev/null 2>&1 || { echo "bitacora-tracker: gh not authenticated — run 'gh auth login'" >&2; exit 5; }
      ;;
    whoami)    gh api user -q .login ;;
    list-mine) gh issue list --assignee @me --state open \
                 --json number,title,labels,updatedAt,milestone ;;
    view)
      [[ -n "${1:-}" ]] || die "view needs <id>"
      gh issue view "$1" --json number,title,body,labels,state,milestone,comments ;;
    comments)
      [[ -n "${1:-}" ]] || die "comments needs <id>"
      gh issue view "$1" --json comments \
        | jq '[.comments[] | {author: .author.login, createdAt: .createdAt, body: .body}]' ;;
    comment)
      local id="${1:-}"; shift || true
      [[ -n "$id" ]] || die "comment needs <id> --body-file <f>"
      [[ "${1:-}" == "--body-file" && -n "${2:-}" ]] || die "comment needs <id> --body-file <f>"
      gh issue comment "$id" --body-file "$2" ;;
    edit-body)
      local id="${1:-}"; shift || true
      [[ -n "$id" ]] || die "edit-body needs <id> --body-file <f>"
      [[ "${1:-}" == "--body-file" && -n "${2:-}" ]] || die "edit-body needs <id> --body-file <f>"
      gh issue edit "$id" --body-file "$2" ;;
    *) die "unknown verb '$verb'" ;;
  esac
}

case "$tracker" in
  github) gh_backend "$@" ;;
  gitlab) echo "bitacora-tracker: gitlab backend not yet implemented (PR-2)" >&2; exit 3 ;;
  *)      die "unknown TRACKER '$tracker' (want github|gitlab)" ;;
esac
