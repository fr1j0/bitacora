# Tracker Backends (GitHub-first) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Bitácora target GitHub Issues as the tracker backend (Jira stays the default), selected per-repo, with `[CTX]` comments written/read on GitHub issues.

**Architecture:** A `resolve-tracker.sh` script picks `github | gitlab | jira` (explicit `tracker:` in config wins, else inferred from the git remote host). Skills branch once on tracker *family* — `mcp` (today's Jira code, untouched) vs `cli`. The `cli` path calls a uniform, tested `bitacora-tracker.sh` adapter wrapping `gh` (and later `glab`). A `tracker-adapter` SKILL documents per-backend semantic gaps; the `[CTX]` logical format is unchanged with a per-family render note.

**Tech Stack:** Bash, `gh` CLI, `jq`, awk (YAML micro-walk, matching `resolve-project-scope.sh`), Markdown SKILL docs.

**Scope:** This plan is **PR-1 = GitHub only**. The GitLab column (`glab`) is a separate follow-up plan; the seam (family branch, adapter dispatch, capability table) is built for it here but `glab` verbs return a "not yet implemented" stub.

## Global Constraints

- Match `resolve-project-scope.sh` conventions exactly: `--dir`/`--repo-config`/`--home-config` flags, `$CLAUDE_PROJECT_DIR` default, awk YAML micro-walk (not a general parser), reuse its remote-slug normalization verbatim.
- Match the test harness in `test-resolve-project-scope.sh`: `set -uo pipefail`, mktemp throwaway repos via `git init -q`, `check`/`check_err_contains` helpers, `PASS:`/`FAIL:` lines, `fail=1` on mismatch, `trap 'rm -rf "$TMP"' EXIT`.
- All new scripts live in `plugins/bitacora/scripts/` with a paired `test-<name>.sh`.
- Backend CLIs are a hard dependency surfaced through a `doctor` precondition — never let a raw `gh`/`jq` error reach the user.
- The literal `[CTX]` marker is retained on every backend (it is the corpus selector). `validate-ctx.sh` is **not** modified.
- Never add AI attribution to commits.
- Do not touch the `mcp` (Jira) code paths except to add the one-time family branch in front of them.

---

### Task 1: `resolve-tracker.sh` — tracker resolution

**Files:**
- Create: `plugins/bitacora/scripts/resolve-tracker.sh`
- Test: `plugins/bitacora/scripts/test-resolve-tracker.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `resolve-tracker.sh [--dir <d>] [--repo-config <p>] [--home-config <p>]` → stdout one of `github|gitlab|jira` (exit 0); exit 2 usage/invalid-value; exit 4 not-a-repo/no-remote *and* no explicit `tracker:`.

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-resolve-tracker.sh`:

```bash
#!/usr/bin/env bash
# Deterministic tests for resolve-tracker.sh. Throwaway git repos + config files
# under mktemp; no real remotes or ~/.claude config involved.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
RT="$DIR/resolve-tracker.sh"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkrepo() {  # name [remote-url] → prints repo path; no remote when url omitted
  local path="$TMP/$1"
  git init -q "$path"
  [[ -n "${2:-}" ]] && git -C "$path" remote add origin "$2"
  printf '%s' "$path"
}

GH_REPO="$(mkrepo gh-repo https://github.com/org/vatios.git)"
GL_REPO="$(mkrepo gl-repo git@gitlab.com:org/thing.git)"
JIRA_REPO="$(mkrepo jira-repo git@bitbucket.example.com:org/thing.git)"
NOREMOTE="$(mkrepo no-remote)"

# Config with an explicit tracker: override.
OVERRIDE_CFG="$TMP/override.yml"
cat > "$OVERRIDE_CFG" <<'EOF'
tracker: jira   # explicit override beats remote inference
next:
  stale_days: 30
EOF

# Config selecting gitlab explicitly (for a self-managed host that won't infer).
GL_CFG="$TMP/gl.yml"
echo 'tracker: "gitlab"' > "$GL_CFG"

MISSING="$TMP/none.yml"

check() {  # desc expected-stdout expected-code args...
  local desc="$1" expected="$2" want_code="$3"; shift 3
  local out code
  out="$(bash "$RT" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == "$want_code" ]]; then
    echo "PASS: $desc → '$out' ($code)"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' ($want_code)"; fail=1
  fi
}

check "github inferred from remote" github 0 \
  --dir "$GH_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check "gitlab inferred from remote" gitlab 0 \
  --dir "$GL_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check "unknown host infers jira" jira 0 \
  --dir "$JIRA_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check "explicit tracker beats inference" jira 0 \
  --dir "$GH_REPO" --repo-config "$OVERRIDE_CFG" --home-config "$MISSING"
check "explicit gitlab for self-managed (no remote)" gitlab 0 \
  --dir "$NOREMOTE" --repo-config "$GL_CFG" --home-config "$MISSING"
check "no remote and no explicit tracker → exit 4" "" 4 \
  --dir "$NOREMOTE" --repo-config "$MISSING" --home-config "$MISSING"
check "unknown arg → exit 2" "" 2 --bogus

if (( fail )); then echo "SOME TESTS FAILED"; exit 1; else echo "ALL TESTS PASSED"; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-resolve-tracker.sh`
Expected: FAIL lines (script does not exist yet — `bash: .../resolve-tracker.sh: No such file or directory`), ending `SOME TESTS FAILED`.

- [ ] **Step 3: Write the implementation**

Create `plugins/bitacora/scripts/resolve-tracker.sh`:

```bash
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
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run: `chmod +x plugins/bitacora/scripts/resolve-tracker.sh && bash plugins/bitacora/scripts/test-resolve-tracker.sh`
Expected: all `PASS:` lines, ending `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/scripts/resolve-tracker.sh plugins/bitacora/scripts/test-resolve-tracker.sh
git commit -m "feat(tracker): resolve-tracker.sh — infer/override github|gitlab|jira (#117)"
```

---

### Task 2: `bitacora-tracker.sh` — GitHub CLI adapter

**Files:**
- Create: `plugins/bitacora/scripts/bitacora-tracker.sh`
- Test: `plugins/bitacora/scripts/test-bitacora-tracker.sh`

**Interfaces:**
- Consumes: `$TRACKER` env (`github` for this PR; `gitlab` stubbed).
- Produces: `TRACKER=github bitacora-tracker.sh <verb> [args]`:
  - `doctor` → exit 0 if `gh`+`jq` installed & `gh` authed, else exit 5 with guidance.
  - `whoami` → login on stdout.
  - `list-mine` → JSON array of open issues assigned to the caller (`gh issue list --json number,title,labels,updatedAt,milestone`).
  - `view <id>` → JSON object for one issue (`number,title,body,labels,state,milestone,comments`).
  - `comments <id>` → normalized JSON array `[{author, createdAt, body}]`.
  - `comment <id> --body-file <f>` → posts a comment.
  - `edit-body <id> --body-file <f>` → replaces the issue body.
  - Unknown verb / missing args → exit 2. `gitlab` verbs → exit 3 (not yet implemented).

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-bitacora-tracker.sh`:

```bash
#!/usr/bin/env bash
# Tests for bitacora-tracker.sh github dispatch + JSON normalization, using a
# PATH-shimmed fake `gh` so nothing hits the network or real auth. Real `jq`
# runs, so comment normalization is exercised for real.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BT="$DIR/bitacora-tracker.sh"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Fake gh: appends argv to $GH_ARGS, emits canned output per subcommand.
cat > "$TMP/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_ARGS"
case "$1 $2" in
  "issue list")    echo '[{"number":7,"title":"x","labels":[],"updatedAt":"2026-06-23T00:00:00Z","milestone":null}]' ;;
  "issue view")
    if [[ "$*" == *"--json comments"* ]]; then
      echo '{"comments":[{"author":{"login":"fr1j0"},"createdAt":"2026-06-23T00:00:00Z","body":"[CTX] Status update"}]}'
    else
      echo '{"number":7,"title":"x","body":"b","labels":[],"state":"OPEN","milestone":null,"comments":[]}'
    fi ;;
  "issue comment") echo "https://github.com/org/repo/issues/7#issuecomment-1" ;;
  "issue edit")    echo "https://github.com/org/repo/issues/7" ;;
  "api user")      echo "fr1j0" ;;
  "auth status")   exit 0 ;;
  *) echo "fake gh: unhandled: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$TMP/gh"
export PATH="$TMP:$PATH"
export GH_ARGS="$TMP/gh-args"

run() { TRACKER="${TRK:-github}" bash "$BT" "$@" 2>"$TMP/err"; }

# whoami
out="$(run whoami)"; code=$?
[[ "$out" == "fr1j0" && $code -eq 0 ]] && echo "PASS: whoami" || { echo "FAIL: whoami → '$out' ($code)"; fail=1; }

# list-mine passes --assignee @me and returns the array
out="$(run list-mine)"; code=$?
{ [[ $code -eq 0 ]] && echo "$out" | grep -q '"number":7' \
  && grep -q -- "--assignee @me" "$GH_ARGS"; } \
  && echo "PASS: list-mine" || { echo "FAIL: list-mine → '$out' ($code)"; fail=1; }

# comments are normalized to [{author,createdAt,body}] (author flattened from .login)
out="$(run comments 7)"; code=$?
{ [[ $code -eq 0 ]] && echo "$out" | jq -e '.[0].author == "fr1j0" and (.[0].body | startswith("[CTX]"))' >/dev/null; } \
  && echo "PASS: comments normalized" || { echo "FAIL: comments → '$out' ($code)"; fail=1; }

# comment requires --body-file
BODY="$TMP/body.md"; echo "[CTX] Status update" > "$BODY"
out="$(run comment 7 --body-file "$BODY")"; code=$?
{ [[ $code -eq 0 ]] && grep -q -- "issue comment 7 --body-file" "$GH_ARGS"; } \
  && echo "PASS: comment" || { echo "FAIL: comment → '$out' ($code)"; fail=1; }
run comment 7 >/dev/null 2>&1; [[ $? -eq 2 ]] && echo "PASS: comment missing --body-file → 2" || { echo "FAIL: comment arg-guard"; fail=1; }

# edit-body
out="$(run edit-body 7 --body-file "$BODY")"; code=$?
{ [[ $code -eq 0 ]] && grep -q -- "issue edit 7 --body-file" "$GH_ARGS"; } \
  && echo "PASS: edit-body" || { echo "FAIL: edit-body → '$out' ($code)"; fail=1; }

# doctor passes when gh+jq present and authed
run doctor >/dev/null 2>&1; [[ $? -eq 0 ]] && echo "PASS: doctor ok" || { echo "FAIL: doctor ok"; fail=1; }

# unknown verb → 2
run frobnicate >/dev/null 2>&1; [[ $? -eq 2 ]] && echo "PASS: unknown verb → 2" || { echo "FAIL: unknown verb"; fail=1; }

# gitlab backend stub → 3
TRK=gitlab run list-mine >/dev/null 2>&1; [[ $? -eq 3 ]] && echo "PASS: gitlab stub → 3" || { echo "FAIL: gitlab stub"; fail=1; }

if (( fail )); then echo "SOME TESTS FAILED"; exit 1; else echo "ALL TESTS PASSED"; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-bitacora-tracker.sh`
Expected: FAIL lines (script missing), ending `SOME TESTS FAILED`.

- [ ] **Step 3: Write the implementation**

Create `plugins/bitacora/scripts/bitacora-tracker.sh`:

```bash
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
      [[ "${1:-}" == "--body-file" && -n "${2:-}" ]] || die "comment needs <id> --body-file <f>"
      gh issue comment "$id" --body-file "$2" ;;
    edit-body)
      local id="${1:-}"; shift || true
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
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run: `chmod +x plugins/bitacora/scripts/bitacora-tracker.sh && bash plugins/bitacora/scripts/test-bitacora-tracker.sh`
Expected: all `PASS:` lines, ending `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/scripts/bitacora-tracker.sh plugins/bitacora/scripts/test-bitacora-tracker.sh
git commit -m "feat(tracker): bitacora-tracker.sh github adapter with normalized verbs (#117)"
```

---

### Task 3: `tracker-adapter` SKILL + `[CTX]` render note

**Files:**
- Create: `plugins/bitacora/skills/tracker-adapter/SKILL.md`
- Modify: `plugins/bitacora/skills/jira-comment-format/SKILL.md` (add a render-by-family note)

**Interfaces:**
- Consumes: `resolve-tracker.sh`, `bitacora-tracker.sh` (Task 1–2).
- Produces: the canonical capability table + verb reference every skill task below points to, and the GFM render note `handoff`/`improve` rely on.

- [ ] **Step 1: Write the `tracker-adapter` SKILL**

Create `plugins/bitacora/skills/tracker-adapter/SKILL.md`:

```markdown
---
name: tracker-adapter
description: How Bitácora selects and talks to a tracker backend (jira | github | gitlab). Use whenever a skill must read or write issues/comments — to resolve the active backend, pick the right verb, and reason about per-backend capability gaps.
allowed-tools: Read, Bash
---

This skill is the single source of truth for **tracker selection and the backend
verb layer**. The `[CTX]` comment format itself lives in `jira-comment-format`;
this skill says *which backend* a skill talks to and *how*.

## Resolve the active backend (every skill, first)

Run `resolve-tracker.sh` (in `plugins/bitacora/scripts/`):

    bash "$SCRIPTS/resolve-tracker.sh"   # → github | gitlab | jira

- exit 0: stdout is the backend.
- exit 4: not a git repo / no remote and no explicit `tracker:` — tell the user to
  set `tracker:` in `.bitacora.yml`, do not guess.

Branch once on **family**:

- `jira` → **mcp family**: use the Atlassian MCP exactly as today (unchanged).
- `github` / `gitlab` → **cli family**: use `bitacora-tracker.sh` (below). Run
  `bitacora-tracker.sh doctor` first; on exit 5 surface the auth/install guidance
  and stop.

## CLI verb reference (`bitacora-tracker.sh`)

Set `TRACKER` from the resolved backend; all verbs emit normalized JSON.

| Need | Verb |
|---|---|
| issues assigned to me (for `next`) | `list-mine` |
| one issue | `view <id>` |
| the `[CTX]` corpus | `comments <id>` → `[{author,createdAt,body}]` |
| write a `[CTX]` / `[ARCHIVE]` comment | `comment <id> --body-file <f>` |
| rewrite the issue body (`improve`) | `edit-body <id> --body-file <f>` |
| current user | `whoami` |

Read the comment **date from `createdAt`**, never from the body (same rule as Jira).

## Capability table (semantic gaps the verbs can't hide)

| Capability | jira | github | gitlab |
|---|---|---|---|
| family | mcp | cli | cli |
| corpus = comments | ✓ | ✓ | ✓ |
| single editable body | description (ADF) | body (md) | description (md) |
| native issue types | ✓ | types (beta) / labels | labels |
| epic / rollup basis | epic→child link | sub-issues, else milestone | native epics |
| renderer autolinks bare URLs | ✗ (ADF) | ✓ (GFM) | ✓ (GFM) |
| identity token | accountId | `@me` / login | `@me` / username |
| scope unit | project key (map) | current repo | current project |

Implications skills must honor:
- **Scope:** on the cli family the scope *is* the current repo — do not consult the
  Jira `remote_project_map`; `list-mine` is already repo-scoped.
- **Issue type:** on the cli family derive type from labels (or native issue type if
  present); fall back to a generic rewrite rather than refusing.
- **Epic rollup:** see `bitacora:session-digest` — degrade and label the basis.

## Render: see `jira-comment-format`

The `[CTX]` logical format is identical on every backend. Only the *render* differs
by family (URL wrapping, code marks); `jira-comment-format` documents both. Always
keep the literal `[CTX]` marker — it is the corpus selector.
```

- [ ] **Step 2: Add the render-by-family note to `jira-comment-format`**

In `plugins/bitacora/skills/jira-comment-format/SKILL.md`, immediately **after** the
"URLs must be wrapped, never bare" bullet under **Write rules (hard)**, add:

```markdown

- **Render differs by tracker family (see `tracker-adapter`).** The wrapping rule
  above is for the **mcp/Jira** family — Jira's ADF renderer does *not* autolink, so
  every URL must be wrapped and identifiers need backticks (ADF code marks). On the
  **cli family (GitHub/GitLab)** comments are GitHub-flavored markdown: bare URLs
  autolink, so wrapping is *optional* (compact `[#123](url)` references are still
  preferred for readability) and backticks render as GFM code spans. The GFM render
  only *relaxes* the Jira rules — it never adds new ones. The logical sections and the
  literal `[CTX]` marker are identical across families.
```

- [ ] **Step 3: Verify the SKILL is internally consistent**

Run: `grep -c "cli family" plugins/bitacora/skills/tracker-adapter/SKILL.md plugins/bitacora/skills/jira-comment-format/SKILL.md`
Expected: both files report a non-zero count (the render note and the verb reference both reference the cli family), confirming the cross-reference is in place.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/tracker-adapter/SKILL.md plugins/bitacora/skills/jira-comment-format/SKILL.md
git commit -m "docs(tracker): tracker-adapter SKILL + per-family [CTX] render note (#117)"
```

---

### Task 4: `tracker:` config field + help + README

**Files:**
- Modify: `plugins/bitacora/commands/help.md`
- Modify: `plugins/bitacora/README.md`

**Interfaces:**
- Consumes: the backends from Task 1.
- Produces: user-facing documentation of `tracker:` and the `gh` prerequisite. No code.

- [ ] **Step 1: Document the `tracker:` field + prerequisite in help**

In `plugins/bitacora/commands/help.md`, add a short "Tracker backend" subsection stating:

```markdown
## Tracker backend

Bitácora targets **Jira** by default. In a repo whose tracker is **GitHub Issues**,
set the backend (or let it infer from the git remote):

```yaml
# .bitacora.yml (repo) or ~/.claude/bitacora.yml (home)
tracker: github   # jira | github | gitlab — omit to infer from the git remote host
```

GitHub/GitLab backends require the `gh`/`glab` CLI installed and authenticated
(`gh auth login`). All skills read and write `[CTX]` comments on the selected
tracker's issues exactly as they do on Jira.
```

- [ ] **Step 2: Mirror the note in the README**

In `plugins/bitacora/README.md`, add the same `tracker:` snippet under the configuration section (match the surrounding heading style; keep it to the yaml block + one sentence).

- [ ] **Step 3: Verify**

Run: `grep -rl "tracker: github" plugins/bitacora/commands/help.md plugins/bitacora/README.md`
Expected: both paths listed.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/commands/help.md plugins/bitacora/README.md
git commit -m "docs(tracker): document tracker: config field + gh prerequisite (#117)"
```

---

### Tasks 5–9: route each skill through the family branch

Tasks 5–9 share one mechanical shape and one verification method, so they are
described once here and then listed per skill. **Each is its own task and its own
commit.**

**Shared edit (per skill SKILL.md):** add a `## Resolve the tracker (first)` step at
the top of the procedure that calls `resolve-tracker.sh` and branches on family,
pointing the reader to `tracker-adapter`. Then, at each point the current procedure
calls the Atlassian MCP, add the **cli-family** alternative using the matching
`bitacora-tracker.sh` verb. Leave the existing mcp/Jira prose untouched as the
`jira` branch.

**Shared verification (manual acceptance, cli family):** these are prose-routing
changes with no bash unit test. Verify against a real GitHub repo (`vatios`, or a
throwaway repo with one issue) by adding a row to
`docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` and running it in a live session.
Each task's "test" step is the specific acceptance below.

---

### Task 5: `next` — cli family

**Files:**
- Modify: `plugins/bitacora/skills/session-next/SKILL.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

**Interfaces:**
- Consumes: `resolve-tracker.sh`, `bitacora-tracker.sh list-mine`.
- Produces: a repo-scoped `next` on the cli family.

- [ ] **Step 1: Add the family branch + cli read path**

In `session-next/SKILL.md`: add the `## Resolve the tracker (first)` step. In the
`github`/`gitlab` branch, replace the "resolve the Jira project / run JQL" step with:

```markdown
On the **cli family**, the scope *is* the current repo — do not run
`resolve-project-scope.sh`. Fetch candidates with:

    bash "$SCRIPTS/bitacora-tracker.sh" list-mine    # TRACKER from resolve-tracker

Rank/categorize the returned issues with the same pickup-cost / readiness logic as
the Jira path (labels stand in for status; `updatedAt` for staleness).
```

Keep the existing Jira JQL path as the `jira` branch.

- [ ] **Step 2: Add the acceptance row**

Append to `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`:

```markdown
- [ ] **next (github):** in a GitHub-Issues repo with ≥1 issue assigned to you, run
  `/bit:next`. Expect a categorized shortlist of *this repo's* issues — never a Jira
  project's tickets, never an unscoped query.
```

- [ ] **Step 3: Run the acceptance check**

In a live session inside a GitHub repo (e.g. `vatios`) with an issue assigned to you, run `/bit:next`.
Expected: shortlist drawn from `gh issue list --assignee @me` for the current repo; no Jira call.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-next/SKILL.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "feat(next): cli-family (GitHub) read path, repo-scoped (#117)"
```

---

### Task 6: `resume` + `status` — cli family (read pair)

**Files:**
- Modify: `plugins/bitacora/skills/session-resume/SKILL.md`
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

**Interfaces:**
- Consumes: `bitacora-tracker.sh comments <id>` → `[{author,createdAt,body}]`.
- Produces: `[CTX]` corpus reads on the cli family. Output/synthesis logic unchanged.

- [ ] **Step 1: Add the family branch + cli read path to both skills**

In each of `session-resume/SKILL.md` and `session-status/SKILL.md`: add the
`## Resolve the tracker (first)` step. In the cli branch, replace "fetch the issue's
Jira comments via MCP" with:

```markdown
On the **cli family**, fetch the corpus with:

    bash "$SCRIPTS/bitacora-tracker.sh" comments <id>   # → [{author,createdAt,body}]

Grep bodies for the `[CTX]` marker exactly as on Jira; take the comment date from
`createdAt`. Synthesis across the five lenses is unchanged.
```

- [ ] **Step 2: Add acceptance rows**

Append to `MANUAL-ACCEPTANCE.md`:

```markdown
- [ ] **resume (github):** on an issue carrying a `[CTX]` comment, `/bit:resume <n>`
  rehydrates Status/Decisions/Next from that comment.
- [ ] **status (github):** `/bit:status <n>` synthesizes the latest `[CTX]` in the
  selected lens; no Jira call is made.
```

- [ ] **Step 3: Run the acceptance check**

Seed an issue: `gh issue comment <n> --body-file` with a compliant `[CTX]` block. Run `/bit:resume <n>` and `/bit:status <n>`.
Expected: both read the `[CTX]` back and synthesize; date comes from comment metadata.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-resume/SKILL.md plugins/bitacora/skills/session-status/SKILL.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "feat(resume,status): cli-family (GitHub) [CTX] corpus reads (#117)"
```

---

### Task 7: `handoff` — cli family (write)

**Files:**
- Modify: `plugins/bitacora/skills/session-handoff/SKILL.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

**Interfaces:**
- Consumes: `bitacora-tracker.sh comments <id>` (collision/staleness read) and `comment <id> --body-file <f>` (write); GFM render note from `jira-comment-format`.
- Produces: `[CTX]` comments written to GitHub issues.

- [ ] **Step 1: Add the family branch + cli write path**

In `session-handoff/SKILL.md`: add the `## Resolve the tracker (first)` step. In the
cli branch:

```markdown
On the **cli family**, draft the `[CTX]` using the **GFM render** (bare URLs allowed;
see `jira-comment-format`). The collision/staleness pre-checks read the corpus via
`bitacora-tracker.sh comments <id>`. After confirmation, write each comment by piping
the drafted body to a temp file and:

    bash "$SCRIPTS/bitacora-tracker.sh" comment <id> --body-file "$TMP/ctx-<id>.md"

The local Remember scratch save is unchanged.
```

- [ ] **Step 2: Add the acceptance row**

```markdown
- [ ] **handoff (github):** after a session touching a GitHub issue, `/bit:handoff`
  drafts a `[CTX]`, confirms, then posts it as an issue comment (verify with
  `gh issue view <n> --json comments`). A bare URL renders as a link.
```

- [ ] **Step 3: Run the acceptance check**

Run `/bit:handoff` in a session that touched a GitHub issue; confirm the write.
Expected: `gh issue view <n>` shows the new `[CTX]` comment; round-trips with Task 6's `/bit:resume`.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-handoff/SKILL.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "feat(handoff): cli-family (GitHub) [CTX] comment writes (#117)"
```

---

### Task 8: `improve` — cli family (body rewrite)

**Files:**
- Modify: `plugins/bitacora/skills/session-improve/SKILL.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

**Interfaces:**
- Consumes: `bitacora-tracker.sh view <id>` (read body+labels), `comment` (`[ARCHIVE]` snapshot), `edit-body` (rewrite).
- Produces: in-place GitHub issue-body rewrite with a snapshot comment.

- [ ] **Step 1: Add the family branch + cli rewrite path**

In `session-improve/SKILL.md`: add the `## Resolve the tracker (first)` step. In the
cli branch:

```markdown
On the **cli family** the issue has a single markdown **body** (no ADF). Read it with
`bitacora-tracker.sh view <id>`; derive issue *type* from labels (or native issue
type), falling back to a generic structured rewrite. On accept:

1. Snapshot the current body to an `[ARCHIVE]` comment:
   `bitacora-tracker.sh comment <id> --body-file "$TMP/archive-<id>.md"`
2. Replace the body:
   `bitacora-tracker.sh edit-body <id> --body-file "$TMP/rewrite-<id>.md"`

Use the GFM render (no ADF wrapping). Title edits, if any, stay a separate
confirmed step (`gh issue edit <id> --title`).
```

- [ ] **Step 2: Add the acceptance row**

```markdown
- [ ] **improve (github):** `/bit:improve <n>` snapshots the old body to an
  `[ARCHIVE]` comment, then rewrites the issue body in place (verify both with
  `gh issue view <n>`). Type is inferred from labels.
```

- [ ] **Step 3: Run the acceptance check**

Run `/bit:improve <n>` on a GitHub issue.
Expected: an `[ARCHIVE]` comment appears and the body is the structured rewrite; the pre-state is recoverable from the archive comment.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-improve/SKILL.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "feat(improve): cli-family (GitHub) body rewrite + [ARCHIVE] snapshot (#117)"
```

---

### Task 9: `digest` — cli family + graceful epic rollup

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/SKILL.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

**Interfaces:**
- Consumes: `bitacora-tracker.sh list-mine` / `view` / `comments`.
- Produces: multi-issue digest on the cli family; honestly-labeled rollup basis.

- [ ] **Step 1: Add the family branch + cli multi-read + rollup degradation**

In `session-digest/SKILL.md`: add the `## Resolve the tracker (first)` step. In the
cli branch:

```markdown
On the **cli family**, gather the issue set with `list-mine` (or the explicit keys
the user passed) and read each via `comments <id>`; cross-ticket synthesis is
unchanged.

**Epic rollup degrades by backend (label the basis in the output):**
- GitHub: if the issue has **sub-issues**, roll up over them; else fall back to the
  **milestone** as the grouping. State which basis was used, e.g.
  *"Rollup basis: milestone `v0.8` (no sub-issues found)."*
- GitLab: use the native epic (PR-2).

Never imply Jira-epic parity — name the basis so the reader knows the rollup's shape.
```

- [ ] **Step 2: Add the acceptance row**

```markdown
- [ ] **digest (github):** `/bit:digest` over ≥2 GitHub issues produces a cross-issue
  digest; an epic-style rollup names its basis (sub-issues or milestone) and does not
  claim Jira-epic semantics.
```

- [ ] **Step 3: Run the acceptance check**

Run `/bit:digest` over two GitHub issues (and once over a milestone-grouped set).
Expected: cross-issue digest renders; the rollup output explicitly names sub-issues vs milestone as the basis.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-digest/SKILL.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "feat(digest): cli-family (GitHub) reads + graceful epic rollup (#117)"
```

---

## Final verification (whole-plan)

- [ ] **Run the full script test suite**

Run: `for t in plugins/bitacora/scripts/test-*.sh; do echo "== $t"; bash "$t" || exit 1; done`
Expected: every harness ends `ALL TESTS PASSED` (the two new ones plus the unchanged existing suites).

- [ ] **Walk the GitHub manual-acceptance rows** added in Tasks 5–9 against `vatios` (or a throwaway repo), confirming a full `handoff → resume` round-trip and an `improve` body rewrite.

- [ ] **Confirm the Jira path is untouched:** spot-check one Jira repo with `/bit:status` to verify the `mcp` branch still behaves exactly as before.
