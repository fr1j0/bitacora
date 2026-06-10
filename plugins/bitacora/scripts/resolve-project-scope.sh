#!/usr/bin/env bash
# resolve-project-scope.sh — resolve the current repo's Jira project key for the
# /bitacora:next default query (issue #118). Reads the repo's git remote
# (origin, else the first listed remote), normalizes it to a lowercase
# host/owner/repo slug, and looks the slug up in the next.remote_project_map
# table of the Bitácora config files. The caller (session-next skill) injects
# the printed key into the default JQL, or hard-stops on a non-zero exit —
# never an unscoped site-wide query.
#
# Usage:
#   resolve-project-scope.sh [--dir <repo-dir>] [--repo-config <path>] [--home-config <path>]
#
#   --dir          repository to inspect (default: $CLAUDE_PROJECT_DIR, else .)
#   --repo-config  repo-level config   (default: <dir>/.bitacora.yml)
#   --home-config  home-level config   (default: ~/.claude/bitacora.yml)
#
# Output / exit codes:
#   0  stdout = the mapped Jira project key
#   2  usage error (unknown arg)                    — reason on stderr
#   3  remote resolved but slug not in any map      — stderr names the slug and
#      shows the exact YAML to add
#   4  not a git repo, or the repo has no remotes   — reason on stderr
#
# Precedence is per slug: a repo-level map entry overrides a home one for the
# same slug, so ~/.claude/bitacora.yml can stay the central table.
# Normalization handles git@host:owner/repo(.git), ssh://, git+ssh://, git://,
# http(s):// forms; user@ and a trailing .git or / are stripped and the slug is
# lowercased. Exotic remotes (ports, etc.) still work: map whatever slug the
# exit-3 message reports.
set -uo pipefail

dir="${CLAUDE_PROJECT_DIR:-.}"
repo_config="" home_config=""

while (( $# )); do
  case "$1" in
    --dir)         dir="${2:-}"; shift 2 ;;
    --repo-config) repo_config="${2:-}"; shift 2 ;;
    --home-config) home_config="${2:-}"; shift 2 ;;
    *) echo "resolve-project-scope: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[[ -z "$repo_config" ]] && repo_config="$dir/.bitacora.yml"
[[ -z "$home_config" ]] && home_config="$HOME/.claude/bitacora.yml"

# 1. Read the remote URL: origin, else the first listed remote.
if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "resolve-project-scope: '$dir' is not a git repository — cannot auto-detect a Jira project" >&2
  exit 4
fi
url="$(git -C "$dir" remote get-url origin 2>/dev/null)"
if [[ -z "$url" ]]; then
  first_remote="$(git -C "$dir" remote 2>/dev/null | head -n1)"
  [[ -n "$first_remote" ]] && url="$(git -C "$dir" remote get-url "$first_remote" 2>/dev/null)"
fi
if [[ -z "$url" ]]; then
  echo "resolve-project-scope: repository at '$dir' has no git remote — cannot auto-detect a Jira project" >&2
  exit 4
fi

# 2. Normalize to a lowercase host/owner/repo slug.
slug="$url"
slug="${slug#git+ssh://}"; slug="${slug#ssh://}"; slug="${slug#git://}"
slug="${slug#https://}";   slug="${slug#http://}"
slug="${slug#*@}"            # drop user@
slug="${slug/://}"           # scp-style host:owner/repo → host/owner/repo
slug="${slug%/}"             # trailing slash, then trailing .git (handles .git/)
slug="${slug%.git}"
slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"

# 3. Look the slug up in next.remote_project_map. Minimal YAML walk: enter the
#    top-level `next:` block, then its `remote_project_map:` sub-block, and read
#    `<slug>: <key>` entries (quotes optional, inline comments tolerated) until
#    the block dedents. Not a general YAML parser — just this one table.
lookup() {  # <file> <slug> → prints key, exit 0 iff found
  local file="$1" want="$2"
  [[ -f "$file" ]] || return 1
  awk -v want="$want" -v sq="'" '
    function indent_of(s) { match(s, /^ */); return RLENGTH }
    function strip(s,  f, l) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (length(s) >= 2) {
        f = substr(s, 1, 1); l = substr(s, length(s), 1)
        if ((f == "\"" && l == "\"") || (f == sq && l == sq)) s = substr(s, 2, length(s) - 2)
      }
      return s
    }
    /^[ \t]*#/ { next }
    !in_next { if ($0 ~ /^next:[ \t]*(#.*)?$/) in_next=1; next }
    !in_map {
      if ($0 ~ /^[^ \t]/) { exit 1 }                 # dedent: next block ended, map never seen
      if ($0 ~ /^[ \t]+remote_project_map:[ \t]*(#.*)?$/) { in_map=1; map_indent=indent_of($0) }
      next
    }
    {
      if ($0 ~ /^[ \t]*$/) next
      if (indent_of($0) <= map_indent) exit 1        # dedent: map block ended
      line=$0
      sub(/[ \t]#.*$/, "", line)                     # inline comment
      pos=index(line, ": "); if (pos == 0) next
      k=strip(substr(line, 1, pos-1)); v=strip(substr(line, pos+1))
      if (tolower(k) == want && v != "") { print v; exit 0 }
    }
    END { if (!in_map) exit 1 }
  ' "$file"
}

key=""
for cfg in "$repo_config" "$home_config"; do
  if key="$(lookup "$cfg" "$slug")" && [[ -n "$key" ]]; then
    printf '%s\n' "$key"
    exit 0
  fi
done

cat >&2 <<EOF
resolve-project-scope: no Jira project mapping for '$slug'.
/bitacora:next will not run an unscoped site-wide query. To map this repo, add
under next.remote_project_map in ~/.claude/bitacora.yml (central table) or
$dir/.bitacora.yml (repo-level override):

  next:
    remote_project_map:
      "$slug": "<PROJECT_KEY>"
EOF
exit 3
