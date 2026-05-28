# Bitácora statusLine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Bitácora's Claude Code `statusLine` — a single line that renders `<branch-or-ticket> · ctx <bar> <pct>% · ✎ handoff pending`, with bold + red escalation at ≥85% context. Opt-in via a stable user-side path (`~/.claude/bitacora/statusline.sh`) kept fresh by a sibling SessionStart sync hook (mirroring the `/bit:` alias auto-sync). Realizes the deferred handoff-pending spec.

**Architecture:** Two shell scripts under `plugins/bitacora/statusline/` (`statusline.sh` + sourceable `handoff-pending.sh` pure function) — the pure-function-plus-thin-I/O pattern from `validate-ctx.sh`. A new `plugins/bitacora/scripts/sync-statusline.sh` mirrors `sync-bit-aliases.sh` for the opt-in copy. `session-handoff` skill is extended to write `.bitacora/last-handoff` (the marker the indicator reads). Two new test scripts wired into CI.

**Tech Stack:** bash 3.2+ (so it runs on stock macOS), `jq`, `git` (each git call wrapped in `timeout 1` when available — falls back to no-op on stock macOS), Claude Code `statusLine.command` JSON-over-stdin contract.

**Spec:** `docs/superpowers/specs/2026-05-28-bitacora-statusline-design.md`

**Branch:** Work on `feat/bitacora-statusline` (already created; the spec commit `88d48e6` lives there). Commit per task. **Do not add `Co-Authored-By` trailers** (project convention). Open a PR at the end; do not merge to `main` (branch-protected).

---

## File Structure

| File | Status | Responsibility |
|------|--------|----------------|
| `plugins/bitacora/statusline/handoff-pending.sh` | New | Sourceable pure function `handoff_pending(is_ticket, tree_dirty, last_commit_ts, marker_ts)` |
| `plugins/bitacora/statusline/statusline.sh` | New | Main script: stdin JSON → branch/ticket + meter + handoff segments → one line |
| `plugins/bitacora/scripts/sync-statusline.sh` | New | Opt-in SessionStart copy of `statusline/*.sh` → `~/.claude/bitacora/` |
| `plugins/bitacora/scripts/test-statusline.sh` | New | Pure-function matrix + full-render fixtures (with/without git, NO_COLOR, threshold) |
| `plugins/bitacora/scripts/test-sync-statusline.sh` | New | Mirrors `test-sync-bit-aliases.sh` for the new sync script |
| `plugins/bitacora/hooks/hooks.json` | Modify | Add second SessionStart hook command invoking `sync-statusline.sh` |
| `plugins/bitacora/skills/session-handoff/SKILL.md` | Modify | New section: write epoch seconds to `.bitacora/last-handoff` on successful completion |
| `.gitignore` | Modify | Add `.bitacora/` |
| `.github/workflows/test.yml` | Modify | Add the two new test steps |
| `plugins/bitacora/README.md` | Modify | New *Optional: statusLine* section with the opt-in snippet + caveats |

---

## Task 1: Pure decision function — `handoff-pending.sh` (TDD)

**Files:**
- Create: `plugins/bitacora/statusline/handoff-pending.sh`
- Test (later added in Task 4): `plugins/bitacora/scripts/test-statusline.sh`

This is a small pure function with no I/O — perfect for test-first. The test lives in `test-statusline.sh` (built up across Tasks 1 and 4); in this task we write only the pure-function portion of that test.

- [ ] **Step 1: Write the test scaffold + pure-function assertions**

Create `plugins/bitacora/scripts/test-statusline.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Tests statusline.sh — pure function + full-render fixtures.
# (Full-render section is added in Task 4.)
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

if [ "$fail" -eq 0 ]; then echo "All statusline tests passed."; else echo "Some tests FAILED."; fi
exit "$fail"
```

- [ ] **Step 2: Make the test executable and run it to confirm it fails**

```bash
chmod +x plugins/bitacora/scripts/test-statusline.sh
bash plugins/bitacora/scripts/test-statusline.sh; echo "exit=$?"
```

