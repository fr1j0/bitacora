# Handoff Guardrail Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the handoff guardrail per `docs/superpowers/specs/2026-05-29-handoff-guardrail-hook-design.md` — a UserPromptSubmit hook that intercepts `/clear` and `/compact` when handoff work is pending, suggests `/bitacora:handoff`, and exposes a one-shot marker-file escape hatch.

**Architecture:** One new shell script (`precompact-handoff-check.sh`) + one assertion harness. Wired into `plugins/bitacora/hooks/hooks.json` as a UserPromptSubmit entry. The existing `sync-statusline.sh` SessionStart hook is extended to also copy the new script into `~/.claude/bitacora/` so opt-in users get auto-updates. README documents the manual `settings.json` install path for fine-grained control. CI gains one new test step.

**Tech Stack:** Bash 3.2+, `jq` (already a soft-dep via statusline). Branch already created: `feat/handoff-guardrail-hook` (spec at `6709828`).

> **Convention note for the implementer:** every `old_string` and `new_string` payload in this plan is wrapped in a **4-backtick** outer code fence (```` ```` ````) so that ordinary 3-backtick code fences inside the payload don't break the outer wrapper. When applying via the `Edit` tool, copy the literal text *between* the two 4-backtick fences and pass it verbatim — do not strip or normalize whitespace, do not re-render any inner 3-backtick fences.

---

## File Structure

**New (no existing):**

- `plugins/bitacora/scripts/precompact-handoff-check.sh` — the hook script. Reads JSON from stdin, decides whether to block, emits JSON on stdout when blocking.
- `plugins/bitacora/scripts/test-precompact-handoff-check.sh` — assertion harness for the decision matrix.

**Edited (in dependency order):**

- `plugins/bitacora/hooks/hooks.json` — add the `UserPromptSubmit` entry pointing at the new script.
- `plugins/bitacora/scripts/sync-statusline.sh` — extend to also copy `precompact-handoff-check.sh` into `~/.claude/bitacora/`. Same opt-in / additive pattern.
- `plugins/bitacora/scripts/test-sync-statusline.sh` — assert the hook script is copied when the source is present.
- `plugins/bitacora/README.md` — new "Optional: the handoff guardrail hook" subsection following the statusLine subsection.
- `.github/workflows/test.yml` — add one new step running `test-precompact-handoff-check.sh` inside the existing `shell-tests` matrix job.

**No-touch files** — explicitly out of scope:

- `plugins/bitacora/statusline/handoff-pending.sh` — reused as-is; no edits.
- `plugins/bitacora/statusline/statusline.sh` — unrelated to the hook.
- Any skill, command, or alias file — the hook is infra, not a command.
- `PLUGIN_BRIEF.md`, root `README.md` — the hook is opt-in plugin infrastructure; plugin README is the right surface.

---

## Task 1: Write the hook script and its test harness (TDD)

The script is real shell logic with multiple decision branches. Tests come first: the harness lands with all assertions failing because the script doesn't exist yet; then the script lands and turns them green.

**Files:**
- Create: `plugins/bitacora/scripts/precompact-handoff-check.sh`
- Create: `plugins/bitacora/scripts/test-precompact-handoff-check.sh`

### Step 1: Write the test harness (will fail because the script is absent)

- [ ] **Create the harness** at `plugins/bitacora/scripts/test-precompact-handoff-check.sh` with this exact content:

````
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
````

### Step 2: Run the harness to confirm it fails (script does not exist)

- [ ] Run:

```bash
plugins/bitacora/scripts/test-precompact-handoff-check.sh 2>&1 | tail -20
```

Expected: every case after the `SKIP:`-guarded line fails because `precompact-handoff-check.sh` does not exist (the `cp` early in the harness fails, the trap runs, and the script exits non-zero). Specifically, the output should end with a non-zero exit; the cp error mentions the missing file. This is the failing-test phase of TDD.

### Step 3: Write the hook script

- [ ] **Create** `plugins/bitacora/scripts/precompact-handoff-check.sh` with this exact content:

````
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
SOURCE_HANDOFF_PENDING="$DIR/handoff-pending.sh"

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
# shellcheck source=./handoff-pending.sh
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
  [ -z "$marker_ts" ] && marker_ts=0
