#!/usr/bin/env bash
# resolve-tracker.sh — resolve the active tracker backend for a repo:
# github | gitlab | jira. An explicit top-level `tracker:` in config wins;
# otherwise infer from the git remote host. Sibling to resolve-project-scope.sh
# and reuses its remote-slug normalization.
#
# Usage:
#   resolve-tracker.sh [--dir <repo-dir>] [--repo-config <path>] [--home-config <path>]
#
# Output / exit codes:
#   0  stdout = github | gitlab | jira
#   2  usage error (unknown arg) or invalid tracker value   — reason on stderr
#   4  not a git repo / no remote AND no explicit tracker:   — reason on stderr
set -uo pipefail

dir="${CLAUDE_PROJECT_DIR:-.}"
repo_config="" home_config=""
while (( $# )); do
  case "$1" in
    --dir)         dir="${2:-}"; shift 2 ;;
    --repo-config) repo_config="${2:-}"; shift 2 ;;
    --home-config) home_config="${2:-}"; shift 2 ;;
    *) echo "resolve-tracker: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[[ -z "$repo_config" ]] && repo_config="$dir/.bitacora.yml"
[[ -z "$home_config" ]] && home_config="$HOME/.claude/bitacora.yml"

# 1. Explicit top-level `tracker:` — repo config first, then home config.
read_tracker() {  # <file> → prints lowercased value iff a top-level tracker: exists
  local file="$1"
  [[ -f "$file" ]] || return 1
  awk '
    /^[ \t]*#/ { next }
    /^tracker:[ \t]*/ {
      line=$0; sub(/^tracker:[ \t]*/, "", line); sub(/[ \t]#.*$/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      gsub(/^["'"'"']|["'"'"']$/, "", line)
      if (line != "") { print tolower(line); found=1; exit }
    }
    END { if (!found) exit 1 }
  ' "$file"
}
for cfg in "$repo_config" "$home_config"; do
  if t="$(read_tracker "$cfg")" && [[ -n "$t" ]]; then
    case "$t" in
      jira|github|gitlab) printf '%s\n' "$t"; exit 0 ;;
      *) echo "resolve-tracker: invalid tracker '$t' in $cfg (want jira|github|gitlab)" >&2; exit 2 ;;
    esac
  fi
done

# 2. Infer from the git remote host.
if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "resolve-tracker: '$dir' is not a git repository and no explicit tracker: is set" >&2
  exit 4
fi
url="$(git -C "$dir" remote get-url origin 2>/dev/null)"
if [[ -z "$url" ]]; then
  first_remote="$(git -C "$dir" remote 2>/dev/null | head -n1)"
  [[ -n "$first_remote" ]] && url="$(git -C "$dir" remote get-url "$first_remote" 2>/dev/null)"
fi
if [[ -z "$url" ]]; then
  echo "resolve-tracker: repository at '$dir' has no git remote and no explicit tracker: is set" >&2
  exit 4
fi

# Normalize to host (same stripping as resolve-project-scope.sh, then first segment).
slug="$url"
slug="${slug#git+ssh://}"; slug="${slug#ssh://}"; slug="${slug#git://}"
slug="${slug#https://}";   slug="${slug#http://}"
slug="${slug#*@}"            # drop user@
slug="${slug/://}"           # scp-style host:owner/repo → host/owner/repo
slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
host="${slug%%/*}"
case "$host" in
  github.com|*.github.com) printf 'github\n' ;;
  gitlab.com|*.gitlab.com) printf 'gitlab\n' ;;
  *)                       printf 'jira\n'   ;;
esac
exit 0