Expected: fails immediately with an error like `... handoff-pending.sh: No such file or directory` (the source file doesn't exist yet) and exit ≠ 0.

- [ ] **Step 3: Write `handoff-pending.sh`**

Create `plugins/bitacora/statusline/handoff-pending.sh` with exactly this content:

```bash
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
```

- [ ] **Step 4: Run the test — expect all PASS**

```bash
bash plugins/bitacora/scripts/test-statusline.sh; echo "exit=$?"
```

Expected: six `PASS:` lines, `All statusline tests passed.`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/statusline/handoff-pending.sh plugins/bitacora/scripts/test-statusline.sh
git commit -m "feat(statusline): add pure handoff_pending decision function + test"
```

---

## Task 2: Main script — `statusline.sh`

**Files:**
- Create: `plugins/bitacora/statusline/statusline.sh`

The render-fixture tests for this script come in Task 4 (they need a fake-repo helper that's bulky enough to warrant its own task). This task ships the script with a tiny manual smoke check.

- [ ] **Step 1: Write `statusline.sh`**

Create `plugins/bitacora/statusline/statusline.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# statusline.sh — Bitácora's Claude Code statusLine renderer.
#
# Reads JSON from stdin (Claude Code session info), prints one line:
#   <branch-or-ticket>  ·  ctx <bar> <pct>%  ·  ✎ handoff pending
#
# Each segment is omitted independently when its data is unavailable or its
# config toggle is false. At pct >= THRESHOLD (default 85) the meter — and
# the handoff segment when present — render in bold + red (or "⚠ " prefix
# when $NO_COLOR is set). Every git call is wrapped in `timeout 1` so the
# statusLine can never hang. Always exits 0; never errors visibly.
#
# Configuration is env-var-driven for v1 (the user sources their .bitacora.yml
# externally if they wish; YAML parsing in pure bash is out of scope):
#   BITACORA_SHOW_BRANCH   (default: true)
#   BITACORA_SHOW_METER    (default: true)
#   BITACORA_SHOW_HANDOFF  (default: true)
#   BITACORA_THRESHOLD     (default: 85)

set -o pipefail  # do NOT set -u: empty-array expansion would error in bash 4

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/handoff-pending.sh"

SHOW_BRANCH="${BITACORA_SHOW_BRANCH:-true}"
SHOW_METER="${BITACORA_SHOW_METER:-true}"
SHOW_HANDOFF="${BITACORA_SHOW_HANDOFF:-true}"
THRESHOLD="${BITACORA_THRESHOLD:-85}"
KEY_PATTERN='[A-Z][A-Z0-9]+-[0-9]+'

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
git_in() { timeout 1 git -C "$cwd" "$@" 2>/dev/null; }

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

pct=""
if [ "$SHOW_METER" = "true" ]; then
  if [ -n "$pct_raw" ] && [[ "$pct_raw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    pct="${pct_raw%.*}"
    body="ctx $(render_bar "$pct") ${pct}%"
    if [ "$pct" -ge "$THRESHOLD" ]; then segments+=("$(escalate "$body")"); else segments+=("$body"); fi
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
    body="✎ handoff pending"
    if [ -n "$pct" ] && [ "$pct" -ge "$THRESHOLD" ]; then segments+=("$(escalate "$body")"); else segments+=("$body"); fi
  fi
fi

# --- print --------------------------------------------------------------------
if [ "${#segments[@]}" -eq 0 ]; then exit 0; fi
out="${segments[0]}"
for ((i=1; i<${#segments[@]}; i++)); do out+="  ·  ${segments[$i]}"; done
printf '%s\n' "$out"
exit 0
```

- [ ] **Step 2: Make it executable and run a manual smoke test**

```bash
chmod +x plugins/bitacora/statusline/statusline.sh
printf '{"cwd":"%s","context_window":{"used_percentage":42}}' "$PWD" | bash plugins/bitacora/statusline/statusline.sh
```

Expected: a single line containing the current branch name (or ticket key if your branch matches `^[A-Z][A-Z0-9]+-\d+`), followed by `· ctx ███░░░░░ 42%`. No error. (The exact branch text depends on what you're on — verify the *shape*, not the content.)

- [ ] **Step 3: Smoke-test the bar math at the thresholds**

```bash
for p in 0 12 50 76 84 85 87 100; do
  printf '{"cwd":"%s","context_window":{"used_percentage":%d}}' "$PWD" "$p" \
    | bash plugins/bitacora/statusline/statusline.sh
done
```

Expected: each output line carries the right meter — `0%` → 0 filled, `12%` → 1, `50%` → 4, `76%` → 6, `84%` → 7, `85%` → 7 with ANSI bold+red, `87%` → 7 with ANSI, `100%` → 8 with ANSI.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/statusline/statusline.sh
git commit -m "feat(statusline): add main statusline.sh renderer (branch + ctx + handoff)"
```

---

## Task 3: Sync script — `sync-statusline.sh` (TDD; mirrors `sync-bit-aliases.sh`)

**Files:**
- Create: `plugins/bitacora/scripts/sync-statusline.sh`
- Create: `plugins/bitacora/scripts/test-sync-statusline.sh`

- [ ] **Step 1: Write the test**

Create `plugins/bitacora/scripts/test-sync-statusline.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Asserts sync-statusline.sh honors the opt-in gate, copies *.sh files,
# picks up later-added scripts, updates content, and never deletes dest files.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/sync-statusline.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

plugin="$work/plugin"
mkdir -p "$plugin/statusline"
printf 'x\n' > "$plugin/statusline/statusline.sh"
printf 'y\n' > "$plugin/statusline/handoff-pending.sh"
printf 'z\n' > "$plugin/statusline/README.md"   # non *.sh → must be ignored

fakehome="$work/home"
export HOME="$fakehome"
export CLAUDE_PLUGIN_ROOT="$plugin"
dest="$fakehome/.claude/bitacora"

# 1. Not opted in (dest absent) → no-op; must not create the dir.
bash "$SCRIPT"
[ ! -e "$dest" ] && pass "opt-out: no-op when ~/.claude/bitacora absent" \
                 || bad  "opt-out: created dir/files when not opted in"

# 2. Opted in → copies both scripts; non-.sh ignored.
mkdir -p "$dest"
bash "$SCRIPT"
[ -f "$dest/statusline.sh" ]       && pass "copies statusline.sh"           || bad "missing statusline.sh"
[ -f "$dest/handoff-pending.sh" ]  && pass "copies handoff-pending.sh"      || bad "missing handoff-pending.sh"
[ ! -e "$dest/README.md" ]         && pass "ignores non *.sh files"         || bad "copied a non-.sh file"
[ -x "$dest/statusline.sh" ]       && pass "copy is executable"             || bad "copy is not executable"

# 3. Script added in a later release → synced on next run.
printf 'new\n' > "$plugin/statusline/new-helper.sh"
bash "$SCRIPT"
[ -f "$dest/new-helper.sh" ] && pass "later-added script syncs automatically" || bad "new script not synced"

# 4. Content of an existing script changes → updated.
printf 'updated\n' > "$plugin/statusline/statusline.sh"
bash "$SCRIPT"
[ "$(cat "$dest/statusline.sh")" = "updated" ] && pass "updates changed content" || bad "stale content"

# 5. CLAUDE_PLUGIN_ROOT set but its statusline dir missing → no-op, exit 0.
rm -rf "$plugin/statusline"
if bash "$SCRIPT"; then pass "missing source dir → exits 0 (no-op)"; else bad "nonzero exit on missing source dir"; fi

# 6. Add/update only — a user's own dest file is never deleted.
mkdir -p "$plugin/statusline"; printf 'x\n' > "$plugin/statusline/statusline.sh"
printf 'mine\n' > "$dest/custom.sh"
bash "$SCRIPT"
[ -f "$dest/custom.sh" ] && pass "never deletes existing dest files" || bad "deleted a dest file"

if [ "$fail" -eq 0 ]; then echo "All sync-statusline tests passed."; else echo "Some tests FAILED."; fi
exit "$fail"
```

- [ ] **Step 2: Make executable, run to confirm it fails**

```bash
chmod +x plugins/bitacora/scripts/test-sync-statusline.sh
bash plugins/bitacora/scripts/test-sync-statusline.sh; echo "exit=$?"
```

Expected: failures (the sync script doesn't exist yet), exit `1`.

- [ ] **Step 3: Write `sync-statusline.sh`**

Create `plugins/bitacora/scripts/sync-statusline.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# sync-statusline.sh — keep the opt-in Bitácora statusLine scripts in sync.
#
# Copies the plugin's bundled statusline/*.sh into the user's stable location
# ~/.claude/bitacora/, so the user's settings.json can reference a fixed path
# immune to plugin-cache version churn. Run from the plugin's SessionStart
# hook, this means script updates sync automatically — no manual re-run of
# the README snippet.
#
# OPT-IN: does nothing unless ~/.claude/bitacora/ already exists. The user
# opts in once by creating that dir + adding the statusLine snippet to
# settings.json (see the plugin README); until then this is a no-op.
#
# Add/update only: never deletes files in the dest dir. Always exits 0 so a
# SessionStart hook can never break a session.
#
# Source resolution:
#   $CLAUDE_PLUGIN_ROOT/statusline    when set (the hook path) — trusted absolutely
#   ../statusline next to this script otherwise (manual run outside a hook)

dest="${HOME}/.claude/bitacora"

# Opt-in gate: absent dir = not opted in = nothing to do.
[ -d "$dest" ] || exit 0

# Locate the bundled statusline scripts.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  src="${CLAUDE_PLUGIN_ROOT}/statusline"
else
  src="$(cd "$(dirname "$0")/../statusline" 2>/dev/null && pwd || true)"
fi
[ -n "${src:-}" ] && [ -d "$src" ] || exit 0

for f in "$src"/*.sh; do
  [ -e "$f" ] || continue            # literal glob when there are no matches
  name="$(basename "$f")"
  cp -- "$f" "$dest/$name" 2>/dev/null || true
  chmod +x "$dest/$name" 2>/dev/null || true
done

exit 0
```

- [ ] **Step 4: Make executable, run the tests — expect all PASS**

```bash
chmod +x plugins/bitacora/scripts/sync-statusline.sh
bash plugins/bitacora/scripts/test-sync-statusline.sh; echo "exit=$?"
```

Expected: all PASS lines, `All sync-statusline tests passed.`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/scripts/sync-statusline.sh plugins/bitacora/scripts/test-sync-statusline.sh
git commit -m "feat(statusline): add opt-in sync-statusline.sh (mirrors sync-bit-aliases)"
```

---

## Task 4: Render-fixture tests for `statusline.sh`

**Files:**
- Modify: `plugins/bitacora/scripts/test-statusline.sh`

Add the full-render section (against fake git repos and synthetic JSON) that the script needs but couldn't be in Task 1 (the script didn't exist yet).

- [ ] **Step 1: Append render tests to `test-statusline.sh`**

Append (do NOT replace) the following content to `plugins/bitacora/scripts/test-statusline.sh`, immediately **before** the final `if [ "$fail" -eq 0 ]; then echo "All statusline tests passed."; ...` block:

```bash

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
```

- [ ] **Step 2: Run the full test — expect all PASS**

```bash
bash plugins/bitacora/scripts/test-statusline.sh; echo "exit=$?"
```

Expected: every PASS line (pure + render), `All statusline tests passed.`, exit `0`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/scripts/test-statusline.sh
git commit -m "test(statusline): add full-render fixture tests (git states + NO_COLOR)"
```

---

## Task 5: Extend the SessionStart hook

**Files:**
- Modify: `plugins/bitacora/hooks/hooks.json`

- [ ] **Step 1: Replace the file's contents**

`plugins/bitacora/hooks/hooks.json` currently invokes only `sync-bit-aliases.sh`. Replace its full contents with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/sync-bit-aliases.sh\"",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/sync-statusline.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON**

```bash
python3 -c "import json; json.load(open('plugins/bitacora/hooks/hooks.json'))"
```

Expected: no output (valid JSON). Any traceback means the file is malformed.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/hooks/hooks.json
git commit -m "feat(statusline): wire sync-statusline.sh into the SessionStart hook"
```

---

## Task 6: Wire the new tests into CI

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Append the two new steps**

`.github/workflows/test.yml` currently has two steps under `validate-ctx.steps:` (`Run [CTX] validator tests` and `"Run /bit: alias sync tests"`). Append two more steps to the same list so the file's `steps:` becomes:

```yaml
      - uses: actions/checkout@v4
      - name: Run [CTX] validator tests
        run: bash plugins/bitacora/scripts/test-validate-ctx.sh
      - name: "Run /bit: alias sync tests"
        run: bash plugins/bitacora/scripts/test-sync-bit-aliases.sh
      - name: Run statusline tests
        run: bash plugins/bitacora/scripts/test-statusline.sh
      - name: Run statusline sync tests
        run: bash plugins/bitacora/scripts/test-sync-statusline.sh
```

(The two new step names contain no `: ` so no quoting is needed — but quoting them is also fine.)

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"
```

Expected: no output. Any traceback means the file is malformed (e.g. a `: ` in a `name:` that needs quoting).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: run statusline + sync-statusline tests on every PR"
```

---

## Task 7: Extend `session-handoff` to write the marker

**Files:**
- Modify: `plugins/bitacora/skills/session-handoff/SKILL.md`

- [ ] **Step 1: Insert a new section 7 after Report**

In `plugins/bitacora/skills/session-handoff/SKILL.md`, find the closing of section 6 "Report" (the line `note it's safe to /clear.`). Immediately **after** that section (i.e. before any later section), insert this new section, exactly:

```markdown
## 7. Mark the session handed off (for the statusLine indicator)

After a successful Report — whether full Jira-writing or local-only — write the current
epoch seconds to `.bitacora/last-handoff` in the project root. Create `.bitacora/` if it
does not exist. This marker is read by the opt-in Bitácora statusLine to clear the
`✎ handoff pending` segment. Resetting the clock on local-only handoffs is harmless and
keeps the indicator from going stale forever on Jira-less work. Skip silently if the
working directory is not a git repo (no `.git`) — the indicator is git-scoped, and there
is nothing for it to read in that case.

Exact command:

```bash
[ -d .git ] && { mkdir -p .bitacora && date +%s > .bitacora/last-handoff; } || true
```
```

- [ ] **Step 2: Verify the new section is present and well-formed**

```bash
grep -n "^## 7\. Mark the session handed off" plugins/bitacora/skills/session-handoff/SKILL.md
```

Expected: exactly one line printed, pointing at the new section.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-handoff/SKILL.md
git commit -m "feat(handoff): write .bitacora/last-handoff marker on success (for statusLine)"
```

---

## Task 8: Gitignore `.bitacora/`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Append the marker-dir ignore**

Append (do NOT modify earlier lines) the following block to the end of `.gitignore`:

```
# Bitácora per-project state (handoff marker for the statusLine indicator)
.bitacora/
```

- [ ] **Step 2: Verify it takes effect**

```bash
mkdir -p .bitacora && date +%s > .bitacora/last-handoff
git status --porcelain .bitacora/
```

Expected: no output (the marker dir is ignored). Then clean up: `rm -rf .bitacora`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore .bitacora/ (per-project statusLine marker dir)"
```

---

## Task 9: Plugin README — `Optional: statusLine` section

**Files:**
- Modify: `plugins/bitacora/README.md`

- [ ] **Step 1: Add the new section directly after the `/bit:` alias section**

Find the end of the existing `## Optional: the shorter /bit: alias` section in `plugins/bitacora/README.md` (the paragraph ending with `…run the same workflows as their /bitacora:… forms.` plus the trailing auto-sync paragraph). Immediately **after** that section and **before** the `## The [CTX] format` section, insert this new section, exactly:

````markdown
## Optional: the statusLine

A single-line Claude Code statusLine that shows what ticket/branch you're on, how full
your context window is, and whether you have un-handed-off ticket work. Bolds + reds at
≥85% context — the moment to run `/bitacora:handoff` then `/clear` + `/bitacora:resume`.

```
AT-4104  ·  ctx ██████░░ 76%  ·  ✎ handoff pending
```

Opt in once (per machine):

```bash
mkdir -p ~/.claude/bitacora
src_file="$(find ~/.claude/plugins -path '*bitacora/statusline/statusline.sh' | head -1)"
if [ -z "$src_file" ]; then
  echo "bitacora statusline not found — is the plugin installed?" >&2
else
  cp "$(dirname "$src_file")"/*.sh ~/.claude/bitacora/
fi
```

Then add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/bitacora/statusline.sh"
  }
}
```

After opt-in, a `SessionStart` hook keeps the scripts in sync at `~/.claude/bitacora/`
so future plugin releases pick up automatically — no need to re-run the snippet.

**Caveats**

- **Claude Code permits exactly one `statusLine.command`** — installing this **replaces**
  any existing statusLine. Wrap our script if you have your own (unsupported in v1).
- The `✎ handoff pending` segment appears only on ticket branches (`PROJ-1234`-style names)
  with unsaved work since the last `/bitacora:handoff`.
- Set `NO_COLOR=1` to disable ANSI; a `⚠ ` prefix substitutes at the escalation threshold.
- Per-segment toggles via env vars: `BITACORA_SHOW_BRANCH`, `BITACORA_SHOW_METER`,
  `BITACORA_SHOW_HANDOFF`, `BITACORA_THRESHOLD` (default `85`).
````

- [ ] **Step 2: Verify the section is present, with the right neighbors**

```bash
grep -n "^## " plugins/bitacora/README.md
```

Expected: among the section headings, `## Optional: the shorter /bit: alias` appears before `## Optional: the statusLine`, which appears before `## The [CTX] format`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/README.md
git commit -m "docs: add 'Optional: the statusLine' opt-in section to plugin README"
```

---

## Task 10: Live acceptance

**No file changes — manual verification after Tasks 1–9 are committed locally.**

- [ ] **Step 1: Run the full test suite locally**

```bash
bash plugins/bitacora/scripts/test-validate-ctx.sh && \
bash plugins/bitacora/scripts/test-sync-bit-aliases.sh && \
bash plugins/bitacora/scripts/test-statusline.sh && \
bash plugins/bitacora/scripts/test-sync-statusline.sh
echo "exit=$?"
```

Expected: each script prints all PASS lines and its summary; final `exit=0`.

- [ ] **Step 2: Opt in on this machine**

Run the README snippet from Task 9, then add the `statusLine` entry to `~/.claude/settings.json`.

- [ ] **Step 3: Start a fresh Claude Code session in this repo and observe the statusLine**

Confirm structurally:
- The line shows the current branch (or ticket key if branch matches the pattern), then `ctx <bar> <pct>%`.
- Off a ticket branch (e.g. `main`), no `handoff pending` segment.
- On a ticket branch with uncommitted work, `✎ handoff pending` appears.
- After running `/bitacora:handoff` successfully, the marker is written and the indicator clears.
- At ≥85% context (force it by piping a fixture into the script directly if you can't naturally hit it during testing), the meter (and handoff segment when present) render in bold + red.
- With `NO_COLOR=1`, no ANSI escapes leak; `⚠ ` appears at the threshold.

If anything fails: open an issue or fix inline and re-run from the offending task.

---

## Task 11: Open the PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/bitacora-statusline
```

- [ ] **Step 2: Open the PR against `main`**

```bash
gh pr create --base main --head feat/bitacora-statusline \
  --title "feat: Bitácora statusLine (combined handoff-pending + context meter)" \
  --body "$(cat <<'EOF'
Ships Bitácora's Claude Code statusLine — a single line rendering `<branch-or-ticket> · ctx <bar> <pct>% · ✎ handoff pending`, with bold + red escalation at ≥85% context. Realizes the deferred 2026-05-27 handoff-pending spec by also building the Phase 6 statusLine itself (no statusLine script existed before).

### Design
Spec: `docs/superpowers/specs/2026-05-28-bitacora-statusline-design.md`
Plan: `docs/superpowers/plans/2026-05-28-bitacora-statusline.md`

- **Two scripts** in `plugins/bitacora/statusline/`: `statusline.sh` (orchestrator, reads JSON from stdin) + sourceable `handoff-pending.sh` (pure decision function, validate-ctx.sh pattern).
- **Opt-in via stable path** `~/.claude/bitacora/statusline.sh` kept fresh by a new `sync-statusline.sh` SessionStart hook (mirrors the proven `sync-bit-aliases.sh` opt-in pattern).
- **Marker** written by `session-handoff` on successful completion at `.bitacora/last-handoff` (project-root, gitignored).
- **NO_COLOR honored** with a `⚠ ` prefix at the threshold.
- **Per-segment env toggles** + `BITACORA_THRESHOLD` for v1 (YAML config is a post-v1 concern).

### Files
- New: `statusline/{statusline,handoff-pending}.sh`
- New: `scripts/{sync-statusline,test-statusline,test-sync-statusline}.sh`
- Modified: `hooks/hooks.json` (second SessionStart command); `skills/session-handoff/SKILL.md` (new section 7); `.gitignore`; `.github/workflows/test.yml` (two new test steps); `plugins/bitacora/README.md` (new opt-in section).

### Verification
All four test scripts pass locally and in CI; live acceptance on this machine confirms the line renders, the threshold escalates, the indicator clears after handoff, and `NO_COLOR` degrades gracefully.

### Roadmap after this lands
Bitácora's published roadmap is empty — `/handoff`, `/resume`, `/status`, `/help`, and the statusLine are shipped; `/improve`, `/spike`, and `/next` have all been formally dropped or deferred for documented reasons.
EOF
)"
```

- [ ] **Step 3: Wait for CI** (`gh pr checks <PR#>`) — all four test steps must pass.

- [ ] **Step 4: Hand off** — do **not** merge from this plan. Surface the PR URL for the user's review/merge (project convention: PR → CR → merge; never push to `main`).

---

## Self-Review

**Spec coverage:** every spec section maps to a task —
- File structure §all → Tasks 1, 2, 3, 5, 6, 7, 8, 9 (each new/modified file has its own task).
- Rendering §Segment 1 (branch/ticket) → Task 2 (script) + Task 4 (render fixtures, non-ticket case).
- Rendering §Segment 2 (context meter, round-nearest math, threshold) → Task 2 (script + smoke at 0/12/50/76/84/85/87/100) + Task 4 (regression: bar at 50%, ANSI at 88%).
- Rendering §Segment 3 (handoff pending) → Task 1 (pure function) + Task 2 (script wiring) + Task 4 (dirty/clean/marker-future cases).
- Rendering §NO_COLOR → `⚠` prefix → Task 2 (`escalate` helper) + Task 4 (NO_COLOR tests).
- Detection §git safety (`timeout 1`) → Task 2 (`git_in` helper).
- Modify session-handoff §marker write → Task 7.
- Opt-in mechanism §stable path + extended sync hook → Tasks 3, 5, 9.
- Configuration §env-var toggles + `BITACORA_THRESHOLD` → Task 2 (defaults at the top of `statusline.sh`); README documents the toggles in Task 9.
- Error/edge §all rows of the table → Task 4 fixtures (non-repo, missing pct, marker-future, non-ticket branch) + Task 2 defensive `2>/dev/null` and `|| true` patterns.
- Testing §both scripts wired into CI → Tasks 4 + 6.
- Decisions §all → reflected in scripts (Tasks 1–3), hook (5), skill change (7), and README copy (9).

**Placeholder scan:** none — every step shows the exact content/diff/command and the expected output. No "TBD" / "implement error handling" / "similar to Task N." The only `<...>` substitutions are template placeholders inside example renderings (`<branch-or-ticket>`, `<pct>%`) and the PR-number placeholder in the `gh pr checks <PR#>` instruction, which is by design.

**Type / identifier consistency:** identifiers used across tasks are spelled the same in every place they appear —
- script filenames (`statusline.sh`, `handoff-pending.sh`, `sync-statusline.sh`, `test-statusline.sh`, `test-sync-statusline.sh`) — checked.
- function name `handoff_pending` and its 4 args (`is_ticket`, `tree_dirty`, `last_commit_ts`, `marker_ts`) — same in Task 1 source, Task 1 tests, Task 2 caller, Task 4 tests.
- env-var names (`BITACORA_SHOW_BRANCH/SHOW_METER/SHOW_HANDOFF/THRESHOLD`, `NO_COLOR`) — same in Task 2 script and Task 9 README.
- dest path `~/.claude/bitacora/` — same in Task 3 script, Task 3 test, Task 9 README, settings.json snippet.
- marker path `.bitacora/last-handoff` — same in Task 2 reader, Task 7 writer, Task 8 gitignore.

**Scope:** one focused feature, one branch, one PR; eleven tasks, ten of them small and contained (the eleventh is the manual live acceptance).

---

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task with two-stage review between tasks.
2. **Inline Execution** — execute tasks in this session with checkpoints (after the pure function + main script; after the sync infrastructure + CI; after the marker + docs; before the live acceptance).

Which approach?
