#!/usr/bin/env bash
# Asserts precompact-handoff-check.sh matches /clear / /compact correctly,
# blocks when handoff is pending, consumes the marker file, and stays silent
# in non-matching, non-ticket, or no-repo cases.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="$DIR/precompact-handoff-check.sh"
HANDOFF_PENDING_SRC="$DIR/../statusline/handoff-pending.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# Skip render tests if jq or git are not on PATH (CI matrix may lack them).
need() { command -v "$1" >/dev/null 2>&1 || { echo "SKIP: $1 not on PATH"; exit 0; }; }
need jq
need git

# Stage the hook + its sourceable sibling in a single temp dir so the hook's
# DIR-relative source resolves to handoff-pending.sh in that same dir.
stage="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$stage" "$work"' EXIT
cp "$HOOK_SRC" "$stage/precompact-handoff-check.sh"
cp "$HANDOFF_PENDING_SRC" "$stage/handoff-pending.sh"
chmod +x "$stage/precompact-handoff-check.sh"

# Helper: feed a JSON prompt on stdin to the hook (no cwd change).
run_hook() {
  printf '%s' "$1" | "$stage/precompact-handoff-check.sh"
}

# Helper: feed a JSON prompt on stdin to the hook, with cwd inside a repo.
cd_run() {
  local r="$1" json="$2"
  ( cd "$r" || exit 1; printf '%s' "$json" | "$stage/precompact-handoff-check.sh" )
}

# Helper: make a temp repo on a given branch with optional dirty + extra commits + marker.
setup_repo() {
  local branch="$1" dirty="$2" extra_commits="$3" marker_ts="$4"
  local r="$work/repo-$RANDOM-$$"
  rm -rf "$r"
  mkdir -p "$r"
  (
    cd "$r" || exit 1
    git init -q
    git checkout -q -b "$branch"
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      git commit --allow-empty -q -m "initial"
    if [ "$marker_ts" -gt 0 ]; then
      mkdir -p .bitacora
      printf '%s\n' "$marker_ts" > .bitacora/last-handoff
    fi
    if [ "$extra_commits" -gt 0 ]; then
      for i in $(seq 1 "$extra_commits"); do
        GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
          git commit --allow-empty -q -m "later $i"
      done
    fi
    if [ "$dirty" = "true" ]; then
      echo wip > work.txt
    fi
  )
  printf '%s' "$r"
}

# === Assertions ============================================================

# Case 1: non-matching prompt → silent (no output, exit 0).
out="$(run_hook '{"prompt":"tell me a joke"}')"
[ -z "$out" ] && pass "non-matching prompt → silent" || bad "non-matching prompt → got: $out"

# Case 2: /clear on a clean ticket repo with marker in the future → silent.
now_ts="$(date +%s)"
future_ts=$(( now_ts + 3600 ))
repo="$(setup_repo "AT-1234" "false" "0" "$future_ts")"
out="$(cd_run "$repo" '{"prompt":"/clear"}')"
[ -z "$out" ] && pass "clean ticket repo + /clear → silent" || bad "clean ticket repo → got: $out"

# Case 3: /clear on ticket branch with dirty tree → block + names ticket.
repo="$(setup_repo "AT-1234-feat" "true" "0" "$future_ts")"
out="$(cd_run "$repo" '{"prompt":"/clear"}')"
if printf '%s' "$out" | grep -q '"decision":"block"' && printf '%s' "$out" | grep -q "AT-1234"; then
  pass "dirty tree on ticket + /clear → block + names ticket"
else
  bad "dirty tree → got: $out"
fi

# Case 4: /clear with extra commits beyond marker → block + count present.
repo="$(setup_repo "AT-1234" "false" "2" "1000")"
out="$(cd_run "$repo" '{"prompt":"/clear"}')"
if printf '%s' "$out" | grep -q '"decision":"block"' && printf '%s' "$out" | grep -q 'commit'; then
  pass "commits since marker + /clear → block + mentions commits"
else
  bad "commits since marker → got: $out"
fi

# Case 5: /clear on non-ticket branch (main) with dirty tree → silent.
repo="$(setup_repo "main" "true" "0" "0")"
out="$(cd_run "$repo" '{"prompt":"/clear"}')"
[ -z "$out" ] && pass "non-ticket branch + /clear → silent" || bad "non-ticket → got: $out"

# Case 6: /clear outside any git repo → silent.
out="$(cd_run "$work" '{"prompt":"/clear"}')"
[ -z "$out" ] && pass "outside git repo + /clear → silent" || bad "no-repo → got: $out"

# Case 7: Marker file present consumes one /clear and is removed.
repo="$(setup_repo "AT-1234" "true" "0" "$future_ts")"
mkdir -p "$repo/.bitacora"
touch "$repo/.bitacora/skip-handoff-once"
out="$(cd_run "$repo" '{"prompt":"/clear"}')"
if [ -z "$out" ] && [ ! -e "$repo/.bitacora/skip-handoff-once" ]; then
  pass "marker file → silent, marker consumed"
else
  bad "marker → got: '$out', marker present: $([ -e "$repo/.bitacora/skip-handoff-once" ] && echo yes || echo no)"
fi

# Case 8: /compact triggers the same logic.
repo="$(setup_repo "AT-1234" "true" "0" "$future_ts")"
out="$(cd_run "$repo" '{"prompt":"/compact"}')"
if printf '%s' "$out" | grep -q '"decision":"block"'; then
  pass "/compact + dirty ticket → block"
else
  bad "/compact → got: $out"
fi

# Case 9: /clear-foo does not match (different command).
repo="$(setup_repo "AT-1234" "true" "0" "$future_ts")"
out="$(cd_run "$repo" '{"prompt":"/clear-foo"}')"
[ -z "$out" ] && pass "/clear-foo (not /clear) → silent" || bad "/clear-foo → got: $out"

# Case 10: Leading whitespace before /clear still matches.
repo="$(setup_repo "AT-1234" "true" "0" "$future_ts")"
out="$(cd_run "$repo" '{"prompt":"   /clear"}')"
if printf '%s' "$out" | grep -q '"decision":"block"'; then
  pass "leading whitespace + /clear → block"
else
  bad "leading whitespace → got: $out"
fi

# Case 11: Malformed JSON stdin → silent (fail-open).
out="$(run_hook 'not json at all')"
[ -z "$out" ] && pass "malformed JSON → silent" || bad "malformed JSON → got: $out"

# Case 12: Empty stdin → silent.
out="$(printf '' | "$stage/precompact-handoff-check.sh")"
[ -z "$out" ] && pass "empty stdin → silent" || bad "empty stdin → got: $out"

exit $fail
