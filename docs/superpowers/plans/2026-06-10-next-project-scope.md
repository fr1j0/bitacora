# /next Project Scoping (issue #118) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope `/bitacora:next`'s default JQL to the current repo's Jira project — auto-detected from the git remote via a `next.remote_project_map` config table — and hard-stop (never an unscoped site-wide dump) when the repo has no mapping.

**Architecture:** A new pure-ish helper `scripts/resolve-project-scope.sh` reads the repo's git remote, normalizes it to a lowercase `host/owner/repo` slug, and looks the slug up in `next.remote_project_map` (repo-level `.bitacora.yml` entry overrides the `~/.claude/bitacora.yml` one, per slug). The `session-next` skill gains an early step that calls it: exit 0 → inject `AND project = <KEY>` into the default JQL; exit 3 (unmapped) or 4 (no remote / not a repo) → hard stop with the script's stderr message. An explicit `next.jql` override still wins verbatim and skips scope resolution entirely.

**Tech Stack:** bash + awk (no new dependencies), existing script/test conventions (`plugins/bitacora/scripts/`, deterministic test harness, shellcheck severity=warning), GitHub Actions matrix CI.

**Out of scope:** GitHub Issues backend (#117), Approach C live-match fallback (deferred in the issue), release/version bumps (separate release PR per runbook).

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `plugins/bitacora/scripts/resolve-project-scope.sh` | Create | remote read → slug normalize → map lookup; exit codes 0/2/3/4 |
| `plugins/bitacora/scripts/test-resolve-project-scope.sh` | Create | deterministic tests (temp git repos + temp configs) |
| `plugins/bitacora/skills/session-next/SKILL.md` | Modify | new step 2 (resolve project scope), renumber 2–7 → 3–8, scoped default JQL, error/edge entries, config docs |
| `plugins/bitacora/skills/jira-comment-format/SKILL.md` | Modify | document the `next.*` config block (incl. per-slug map precedence exception) |
| `.github/workflows/test.yml` | Modify | add the new test step |

No changes to `plugins/bitacora/commands/next.md` (thin alias), `examples/shortlist.txt` (output shape unchanged), README/USAGE (don't document `next.*` config), or CHANGELOG/manifests (release PR handles those).

---

### Task 1: `resolve-project-scope.sh` + tests (TDD)

**Files:**
- Test: `plugins/bitacora/scripts/test-resolve-project-scope.sh`
- Create: `plugins/bitacora/scripts/resolve-project-scope.sh`

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-resolve-project-scope.sh` with exactly:

```bash
#!/usr/bin/env bash
# Deterministic tests for resolve-project-scope.sh. Builds throwaway git repos
# and config files under mktemp so nothing depends on the caller's environment,
# real remotes, or a real ~/.claude/bitacora.yml.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
RPS="$DIR/resolve-project-scope.sh"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() {  # name [remote-url] → prints repo path; no remote when url omitted
  local path="$TMP/$1"
  git init -q "$path"
  [[ -n "${2:-}" ]] && git -C "$path" remote add origin "$2"
  printf '%s' "$path"
}

# Home-level config: the central map (plus unrelated keys the parser must skip).
HOME_CFG="$TMP/home-bitacora.yml"
cat > "$HOME_CFG" <<'EOF'
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"
comment_compliance:
  status_extraction: strict
next:
  stale_days: 30
  remote_project_map:
    "github.com/org/ai-advisor-portal": "AT"   # quoted entry + inline comment
    github.com/org/unquoted-repo: TESTING
    "github.com/org/shared-repo": "HOME"
digest:
  epic_type: Epic
EOF

# Repo-level config: overrides shared-repo only.
REPO_CFG="$TMP/repo-bitacora.yml"
cat > "$REPO_CFG" <<'EOF'
next:
  remote_project_map:
    "github.com/org/shared-repo": "REPO"
EOF

# A config with no next: block at all.
NOMAP_CFG="$TMP/nomap.yml"
echo 'project_key_pattern: "[A-Z]+-\\d+"' > "$NOMAP_CFG"

MISSING="$TMP/does-not-exist.yml"

check() {  # desc expected-stdout expected-code args...
  local desc="$1" expected="$2" want_code="$3"; shift 3
  local out code
  out="$(bash "$RPS" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == "$want_code" ]]; then
    echo "PASS: $desc → '$out' ($code)"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' ($want_code)"; fail=1
  fi
}
check_err_contains() {  # desc substring expected-code args...
  local desc="$1" sub="$2" want_code="$3"; shift 3
  local err code
  err="$(bash "$RPS" "$@" 2>&1 >/dev/null)"; code=$?
  if [[ "$code" == "$want_code" && "$err" == *"$sub"* ]]; then
    echo "PASS: $desc → exit $code, stderr names '$sub'"
  else
    echo "FAIL: $desc → exit $code, stderr '$err' (expected $want_code containing '$sub')"; fail=1
  fi
}

SSH_REPO="$(mkrepo ssh-repo 'git@github.com:Org/AI-Advisor-Portal.git')"
HTTPS_REPO="$(mkrepo https-repo 'https://github.com/org/ai-advisor-portal.git')"
SSHPROTO_REPO="$(mkrepo sshproto-repo 'ssh://git@github.com/org/ai-advisor-portal.git')"
NOGIT_SUFFIX_REPO="$(mkrepo nosuffix-repo 'https://github.com/org/unquoted-repo')"
SHARED_REPO="$(mkrepo shared-repo 'git@github.com:org/shared-repo.git')"
UNMAPPED_REPO="$(mkrepo unmapped-repo 'git@github.com:other/vatios.git')"
BARE_REPO="$(mkrepo bare-repo)"          # git repo, no remotes
PLAIN_DIR="$TMP/plain-dir"; mkdir -p "$PLAIN_DIR"   # not a git repo

check "ssh remote (+case, +.git strip)"  AT 0 --dir "$SSH_REPO"      --repo-config "$MISSING" --home-config "$HOME_CFG"
check "https remote"                     AT 0 --dir "$HTTPS_REPO"    --repo-config "$MISSING" --home-config "$HOME_CFG"
check "ssh:// protocol remote"           AT 0 --dir "$SSHPROTO_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check "no .git suffix, unquoted entry"   TESTING 0 --dir "$NOGIT_SUFFIX_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check "repo-level map overrides home"    REPO 0 --dir "$SHARED_REPO" --repo-config "$REPO_CFG" --home-config "$HOME_CFG"
check "home fallback (repo cfg lacks slug)" HOME 0 --dir "$SHARED_REPO" --repo-config "$NOMAP_CFG" --home-config "$HOME_CFG"

check_err_contains "slug not in any map → exit 3"   "github.com/other/vatios" 3 --dir "$UNMAPPED_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check_err_contains "both configs missing → exit 3"  "github.com/other/vatios" 3 --dir "$UNMAPPED_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check_err_contains "repo without remotes → exit 4"  "no git remote" 4 --dir "$BARE_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check_err_contains "not a git repo → exit 4"        "not a git repository" 4 --dir "$PLAIN_DIR" --repo-config "$MISSING" --home-config "$HOME_CFG"
check_err_contains "unknown arg → exit 2"           "unknown arg" 2 --bogus

exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-resolve-project-scope.sh`
Expected: every line `FAIL` (the script under test doesn't exist yet, so each invocation exits 127), final exit code 1.

- [ ] **Step 3: Write the implementation**

Create `plugins/bitacora/scripts/resolve-project-scope.sh` with exactly:

```bash
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
slug="${slug/:/\/}"          # scp-style host:owner/repo → host/owner/repo
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
```

One awk subtlety to preserve: split entries on `": "` (colon-space, see `pos=index(line, ": ")`), not bare `:` — the quoted slug itself contains no colon, but this keeps the parse unambiguous and YAML requires the space after `:` anyway.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/bitacora/scripts/test-resolve-project-scope.sh`
Expected: 11 `PASS` lines, exit 0.

If an awk case fails, debug with `bash -x` on the single failing invocation rather than tweaking blind.

- [ ] **Step 5: Shellcheck both new files**

Run: `shellcheck --severity=warning plugins/bitacora/scripts/resolve-project-scope.sh plugins/bitacora/scripts/test-resolve-project-scope.sh`
Expected: no output, exit 0. (CI lints every script in the directory at this severity; fix any finding now.)

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/scripts/resolve-project-scope.sh plugins/bitacora/scripts/test-resolve-project-scope.sh
git commit -m "feat(next): resolve-project-scope.sh — git remote → Jira project key (#118)"
```

(No Co-Authored-By trailer — commits are authored by the repo owner only.)

---

### Task 2: Wire scope resolution into `session-next/SKILL.md`

**Files:**
- Modify: `plugins/bitacora/skills/session-next/SKILL.md`

- [ ] **Step 1: Insert the new step 2 and renumber**

After the `## 1. Resolve the Atlassian site` section (currently ends line 18) insert:

```markdown
## 2. Resolve the project scope (git / local)

The default query is always scoped to the current repo's Jira project — never a
site-wide dump of everything assigned to you. **Skip this step entirely when
`next.jql` is set** — the override is the user's verbatim query and owns its own
scoping.

```
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-project-scope.sh"
```

(From the repo root: `plugins/bitacora/scripts/resolve-project-scope.sh`.) The script
reads the repo's git remote (`origin`, else the first remote), normalizes it to a
lowercase `host/owner/repo` slug, and resolves it through the
`next.remote_project_map` config table (repo-level `.bitacora.yml` entry overrides
the `~/.claude/bitacora.yml` one, per slug — see Configuration).

- **Exit 0** — stdout is the Jira project key; inject `AND project = <KEY>` into the
  default JQL (step 3).
- **Exit 3** (remote found but slug not mapped) or **exit 4** (not a git repo / no
  remote) — **hard stop.** Relay the script's stderr message verbatim — it names the
  detected slug and shows the exact YAML to add. Do **not** fall back to an unscoped
  query.
```

Then renumber the following section headings (content otherwise untouched except where later steps say):
- `## 2. Query the tickets` → `## 3. Query the tickets`
- `## 3. Gather signals (bounded [CTX] read)` → `## 4. …`
- `## 4. Categorize` → `## 5. …`
- `## 5. Reason-to-pick` → `## 6. …`
- `## 6. Recommend` → `## 7. …`
- `## 7. Render the shortlist` → `## 8. …`

Sanity-grep for stale references: `grep -n "step [0-9]\|## [0-9]" plugins/bitacora/skills/session-next/SKILL.md` — the only numbered cross-reference should be the new step 2's "(step 3)".

- [ ] **Step 2: Scope the default JQL in the Query section**

In the (now) `## 3. Query the tickets` section, replace:

```
`searchJiraIssuesUsingJql`. Default JQL:

```
assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
```

Capped at ~50 results. `.bitacora.yml` → `next.jql` overrides the default verbatim
(no merging, no silent fallback).
```

with:

```
`searchJiraIssuesUsingJql`. Default JQL (`<KEY>` is the project key from step 2):

```
assignee = currentUser() AND project = <KEY> AND statusCategory != Done ORDER BY updated DESC
```

Capped at ~50 results. `.bitacora.yml` → `next.jql` overrides the default verbatim
(no merging, no silent fallback, no scope injection — the override owns its scoping
and step 2 is skipped entirely).
```

- [ ] **Step 3: Add the hard-stop to Error / edge behavior**

In `## Error / edge behavior`, insert after the first bullet (MCP absent):

```markdown
- **No project scope** (repo's remote slug not in `next.remote_project_map`, repo has
  no remote, or CWD is not a git repo) and no `next.jql` override: **hard stop.**
  Relay `resolve-project-scope.sh`'s stderr verbatim (it names the detected slug and
  the exact YAML to add). Never degrade to the unscoped site-wide query — that
  surfaces another project's backlog with full confidence (#118).
```

- [ ] **Step 4: Document the map in Configuration**

Replace the yaml block in `## Configuration` (keep the surrounding prose) with:

```yaml
next:
  # The default JQL is:
  #   assignee = currentUser() AND project = <KEY> AND statusCategory != Done ORDER BY updated DESC
  # where <KEY> comes from remote_project_map below. Override the whole query for
  # team-scoped pickers. Teammates must be referenced by Jira accountId —
  # `assignee in (...)` does not accept email addresses or usernames in Jira Cloud
  # (GDPR-era privacy migration). Use `lookupJiraAccountId` to resolve a teammate's
  # email → accountId once, then paste the accountId here.
  jql: ""            # overrides the default query verbatim when set (owns its own
                     # scoping; remote_project_map is not consulted); e.g.:
                     #   "assignee in (currentUser(), 5a17b8c2..., 5b22d9e3...) AND statusCategory != Done ORDER BY updated DESC"
  stale_days: 30     # "stale" threshold for the Needs-attention tail
  # Git-remote → Jira-project table that scopes the default query. The repo's
  # remote is normalized to a lowercase host/owner/repo slug and resolved here;
  # no entry → hard stop (never an unscoped dump). Keep the central table in
  # ~/.claude/bitacora.yml; a repo-level .bitacora.yml entry overrides the home
  # one for the same slug.
  remote_project_map:
    "github.com/org/ai-advisor-portal": "AT"
    "github.com/org/some-other-repo": "TESTING"
```

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-next/SKILL.md
git commit -m "feat(next): scope the default query to the repo's Jira project, hard-stop on no mapping (#118)"
```

---

### Task 3: Document `next.*` in `jira-comment-format/SKILL.md`

**Files:**
- Modify: `plugins/bitacora/skills/jira-comment-format/SKILL.md` (Configuration section, after the `digest.*` paragraph that ends "…remain single-ticket-only." at line 277)

- [ ] **Step 1: Append the `next.*` block**

Add at the end of the `## Configuration` section:

```markdown
`/bitacora:next` reads its own `next.*` keys (full semantics in `session-next`):

```yaml
next:
  jql: ""              # verbatim override of the default picker query (owns its own scoping)
  stale_days: 30       # "stale" threshold for the Needs-attention tail
  remote_project_map:  # git-remote slug → Jira project key; scopes the default query.
    "github.com/org/repo": "AT"
```

One exception to the file-level "repo `.bitacora.yml` *else* home" rule above:
`next.remote_project_map` is consulted **per slug across both files** (a repo-level
entry overrides the home one for the same slug), so the home file can stay the
central table while individual repos override their own mapping.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/SKILL.md
git commit -m "docs(jira-comment-format): document the next.* config block incl. remote_project_map precedence (#118)"
```

---

### Task 4: CI wiring + full suite

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Add the test step**

In `.github/workflows/test.yml`, after the final step (`Run handoff guardrail hook tests`, line 48–49) append:

```yaml
      - name: Run resolve-project-scope tests
        run: bash plugins/bitacora/scripts/test-resolve-project-scope.sh
```

(The lint job already globs `plugins/bitacora/scripts/*.sh`, so the new scripts are shellchecked with no workflow change.)

- [ ] **Step 2: Run the full local suite**

Run:

```bash
shellcheck --severity=warning plugins/bitacora/scripts/*.sh plugins/bitacora/statusline/*.sh
for t in plugins/bitacora/scripts/test-*.sh; do echo "== $t"; bash "$t" || echo "SUITE FAIL: $t"; done
```

Expected: shellcheck silent; all 11 suites (10 existing + the new one) pass with no `SUITE FAIL` / `FAIL` lines.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: run resolve-project-scope tests (#118)"
```

---

## Acceptance check (from issue #118)

- Repo whose remote maps to a key → `next` queries only that project: Task 2 step 2 (JQL injection).
- Repo with no mapping (e.g. vatios) → hard stop, zero unrelated tickets: Task 1 exits 3/4 + Task 2 steps 1 & 3.
- `next.jql` override path unchanged: Task 2 steps 1–2 (skip + no injection).
- Script tests cover ssh remote, https remote, no remote, not-a-git-repo, slug not in map, repo-level override of home map: Task 1 step 1 (plus ssh://, unquoted entries, home fallback, case/`.git` normalization, both-configs-missing, bad arg).

## Finish

Branch: `feature/118-next-project-scope` (created before Task 1). After all tasks: push, open a PR titled `feat(next): scope the query to the current repo's Jira project (#118)` with `Closes #118`, follow the repo's PR → CR → squash-merge flow. Release bump (version + CHANGELOG) is a separate release PR per the runbook.
