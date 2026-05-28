#!/usr/bin/env bash
# Tests statusline.sh — pure function (Part 1) + full-render fixtures (Part 2).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE_DIR="$DIR/../statusline"
STATUSLINE="$STATUSLINE_DIR/statusline.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# --- Part 1: handoff_pending pure function ------------------------------------
. "$STATUSLINE_DIR/handoff-pending.sh"

# handoff_pending(is_ticket, tree_dirty, last_commit_ts, marker_ts) -> 0/1
if   handoff_pending true  true  100 0   ; then pass "pure: ticket + dirty tree → on"     ; else bad "pure: ticket+dirty"      ; fi
if   handoff_pending true  false 200 100 ; then pass "pure: ticket + commit > marker → on"; else bad "pure: commit>marker"     ; fi
if ! handoff_pending true  false 100 200 ; then pass "pure: ticket + clean + marker > commit → off"; else bad "pure: marker>commit"; fi
if ! handoff_pending false true  100 0   ; then pass "pure: non-ticket branch → off"      ; else bad "pure: non-ticket"        ; fi
if   handoff_pending true  true  0   0   ; then pass "pure: no marker, work present → on" ; else bad "pure: no marker"         ; fi
if ! handoff_pending true  false 100 100 ; then pass "pure: commit == marker → off"       ; else bad "pure: commit==marker"    ; fi


# --- Part 2: Full render against fake repos + JSON fixtures -------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "SKIP: $1 not on PATH (render tests)"; exit 0; }; }
need jq
need git

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Create a fake git repo on a given branch with one commit.
fake_repo() {
  local repo="$1" branch="$2"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git checkout -q -b "$branch"
    : > f
    git add f
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      git commit -q -m init
  )
}

# Render: stdin JSON pointing at $repo with $pct context.
render() {
  local repo="$1" pct="$2"
  printf '{"cwd":"%s","context_window":{"used_percentage":%s}}' "$repo" "$pct" \
    | bash "$STATUSLINE"
}

repo="$work/repo"
fake_repo "$repo" "AT-1234"

# Seed .gitignore so .bitacora/ is never untracked-dirty, and write a marker
# at the commit timestamp so the baseline state is "already handed off" (clean).
printf '.bitacora/\n' >> "$repo/.gitignore"
(
  cd "$repo"
  git add .gitignore
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git commit -q -m "chore: ignore .bitacora"
)
mkdir -p "$repo/.bitacora"
printf '%s\n' "$(git -C "$repo" log -1 --format=%ct)" > "$repo/.bitacora/last-handoff"

# Render: ticket branch, low %, clean tree → ticket key + meter, NO handoff.
out="$(render "$repo" 50)"
[[ "$out" == *"AT-1234"* ]]        && pass "render: ticket key shown"           || bad "render: missing ticket key (got: $out)"
[[ "$out" == *"50%"* ]]            && pass "render: ctx % shown"                || bad "render: missing 50% (got: $out)"
[[ "$out" == *"████░░░░"* ]]       && pass "render: bar math at 50%"            || bad "render: wrong bar at 50%"
[[ "$out" != *"handoff pending"* ]] && pass "render: clean tree → no handoff"   || bad "render: false-positive handoff"

# Render: dirty tree → handoff segment present.
echo dirty > "$repo/f"
out="$(render "$repo" 50)"
[[ "$out" == *"handoff pending"* ]] && pass "render: dirty tree → handoff pending" || bad "render: handoff missing on dirty"

# Render: pct ≥ 85 → ANSI bold+red present (NO_COLOR unset).
out="$(render "$repo" 88)"
[[ "$out" == *$'\033[1;31m'* ]] && pass "render: ≥85% → ANSI bold+red"        || bad "render: missing escalation ANSI"

# Render: NO_COLOR set → no ANSI, ⚠ prefix instead.
out="$(NO_COLOR=1 render "$repo" 88)"
[[ "$out" != *$'\033['* ]]      && pass "render: NO_COLOR → no ANSI"          || bad "render: ANSI leaked with NO_COLOR"
[[ "$out" == *"⚠"* ]]           && pass "render: NO_COLOR → ⚠ prefix at threshold" || bad "render: missing ⚠ prefix"

# Render: missing context_window field → 'ctx ?'.
out="$(printf '{"cwd":"%s","context_window":{}}' "$repo" | bash "$STATUSLINE")"
[[ "$out" == *"ctx ?"* ]] && pass "render: missing pct → 'ctx ?'" || bad "render: missing ctx ? fallback (got: $out)"

# Render: marker_ts in the future clears the handoff segment (when tree is also clean).
ts_future=$(( $(date +%s) + 3600 ))
mkdir -p "$repo/.bitacora"
printf '%s\n' "$ts_future" > "$repo/.bitacora/last-handoff"
(cd "$repo" && git checkout -q -- f)   # clean the working tree
out="$(render "$repo" 50)"
[[ "$out" != *"handoff pending"* ]] && pass "render: clean + marker > commit → no handoff" \
                                    || bad "render: handoff should be cleared (got: $out)"

# Render: non-ticket branch → branch name shown, handoff segment absent.
(cd "$repo" && git checkout -q -b not-a-ticket-branch)
out="$(render "$repo" 50)"
[[ "$out" == *"not-a-ticket-branch"* ]] && pass "render: non-ticket → branch name shown" || bad "render: branch name missing"
[[ "$out" != *"handoff pending"* ]]     && pass "render: non-ticket → no handoff"        || bad "render: handoff on non-ticket"

# Render: not a git repo → branch + handoff absent, meter still renders.
notrepo="$work/notrepo"; mkdir -p "$notrepo"
out="$(render "$notrepo" 42)"
[[ "$out" == *"42%"* ]]             && pass "render: non-repo → meter still renders"      || bad "render: meter missing"
[[ "$out" != *"handoff pending"* ]] && pass "render: non-repo → no handoff segment"       || bad "render: handoff on non-repo"

if [ "$fail" -eq 0 ]; then echo "All statusline tests passed."; else echo "Some tests FAILED."; fi
exit "$fail"