fi

# 10. Decide. False ⇒ nothing to do.
if ! handoff_pending "$is_ticket" "$tree_dirty" "$last_commit_ts" "$marker_ts"; then
  exit 0
fi

# 11. Count commits since the marker (best-effort; 0 if anything goes sideways).
pending_commits=0
if [ "$last_commit_ts" -gt "$marker_ts" ]; then
  pending_commits="$(git -C "$repo_root" log --oneline --since="@$marker_ts" 2>/dev/null | wc -l | tr -d ' ')"
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
````

### Step 4: Make the script executable and run the harness

- [ ] Run:

```bash
chmod +x plugins/bitacora/scripts/precompact-handoff-check.sh
plugins/bitacora/scripts/test-precompact-handoff-check.sh 2>&1 | tail -15
```

Expected: every assertion `PASS`; the script exits 0.

### Step 5: Lint the new script with ShellCheck

- [ ] Run via Docker (matches the CI's `lint` job):

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --severity=warning plugins/bitacora/scripts/precompact-handoff-check.sh
```

Expected: exit 0, no output. If ShellCheck flags an issue, fix it in `precompact-handoff-check.sh` and re-run the harness + the linter before committing.

### Step 6: Confirm existing test suites still pass

- [ ] Run:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
plugins/bitacora/scripts/test-statusline.sh
plugins/bitacora/scripts/test-sync-statusline.sh
```

Expected: every line `PASS`; every script exits 0.

### Step 7: Commit

- [ ] Stage and commit both new files together:

```bash
git add plugins/bitacora/scripts/precompact-handoff-check.sh \
        plugins/bitacora/scripts/test-precompact-handoff-check.sh
git commit -m "feat(hook): add UserPromptSubmit guardrail for /clear and /compact"
```

---

## Task 2: Wire the hook into the plugin's `hooks.json`

The plugin's `hooks.json` already declares two `SessionStart` hooks. Add a new `UserPromptSubmit` top-level entry pointing at the new script.

**Files:**
- Modify: `plugins/bitacora/hooks/hooks.json`

### Step 1: Replace the file with the extended version

- [ ] **Edit** `plugins/bitacora/hooks/hooks.json`. Use the `Edit` tool with:

`old_string`:

````
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
````

`new_string`:

````
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
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/precompact-handoff-check.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
````

### Step 2: Verify the JSON is well-formed

- [ ] Run:

```bash
python3 -c "import json; json.load(open('plugins/bitacora/hooks/hooks.json'))"
echo "exit=$?"
```

Expected: no output and `exit=0`. Any output means malformed JSON; fix before committing.

### Step 3: Commit

- [ ] Stage and commit:

```bash
git add plugins/bitacora/hooks/hooks.json
git commit -m "feat(hook): wire precompact-handoff-check into UserPromptSubmit"
```

---

## Task 3: Extend `sync-statusline.sh` to also copy the hook script

The existing `sync-statusline.sh` already keeps `~/.claude/bitacora/` in sync with the plugin's bundled statusline scripts. Extend it to also copy `precompact-handoff-check.sh` from `plugins/bitacora/scripts/` so opt-in users get auto-updates with no extra steps.

**Files:**
- Modify: `plugins/bitacora/scripts/sync-statusline.sh`
- Modify: `plugins/bitacora/scripts/test-sync-statusline.sh`

### Step 1: Add the test assertion that the hook script is copied

- [ ] **Edit** `plugins/bitacora/scripts/test-sync-statusline.sh` to add a new assertion. First, view the existing assertions so the new one matches the style:

```bash
grep -n "pass\|bad\|cp\|sync-statusline" plugins/bitacora/scripts/test-sync-statusline.sh | head -25
```

You'll see assertions like `[ -f "$dest/statusline.sh" ]       && pass "copies statusline.sh"           || bad "missing statusline.sh"`. Add a new assertion in the same style.

Use the `Edit` tool with:

`old_string`:

````
[ -f "$dest/statusline.sh" ]       && pass "copies statusline.sh"           || bad "missing statusline.sh"
[ -f "$dest/handoff-pending.sh" ]  && pass "copies handoff-pending.sh"      || bad "missing handoff-pending.sh"
````

`new_string`:

````
[ -f "$dest/statusline.sh" ]              && pass "copies statusline.sh"               || bad "missing statusline.sh"
[ -f "$dest/handoff-pending.sh" ]         && pass "copies handoff-pending.sh"          || bad "missing handoff-pending.sh"
[ -f "$dest/precompact-handoff-check.sh" ] && pass "copies precompact-handoff-check.sh" || bad "missing precompact-handoff-check.sh"
````

(Note: I extended the column alignment slightly. If the existing column alignment is hard to match exactly, prefer correctness — single trailing whitespace is fine, the test parses by value.)

### Step 2: Run the test to confirm it fails

- [ ] Run:

```bash
plugins/bitacora/scripts/test-sync-statusline.sh 2>&1 | tail -10
```

Expected: the new "copies precompact-handoff-check.sh" assertion fails because `sync-statusline.sh` doesn't yet know to copy it. Other assertions still pass. Script exits non-zero.

### Step 3: Extend the sync script to copy the hook from `scripts/`

The existing script copies from `${CLAUDE_PLUGIN_ROOT}/statusline/*.sh`. The hook lives in `${CLAUDE_PLUGIN_ROOT}/scripts/precompact-handoff-check.sh` — different source directory — so add a second copy block.

- [ ] **Edit** `plugins/bitacora/scripts/sync-statusline.sh`. Use the `Edit` tool with:

`old_string`:

````
for f in "$src"/*.sh; do
  [ -e "$f" ] || continue            # literal glob when there are no matches
  name="$(basename "$f")"
  cp -- "$f" "$dest/$name" 2>/dev/null || true
  chmod +x "$dest/$name" 2>/dev/null || true
done

exit 0
````

`new_string`:

````
for f in "$src"/*.sh; do
  [ -e "$f" ] || continue            # literal glob when there are no matches
  name="$(basename "$f")"
  cp -- "$f" "$dest/$name" 2>/dev/null || true
  chmod +x "$dest/$name" 2>/dev/null || true
done

# Also copy the UserPromptSubmit hook (lives in scripts/, not statusline/).
# Same opt-in semantics: the dest dir already exists (the guard above passed),
# so the user has opted in. Additive: never deletes; always exits 0.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  hook_src="${CLAUDE_PLUGIN_ROOT}/scripts/precompact-handoff-check.sh"
else
  hook_src="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/precompact-handoff-check.sh"
fi
if [ -r "$hook_src" ]; then
  cp -- "$hook_src" "$dest/precompact-handoff-check.sh" 2>/dev/null || true
  chmod +x "$dest/precompact-handoff-check.sh" 2>/dev/null || true
fi

exit 0
````

### Step 4: Run the sync test again

- [ ] Run:

```bash
plugins/bitacora/scripts/test-sync-statusline.sh 2>&1 | tail -10
```

Expected: all assertions `PASS`; script exits 0. The new "copies precompact-handoff-check.sh" assertion is now green.

### Step 5: Lint the modified script

- [ ] Run ShellCheck (warning severity):

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --severity=warning plugins/bitacora/scripts/sync-statusline.sh
```

Expected: exit 0, no output.

### Step 6: Confirm other test suites still pass

- [ ] Run:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
plugins/bitacora/scripts/test-statusline.sh
plugins/bitacora/scripts/test-precompact-handoff-check.sh
```

Expected: every line `PASS`; every script exits 0.

### Step 7: Commit

- [ ] Stage and commit both files:

```bash
git add plugins/bitacora/scripts/sync-statusline.sh \
        plugins/bitacora/scripts/test-sync-statusline.sh
git commit -m "feat(hook): sync precompact-handoff-check into ~/.claude/bitacora/"
```

---

## Task 4: Add the "Optional: the handoff guardrail hook" subsection to the plugin README

Mirrors the existing "Optional: the statusLine" subsection's shape. The user opts in once per machine: copy the script + edit `settings.json`. After opt-in, the SessionStart sync keeps the script up to date.

**Files:**
- Modify: `plugins/bitacora/README.md`

### Step 1: Add the new subsection between "Optional: the statusLine" and "The `[CTX]` format"

- [ ] **Edit** `plugins/bitacora/README.md`. Use the `Edit` tool with:

`old_string`:

````
## The `[CTX]` format

See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](../../docs/JIRA_AGENT_COMMENT_FORMAT.md). The
operational source of truth is the `jira-comment-format` skill; `scripts/validate-ctx.sh`
classifies any comment as `compliant` / `malformed` / `not-in-format`.
````

`new_string`:

````
## Optional: the handoff guardrail hook

A Claude Code `UserPromptSubmit` hook that intercepts `/clear` and `/compact` when
Bitácora detects pending handoff work on the current ticket branch, prints a clear
action-oriented message suggesting `/bitacora:handoff`, and exposes a one-shot
escape hatch via a `.bitacora/skip-handoff-once` marker file. The friction it
catches: typing `/clear` to recover from context pressure without first writing the
`[CTX]` comment that would have shared the session's outcomes with teammates.

The hook only blocks when **all** of these hold:

- The prompt body starts with `/clear` or `/compact` (after trimming leading whitespace).
- The current directory is inside a git repository.
- The current branch matches a project-key pattern (e.g. `PROJ-1234`).
- Bitácora's existing handoff-pending check (the same one the statusLine uses) is true.

Anything else → silent no-op. The hook also exits silently (fail-open) on any
infrastructure trouble — missing `jq`, missing source files, hook timeouts, malformed
input — so it can never brick a `/clear` you genuinely needed.

Opt in once (per machine):

```bash
mkdir -p ~/.claude/bitacora  # already exists if the statusLine is installed
src_file="$(find ~/.claude/plugins -path '*bitacora/scripts/precompact-handoff-check.sh' | head -1)"
if [ -z "$src_file" ]; then
  echo "bitacora hook not found — is the plugin installed?" >&2
else
  cp "$src_file" ~/.claude/bitacora/
  chmod +x ~/.claude/bitacora/precompact-handoff-check.sh
fi
```

Then add this to `~/.claude/settings.json` (merge with any existing `hooks` block):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/bitacora/precompact-handoff-check.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

After opt-in, the same `SessionStart` hook that syncs the statusLine scripts also
keeps `precompact-handoff-check.sh` in sync at `~/.claude/bitacora/` — no need to
re-run the snippet on plugin updates.

**Bypassing the check:**

- **One attempt:** `touch .bitacora/skip-handoff-once` and re-issue `/clear`. The
  marker is consumed on use; the next `/clear` with pending work fires the check
  again.
- **Permanent:** remove the `UserPromptSubmit` entry from `~/.claude/settings.json`.

**Caveats**

- **Plugin-side activation also exists.** Installing the plugin via Claude Code's
  plugin system activates the hook automatically via `hooks/hooks.json`. The
  manual `settings.json` route above is for users who want to install just the
  hook (without the rest of the plugin) or who want per-machine control.
- **The hook does not catch auto-compact.** Auto-compact preserves context
  (it summarises), so handoff is not actually at risk. Manual `/compact` is
  caught by the same `/clear` matcher.
- **`jq` is required.** If `jq` isn't on PATH the hook fails open (silent), so
  `/clear` proceeds and the handoff is lost. Same dependency as the statusLine.

## The `[CTX]` format

See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](../../docs/JIRA_AGENT_COMMENT_FORMAT.md). The
operational source of truth is the `jira-comment-format` skill; `scripts/validate-ctx.sh`
classifies any comment as `compliant` / `malformed` / `not-in-format`.
````

### Step 2: Sanity-check the README change

- [ ] Run:

```bash
grep -n "handoff guardrail\|precompact-handoff-check\|UserPromptSubmit" plugins/bitacora/README.md
```

Expected: at least 6 matches across the new subsection (heading + several body references). The new subsection sits between the existing "Optional: the statusLine" section and "The `[CTX]` format" heading.

### Step 3: Commit

- [ ] Stage and commit:

```bash
git add plugins/bitacora/README.md
git commit -m "docs(hook): add 'Optional: the handoff guardrail hook' subsection to plugin README"
```

---

## Task 5: Wire the new test script into CI

The existing `shell-tests` matrix job in `.github/workflows/test.yml` runs each test script as a separate step. Add one new step for `test-precompact-handoff-check.sh`.

**Files:**
- Modify: `.github/workflows/test.yml`

### Step 1: Add the new step inside the `shell-tests` job

- [ ] **Edit** `.github/workflows/test.yml`. Use the `Edit` tool with:

`old_string`:

````
      - name: Run statusline tests
        run: bash plugins/bitacora/scripts/test-statusline.sh
      - name: Run statusline sync tests
        run: bash plugins/bitacora/scripts/test-sync-statusline.sh
````

`new_string`:

````
      - name: Run statusline tests
        run: bash plugins/bitacora/scripts/test-statusline.sh
      - name: Run statusline sync tests
        run: bash plugins/bitacora/scripts/test-sync-statusline.sh
      - name: Run handoff guardrail hook tests
        run: bash plugins/bitacora/scripts/test-precompact-handoff-check.sh
````

### Step 2: Validate the workflow YAML

- [ ] Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"
echo "exit=$?"
```

Expected: no output and `exit=0`.

### Step 3: Commit

- [ ] Stage and commit:

```bash
git add .github/workflows/test.yml
git commit -m "ci(hook): run handoff guardrail tests in the shell-tests matrix"
```

---

## Task 6: Final verification + push + open PR

**Files:** none modified — verification only.

### Step 1: Run all test suites

- [ ] Run:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
plugins/bitacora/scripts/test-statusline.sh
plugins/bitacora/scripts/test-sync-statusline.sh
plugins/bitacora/scripts/test-precompact-handoff-check.sh
```

Expected: every line `PASS`; every script exits 0.

### Step 2: Run ShellCheck against all bash scripts (matches the CI `lint` job)

- [ ] Run:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --severity=warning \
  plugins/bitacora/scripts/*.sh \
  plugins/bitacora/statusline/*.sh
echo "exit=$?"
```

Expected: `exit=0` and no findings.

### Step 3: Confirm the help block invariant

- [ ] No help.md edits in this PR, but verify the invariant anyway:

```bash
diff \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md)
```

Expected: no output.

### Step 4: Review the diff against main

- [ ] Inspect the branch's commits and the per-file diff:

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Expected: 6 commits (spec + 5 implementation commits) on `feat/handoff-guardrail-hook`, touching only:

- `docs/superpowers/specs/2026-05-29-handoff-guardrail-hook-design.md`
- `docs/superpowers/plans/2026-05-29-handoff-guardrail-hook.md`
- `plugins/bitacora/scripts/precompact-handoff-check.sh` *(new)*
- `plugins/bitacora/scripts/test-precompact-handoff-check.sh` *(new)*
- `plugins/bitacora/scripts/sync-statusline.sh`
- `plugins/bitacora/scripts/test-sync-statusline.sh`
- `plugins/bitacora/hooks/hooks.json`
- `plugins/bitacora/README.md`
- `.github/workflows/test.yml`

### Step 5: Push the branch

- [ ] Push with upstream tracking:

```bash
git push -u origin feat/handoff-guardrail-hook
```

### Step 6: Open the PR

- [ ] Open the PR with `skip-issue-check` + `enhancement` labels:

```bash
gh pr create --title "feat: handoff guardrail hook (UserPromptSubmit on /clear and /compact)" \
             --label "skip-issue-check,enhancement" \
             --body "$(cat <<'EOF'
## Summary

Implements the handoff guardrail per docs/superpowers/specs/2026-05-29-handoff-guardrail-hook-design.md. A new UserPromptSubmit hook intercepts /clear and /compact when Bitácora detects pending handoff work, prints an action-oriented message suggesting /bitacora:handoff, and exposes a one-shot escape via a .bitacora/skip-handoff-once marker file.

## Mechanics in one paragraph

precompact-handoff-check.sh reads JSON from stdin, matches /clear or /compact via a strict prefix regex, sources the existing handoff-pending.sh decision function (reused as-is from the statusLine), gathers the same four signals the statusLine gathers, and on a pending-handoff truth emits a JSON block with decision: "block" and a multiline message naming the ticket + commits + dirty-tree status. Fail-open on every error path (missing jq, missing source file, malformed input, git not in PATH, timeout). Filename keeps the "PreCompact" friction title for searchability; spec body documents the event-name mismatch.

## What this PR does NOT do

- No PreCompact subscription (auto-compact preserves context, handoff not at risk)
- No Stop subscription (fires too broadly in some Claude Code variants)
- No SessionStart "regret note" (statusLine already covers post-clear pending awareness)
- No auto-run of /bitacora:handoff (paternalistic; breaks draft → confirm → write)
- No env-var silencer or customizable block message in v1

## Install paths

Two paths, intentionally:
1. **In-plugin (default):** activating the plugin via Claude Code's plugin system wires the UserPromptSubmit hook automatically via hooks.json. No user action needed.
2. **Manual (escape route):** copy the script into ~/.claude/bitacora/ and add a UserPromptSubmit entry to ~/.claude/settings.json. For users who want to install just the hook, or who want per-machine control over the hook independent of the rest of the plugin.

Plugin README's new "Optional: the handoff guardrail hook" subsection covers both paths.

## Why skip-issue-check

No tracked issue; review-driven feature. Precedent: every recent maintainer-chore PR (#40, #42–#55).

## Test plan

- [x] New test-precompact-handoff-check.sh covers 12 cases: non-matching prompt, /clear on clean and pending repos (dirty, commits-since-marker), non-ticket branch, outside repo, marker consumption, /compact, /clear-foo non-match, leading whitespace, malformed JSON, empty stdin.
- [x] ShellCheck (--severity=warning) clean across all bash scripts including the new one.
- [x] All four existing test suites still pass.
- [x] sync-statusline.sh now also syncs the hook script; assertion added to test-sync-statusline.sh.
- [x] CI workflow includes the new test step on both ubuntu-latest and macos-latest.
- [ ] Live acceptance per spec: opt in on a real machine, type /clear on a ticket branch with pending work, confirm the block message appears and naming is correct.
EOF
)"
```

### Step 7: Wait for CI

- [ ] Poll until all checks complete:

```bash
until gh pr view <PR#> --json statusCheckRollup --jq '[.statusCheckRollup[] | select(.status != "COMPLETED")] | length == 0' | grep -q true; do sleep 15; done
gh pr view <PR#> --json mergeable,mergeStateStatus,statusCheckRollup --jq '{mergeable, mergeStateStatus, checks: [.statusCheckRollup[] | {name, conclusion}]}'
```

Expected: six green checks (`gate` ×3, `lint`, `shell-tests (ubuntu-latest)`, `shell-tests (macos-latest)`); `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`.

Stop here and report to the user. **Do not auto-merge** — the user confirms each merge explicitly this session.

---

## Notes for the implementer

- **Branch is already created** — `feat/handoff-guardrail-hook`. Spec is committed at `6709828`.
- **Filename `precompact-handoff-check.sh` is deliberate.** The original friction was titled "PreCompact handoff hook"; preserving the filename helps users / docs find the script. The actual Claude Code event is `UserPromptSubmit`; the spec body documents the mismatch. Do **not** rename to `userpromptsubmit-handoff-check.sh`.
- **`handoff-pending.sh` is reused as-is from `plugins/bitacora/statusline/`.** Do not duplicate it. The test harness copies both files into one temp dir so the hook's `$DIR/handoff-pending.sh` resolution works in the test.
- **Fail-open everywhere.** Every error path in the hook exits 0 silently. The hook is a guardrail, not a kernel lock. Don't add error-surfacing or non-zero exits.
- **No new MCP permissions, no new config keys.** Reuses `project_key_pattern` (inline regex `[A-Z][A-Z0-9]+-[0-9]+`); reuses the `.bitacora/last-handoff` marker the handoff command writes.
- **No Co-Authored-By trailer in any commit** (project convention).
- **ShellCheck `--severity=warning`** is the bar; info-level (SC2015, SC1091) is intentionally ignored per the existing CI config.
- **`jq` is a soft dependency** — required for the hook to function but the hook itself fails open if `jq` is absent. The statusLine already requires `jq`, so this is not a new dependency for plugin users.
- **No PLUGIN_BRIEF.md or root README updates** — this is opt-in plugin infrastructure; the plugin README is the right surface.
