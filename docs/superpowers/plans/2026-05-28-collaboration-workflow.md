# Collaboration Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an issue-first collaboration workflow — `CONTRIBUTING.md`, three issue templates, a PR template, four labels, and two GitHub Actions (auto-label new issues; gate PRs on a `ready-for-dev` linked issue) — so that the GitHub repo enforces "open an issue, get it triaged, then code."

**Architecture:** Plain files in `.github/` and the repo root, plus a maintainer-side `docs/TRIAGE.md`. The two workflows are bash + `gh` CLI (preinstalled on `ubuntu-latest`) using `${{ secrets.GITHUB_TOKEN }}`. The gate uses GraphQL `closingIssuesReferences` (the same relation GitHub uses for `Closes #N`). No third-party Actions or apps. The sticky-comment behavior is implemented in bash with a marker line.

**Tech Stack:** Markdown, GitHub Issue Forms (YAML), GitHub Actions YAML, bash, `gh` CLI, GitHub GraphQL API v4.

**Spec:** `docs/superpowers/specs/2026-05-28-collaboration-workflow-design.md`

**Branch:** `worktree-chore+contributing-workflow` (worktree at `.claude/worktrees/chore+contributing-workflow/`). The maintainer may rename to `chore/contributing-workflow` before pushing.

---

## Conventions verified

- The repo has GitHub Actions enabled (`.github/workflows/test.yml` exists).
- Stock labels present: `bug`, `enhancement`, `documentation`, `question`,
  `good first issue`, `help wanted`, `duplicate`, `invalid`, `wontfix`. The new
  labels (`needs-triage`, `needs-info`, `ready-for-dev`, `skip-issue-check`) do
  **not** exist yet — the bootstrap step in `label-new-issues.yml` creates them.
- The repo is `fr1j0/bitacora`. PRs target `main`.
- No CONTRIBUTING.md, no issue templates, no PR template currently exist.
- The Bitácora plugin uses MIT license; contributor footer says so.
- Commits in this repo do **not** use `Co-Authored-By: Claude …` trailers.

## File structure

**Create (9 files):**

| Path | Purpose |
|---|---|
| `CONTRIBUTING.md` | Front-door doc — produces the "Contributing" tab on the repo home page |
| `docs/TRIAGE.md` | Maintainer-side triage process |
| `.github/ISSUE_TEMPLATE/config.yml` | Disable blank issues; contact link to README scope notes |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Bug report issue form |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Feature request issue form |
| `.github/ISSUE_TEMPLATE/question.yml` | Question issue form |
| `.github/pull_request_template.md` | Default PR body |
| `.github/workflows/label-new-issues.yml` | Bootstrap new labels + auto-apply `needs-triage` |
| `.github/workflows/issue-gate.yml` | Block PRs that aren't linked to a `ready-for-dev` issue |

**Modify:** none. Existing `README.md`, `LICENSE`, `.github/workflows/test.yml` are untouched.

## Testing strategy

These are configuration files — there is no unit-test harness. Per-task verification:

1. **YAML parses** — `python3 -c 'import yaml; yaml.safe_load(open(PATH))'` for every `.yml` file.
2. **Workflow lints clean** — `actionlint` if available locally; otherwise rely on GitHub's parser (the workflow will show as invalid in the Actions tab if broken).
3. **Markdown renders** — open in any markdown viewer or rely on visual review in the PR.

End-to-end verification is **post-merge, on the live repo**, executed by the maintainer per §"Testing & verification plan" of the spec. The plan captures these as the final task's checklist; they are *not* run during this implementation.

---

## Task 1: `CONTRIBUTING.md` — the front-door doc

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Write `CONTRIBUTING.md`**

Create `CONTRIBUTING.md` at the repo root with this content:

````markdown
# Contributing to Bitácora

Thanks for your interest! Bitácora is in **alpha** and we're keeping the contribution flow
deliberately simple: **every change starts as an issue.**

## The flow

1. **Open an issue.** Pick a template:
   - [Bug report](https://github.com/fr1j0/bitacora/issues/new?template=bug_report.yml)
   - [Feature request](https://github.com/fr1j0/bitacora/issues/new?template=feature_request.yml)
   - [Question](https://github.com/fr1j0/bitacora/issues/new?template=question.yml)
2. **Wait for triage.** A maintainer will review and either close it, ask for more
   info (`needs-info` label), or approve it (`ready-for-dev` label).
3. **Branch and code.** Once your issue has `ready-for-dev`, create a topic branch
   named `<type>/issue-<N>-<slug>` (e.g. `feat/issue-42-context-meter`,
   `fix/issue-17-empty-ctx`) **off `main`**. Never push to `main` directly.
4. **Open a PR.** Include `Closes #<N>` in the PR body. An automated check verifies
   the linked issue is `ready-for-dev`; if not, the check fails and the PR can't merge.

## Why issue-first?

Bitácora has a [tight scope](README.md#what-lives-where--status-vs-scratch) — it tracks
status and continuity on Jira tickets, and *not* ticket-authoring, spike-running, or
other workflows that have been considered and parked. Triaging first saves you from
writing code that won't be accepted.

## Maintainer exceptions

Maintainers can apply `skip-issue-check` to a PR for typo-only, CI-only, or docs-only
fixes. Everything else needs an approved issue.

## Branching rules

- Branch off `main`. Never push to `main` directly (it's branch-protected).
- Branch name: `<type>/issue-<N>-<slug>`. `<type>` is one of `feat`, `fix`, `chore`,
  `docs`, `refactor`, `test`.
- Squash-merge is the default. Keep commits descriptive but don't over-engineer the
  history — squash collapses it.

## Code of Conduct

Be kind. Assume good faith. If something feels off, open an issue or reach out to a
maintainer.

## License

By contributing, you agree your work is licensed under the [MIT License](LICENSE).
````

- [ ] **Step 2: Verify the file renders as markdown**

Skim the file for broken syntax (mismatched code fences, unclosed links). Optional: run a markdown linter if you have one installed (`markdownlint CONTRIBUTING.md`).

Expected: no parse errors; links to `README.md` and `LICENSE` resolve to existing files.

- [ ] **Step 3: Verify referenced files exist**

```bash
test -f README.md && test -f LICENSE && echo OK
```

Expected output: `OK`

- [ ] **Step 4: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING.md front-door doc"
```

---

## Task 2: `docs/TRIAGE.md` — maintainer process

**Files:**
- Create: `docs/TRIAGE.md`

- [ ] **Step 1: Write `docs/TRIAGE.md`**

Create `docs/TRIAGE.md`:

````markdown
# Triage

Maintainer-side process for handling incoming issues.

## Inbox

```
is:issue is:open label:needs-triage
```

Bookmark this query: <https://github.com/fr1j0/bitacora/issues?q=is%3Aissue+is%3Aopen+label%3Aneeds-triage>

## Decision tree

For each issue in the inbox, do **one** of:

1. **Duplicate** → close with a comment linking the original. Remove `needs-triage`.
2. **Out of scope** → close with a short note explaining why. Link to the scope notes
   (see below). Remove `needs-triage`.
3. **Need more info** → add label `needs-info`, remove `needs-triage`, post a comment
   with the specific questions.
4. **Approve** → add label `ready-for-dev`, remove `needs-triage`. The contributor can
   now open a PR.

## Scope guardrails

Bitácora's scope is **status-tracking and continuity** — `[CTX]` comments, handoff,
resume, status synthesis, and (planned) ticket-picking. Out of scope:

- Ticket-authoring (creating Jira tickets from scratch).
- `/improve` (sharpening vague tickets) — considered and dropped; native Jira AI suffices.
- `/spike` (running spikes from prompts) — considered and dropped; reads status, not
  authors.
- Anything that mutates Jira ticket fields beyond comments.

If an issue proposes any of the above, it's a polite close.

## SLA

Aspirational only: best-effort response within ~1 week. We're an alpha project run by
volunteers.

## Label ownership

Only maintainers apply `ready-for-dev` and `skip-issue-check`. Contributors should not
self-apply these (the gate workflow only trusts maintainer labels in practice; we don't
hard-enforce this, but it's the social contract).

## Branch protection (one-time admin)

To enforce the gate, a repo admin must enable branch protection on `main`:

1. Settings → Branches → Add branch protection rule for `main`.
2. Check **Require status checks to pass before merging**.
3. Add **`gate`** (the job name from `.github/workflows/issue-gate.yml`) to required checks.
4. Check **Require a pull request before merging** and disable direct pushes.

Until this is configured, the gate runs but doesn't block merges.
````

- [ ] **Step 2: Verify file renders and the issue-query URL is well-formed**

Eyeball the markdown; confirm the URL works:

```bash
# Sanity-check the URL encoding
python3 -c "from urllib.parse import unquote; print(unquote('is%3Aissue+is%3Aopen+label%3Aneeds-triage'))"
```

Expected: `is:issue is:open label:needs-triage`

- [ ] **Step 3: Commit**

```bash
git add docs/TRIAGE.md
git commit -m "docs: add maintainer-side triage process"
```

---

## Task 3: Issue templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/question.yml`

- [ ] **Step 1: Write `config.yml`**

Create `.github/ISSUE_TEMPLATE/config.yml`:

```yaml
blank_issues_enabled: false
contact_links:
  - name: Read the scope notes first
    url: https://github.com/fr1j0/bitacora#what-lives-where--status-vs-scratch
    about: Before opening an issue, skim "What lives where" in the README.
```

- [ ] **Step 2: Write `bug_report.yml`**

Create `.github/ISSUE_TEMPLATE/bug_report.yml`:

```yaml
name: Bug report
description: Something Bitácora does but shouldn't, or doesn't but should.
title: "[bug] "
labels: ["bug", "needs-triage"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for filing a bug. The more concrete the repro, the faster we can fix.
        Please skim open issues first to avoid duplicates.

  - type: textarea
    id: summary
    attributes:
      label: Summary
      description: One or two sentences. What broke?
      placeholder: "/bitacora:handoff fails when the ticket has no [CTX] comments yet."
    validations:
      required: true

  - type: textarea
    id: repro_steps
    attributes:
      label: Steps to reproduce
      description: Numbered steps from a clean state.
      placeholder: |
        1. Open a Jira ticket with no comments.
        2. Run `/bitacora:handoff TICKET-123`.
        3. ...
    validations:
      required: true

  - type: textarea
    id: expected_vs_actual
    attributes:
      label: Expected vs actual
      placeholder: |
        Expected: a draft [CTX] comment is generated.
        Actual: command errors with "no comments found".
    validations:
      required: true

  - type: textarea
    id: environment
    attributes:
      label: Environment
      description: Claude Code version, Atlassian MCP version, OS.
      placeholder: |
        Claude Code: 1.x.x
        Atlassian Rovo MCP: x.y.z
        OS: macOS 15.0
    validations:
      required: true

  - type: textarea
    id: logs
    attributes:
      label: Logs / screenshots
      description: Paste relevant log output. Redact ticket IDs and tokens.
    validations:
      required: false

  - type: checkboxes
    id: confirmation
    attributes:
      label: Confirmation
      options:
        - label: I searched existing issues and didn't find a duplicate.
          required: true
        - label: I'm running the latest `main` (or have noted the version above).
          required: true
```

- [ ] **Step 3: Write `feature_request.yml`**

Create `.github/ISSUE_TEMPLATE/feature_request.yml`:

```yaml
name: Feature request
description: Suggest a new command, workflow, or capability.
title: "[feat] "
labels: ["enhancement", "needs-triage"]
body:
  - type: markdown
    attributes:
      value: |
        Bitácora has a [tight scope](https://github.com/fr1j0/bitacora#what-lives-where--status-vs-scratch) —
        status-tracking and continuity. Ticket-authoring, /improve, /spike, and similar
        are out of scope. Please confirm fit before filing.

  - type: textarea
    id: problem
    attributes:
      label: Problem
      description: What can't you do today, or what's painful?
      placeholder: "When I resume on a ticket I haven't touched in a week, I want a 30-second recap..."
    validations:
      required: true

  - type: textarea
    id: proposed_solution
    attributes:
      label: Proposed solution
      description: Roughly how would Bitácora address this?
    validations:
      required: true

  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives considered
      description: Other approaches you weighed, including doing nothing.
    validations:
      required: false

  - type: checkboxes
    id: scope_check
    attributes:
      label: Scope check
      options:
        - label: I've read the "What lives where" section and believe this is within scope (status-tracking / continuity, not ticket-authoring).
          required: true
```

- [ ] **Step 4: Write `question.yml`**

Create `.github/ISSUE_TEMPLATE/question.yml`:

```yaml
name: Question
description: You're stuck and the README didn't help.
title: "[question] "
labels: ["question", "needs-triage"]
body:
  - type: markdown
    attributes:
      value: |
        Questions may be converted to a Discussion or closed without triage if they're
        better suited elsewhere. That's not a rejection — it just helps keep the issue
        tracker focused on bugs and features.

  - type: textarea
    id: goal
    attributes:
      label: What are you trying to do?
      placeholder: "I'm trying to wire /bitacora:resume into my existing handoff workflow..."
    validations:
      required: true

  - type: textarea
    id: tried
    attributes:
      label: What have you tried?
    validations:
      required: true

  - type: textarea
    id: stuck_where
    attributes:
      label: Where are you stuck?
    validations:
      required: true
```

- [ ] **Step 5: Validate every YAML file parses**

```bash
for f in .github/ISSUE_TEMPLATE/*.yml; do
  python3 -c "import yaml,sys; yaml.safe_load(open('$f'))" && echo "OK: $f" || { echo "FAIL: $f"; exit 1; }
done
```

Expected output: four `OK:` lines, one per file.

- [ ] **Step 6: Verify GitHub Issue Forms required top-level keys**

The four templates must each have `name`, `description`, `body`. `config.yml` must have `blank_issues_enabled` (and optionally `contact_links`).

```bash
python3 - <<'PY'
import yaml, pathlib, sys
ok = True
for f in pathlib.Path(".github/ISSUE_TEMPLATE").glob("*.yml"):
    data = yaml.safe_load(f.read_text())
    if f.name == "config.yml":
        if "blank_issues_enabled" not in data:
            print(f"FAIL: {f} missing blank_issues_enabled"); ok = False
    else:
        for key in ("name", "description", "body"):
            if key not in data:
                print(f"FAIL: {f} missing {key}"); ok = False
                continue
print("OK" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
```

Expected output ends with `OK`.

- [ ] **Step 7: Commit**

```bash
git add .github/ISSUE_TEMPLATE/
git commit -m "feat: add issue templates (bug, feature, question)"
```

---

## Task 4: PR template

**Files:**
- Create: `.github/pull_request_template.md`

- [ ] **Step 1: Write `pull_request_template.md`**

Create `.github/pull_request_template.md`:

```markdown
## Linked issue

Closes #<!-- issue number -->

<!--
A linked issue with the `ready-for-dev` label is required. The `gate` workflow
checks this automatically. If you're a maintainer making a typo/CI/docs-only fix,
apply the `skip-issue-check` label to bypass the gate.
-->

## What & why

<!-- 1-3 sentences. Why this change, not what (the diff shows that). -->

## Test plan

<!-- How you verified this. Include commands if relevant. -->

## Checklist

- [ ] Linked issue is labeled `ready-for-dev` (or this PR is maintainer-only and carries `skip-issue-check`).
- [ ] Branch name follows `<type>/issue-<N>-<slug>` (e.g. `feat/issue-42-context-meter`).
- [ ] Tests added/updated where reasonable.
```

- [ ] **Step 2: Verify file is well-formed**

```bash
test -s .github/pull_request_template.md && head -1 .github/pull_request_template.md
```

Expected output: `## Linked issue`

- [ ] **Step 3: Commit**

```bash
git add .github/pull_request_template.md
git commit -m "feat: add pull request template"
```

---

## Task 5: `label-new-issues.yml` — auto-label workflow

**Files:**
- Create: `.github/workflows/label-new-issues.yml`

- [ ] **Step 1: Write `label-new-issues.yml`**

Create `.github/workflows/label-new-issues.yml`:

```yaml
name: Label new issues

on:
  issues:
    types: [opened]

permissions:
  issues: write

jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - name: Bootstrap labels (idempotent)
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPO: ${{ github.repository }}
        run: |
          set -eu
          create_label() {
            local name="$1" color="$2" desc="$3"
            gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" 2>/dev/null || true
          }
          create_label "needs-triage"     "fbca04" "New issue, awaiting maintainer review"
          create_label "needs-info"       "d4a017" "Maintainer asked for more info; waiting on reporter"
          create_label "ready-for-dev"    "0e8a16" "Triaged and approved; safe to start coding"
          create_label "skip-issue-check" "cccccc" "PR exempt from the issue-gate (typo/CI/docs-only)"

      - name: Apply needs-triage to opened issue
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPO: ${{ github.repository }}
          ISSUE: ${{ github.event.issue.number }}
        run: |
          gh issue edit "$ISSUE" --repo "$REPO" --add-label needs-triage
```

- [ ] **Step 2: Validate YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/label-new-issues.yml'))" && echo OK
```

Expected output: `OK`

- [ ] **Step 3: Lint with actionlint (if available)**

```bash
command -v actionlint >/dev/null && actionlint .github/workflows/label-new-issues.yml || echo "actionlint not installed; skipping (GitHub will validate on push)"
```

Expected: no output from `actionlint` (clean) OR the "not installed" message.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/label-new-issues.yml
git commit -m "ci: auto-label new issues with needs-triage"
```

---

## Task 6: `issue-gate.yml` — PR gate workflow

**Files:**
- Create: `.github/workflows/issue-gate.yml`

This is the largest file. Read the whole task before starting.

- [ ] **Step 1: Write `issue-gate.yml`**

Create `.github/workflows/issue-gate.yml`:

```yaml
# This workflow uses `pull_request_target` so it runs with the target repo's
# write token even when the PR comes from a fork (required to post the sticky
# comment). It does NOT check out PR head code; it only reads metadata via the
# GitHub API. That keeps the security surface small — see issue-gate spec §Risks.
name: Issue gate

on:
  pull_request_target:
    types: [opened, synchronize, edited, reopened, labeled, unlabeled]

permissions:
  pull-requests: write
  issues: read
  contents: read

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - name: Run gate
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPO: ${{ github.repository }}
          PR: ${{ github.event.pull_request.number }}
          OWNER: ${{ github.repository_owner }}
        shell: bash
        run: |
          set -euo pipefail

          MARKER='<!-- bitacora-issue-gate -->'
          NAME="${REPO#*/}"

          # ------------------------------------------------------------------
          # post_or_update_sticky: write the marker comment, or edit it in place
          # ------------------------------------------------------------------
          post_or_update_sticky() {
            local body="$1"
            local full="${MARKER}
${body}"
            # Look for an existing comment authored by github-actions[bot] with the marker.
            local existing
            existing=$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate \
              --jq ".[] | select(.user.login==\"github-actions[bot]\") | select(.body | startswith(\"${MARKER}\")) | .id" \
              | head -n1 || true)
            if [ -n "$existing" ]; then
              gh api -X PATCH "repos/${REPO}/issues/comments/${existing}" -f body="$full" >/dev/null
            else
              gh pr comment "$PR" --repo "$REPO" --body "$full" >/dev/null
            fi
          }

          # ------------------------------------------------------------------
          # Override: PR carries skip-issue-check label?
          # ------------------------------------------------------------------
          pr_labels=$(gh pr view "$PR" --repo "$REPO" --json labels --jq '.labels[].name')
          if grep -qx "skip-issue-check" <<<"$pr_labels"; then
            post_or_update_sticky "$(printf 'Gate skipped — `skip-issue-check` applied by a maintainer.')"
            exit 0
          fi

          # ------------------------------------------------------------------
          # Query linked closing issues + their labels
          # ------------------------------------------------------------------
          response=$(gh api graphql -f query='
            query($owner: String!, $name: String!, $number: Int!) {
              repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                  closingIssuesReferences(first: 20) {
                    nodes {
                      number
                      labels(first: 30) { nodes { name } }
                    }
                  }
                }
              }
            }' -F owner="$OWNER" -F name="$NAME" -F number="$PR")

          # Extract: array of "number:label1,label2,..." strings
          linked=$(jq -r '.data.repository.pullRequest.closingIssuesReferences.nodes[] | "\(.number):\([.labels.nodes[].name] | join(","))"' <<<"$response")

          # ------------------------------------------------------------------
          # No linked issues at all -> fail
          # ------------------------------------------------------------------
          if [ -z "$linked" ]; then
            msg=$(cat <<'MSG'
Gate failed — no linked issue found.

Add `Closes #<N>` (or `Fixes #<N>` / `Resolves #<N>`) to the PR body, or link an
issue manually in the right-hand sidebar. The linked issue must carry the
`ready-for-dev` label.

See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md) for the full flow.
MSG
            )
            post_or_update_sticky "$msg"
            exit 1
          fi

          # ------------------------------------------------------------------
          # At least one linked issue carries ready-for-dev -> pass
          # ------------------------------------------------------------------
          approved=()
          unapproved=()
          while IFS= read -r entry; do
            num="${entry%%:*}"
            labels="${entry#*:}"
            if [[ ",${labels}," == *",ready-for-dev,"* ]]; then
              approved+=("$num")
            else
              unapproved+=("$num")
            fi
          done <<<"$linked"

          if [ "${#approved[@]}" -gt 0 ]; then
            list=$(IFS=,; echo "${approved[*]}" | sed 's/,/, #/g')
            post_or_update_sticky "Gate passed — linked to approved issue(s) #${list}."
            exit 0
          fi

          # ------------------------------------------------------------------
          # Linked issues exist but none are ready-for-dev -> fail
          # ------------------------------------------------------------------
          list=$(IFS=,; echo "${unapproved[*]}" | sed 's/,/, #/g')
          msg=$(cat <<MSG
Gate failed — linked issue(s) #${list} are not yet approved for coding.

A maintainer needs to triage them and apply the \`ready-for-dev\` label before
this PR can merge. See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md).
MSG
          )
          post_or_update_sticky "$msg"
          exit 1
```

- [ ] **Step 2: Validate YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/issue-gate.yml'))" && echo OK
```

Expected output: `OK`

- [ ] **Step 3: Lint with actionlint and shellcheck (if available)**

```bash
command -v actionlint >/dev/null && actionlint .github/workflows/issue-gate.yml || echo "actionlint not installed; will be validated on push"
```

Expected: no output from `actionlint` (clean) OR the "not installed" message.

`actionlint` automatically runs `shellcheck` on inline `run:` blocks when both are installed. If only `shellcheck` is available, extract the script and check manually — *optional, not required*.

- [ ] **Step 4: Sanity-check the GraphQL query is well-formed**

```bash
# Extract and pretty-check the query string
python3 - <<'PY'
import yaml, re
wf = yaml.safe_load(open(".github/workflows/issue-gate.yml"))
script = wf["jobs"]["gate"]["steps"][0]["run"]
m = re.search(r"query=\'(.+?)\'", script, re.DOTALL)
assert m, "GraphQL query not found"
q = m.group(1)
# Sanity: balanced braces and the expected fields exist
assert q.count("{") == q.count("}"), "unbalanced braces in GraphQL"
for needle in ("closingIssuesReferences", "labels", "number"):
    assert needle in q, f"missing {needle}"
print("OK")
PY
```

Expected output: `OK`

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/issue-gate.yml
git commit -m "ci: gate PRs on a linked, ready-for-dev issue"
```

---

## Task 7: Final review and PR

**Files:** none new — this task verifies the whole change and opens the PR.

- [ ] **Step 1: Run the full validation pass**

```bash
# All YAML parses
for f in .github/ISSUE_TEMPLATE/*.yml .github/workflows/label-new-issues.yml .github/workflows/issue-gate.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK: $f"
done

# All expected files exist
for f in CONTRIBUTING.md docs/TRIAGE.md \
         .github/ISSUE_TEMPLATE/config.yml \
         .github/ISSUE_TEMPLATE/bug_report.yml \
         .github/ISSUE_TEMPLATE/feature_request.yml \
         .github/ISSUE_TEMPLATE/question.yml \
         .github/pull_request_template.md \
         .github/workflows/label-new-issues.yml \
         .github/workflows/issue-gate.yml; do
  test -s "$f" && echo "OK: $f" || echo "MISSING: $f"
done
```

Expected: every line begins with `OK:`.

- [ ] **Step 2: Confirm no other files were modified**

```bash
git diff --name-only main...HEAD
```

Expected: exactly nine new file paths, all under `CONTRIBUTING.md`, `docs/TRIAGE.md`, `.github/`. No modifications to `README.md`, `LICENSE`, or existing workflows.

- [ ] **Step 3: Push the branch**

```bash
git push -u origin worktree-chore+contributing-workflow
```

Or, if the maintainer renamed the branch before pushing:

```bash
git branch -m worktree-chore+contributing-workflow chore/contributing-workflow
git push -u origin chore/contributing-workflow
```

- [ ] **Step 4: Open the PR with `gh`**

```bash
gh pr create --base main --title "chore: issue-first collaboration workflow" --body "$(cat <<'EOF'
## Summary

- Adds `CONTRIBUTING.md` at the repo root (produces the **Contributing** tab on the repo home page).
- Adds `docs/TRIAGE.md` for the maintainer-side triage process.
- Adds three GitHub Issue Form templates (Bug, Feature, Question) and a `config.yml` that disables blank issues.
- Adds `.github/pull_request_template.md`.
- Adds two workflows:
  - `label-new-issues.yml` — bootstraps four new labels and auto-applies `needs-triage` to opened issues.
  - `issue-gate.yml` — blocks PRs that aren't linked to a `ready-for-dev` issue (with a `skip-issue-check` override for maintainers).
- See `docs/superpowers/specs/2026-05-28-collaboration-workflow-design.md` for the full design.

## Test plan

After merge, run the checks from the spec's "Testing & verification plan" section on the live repo:

- [ ] Open a throwaway issue via each template — confirm `needs-triage` is auto-applied.
- [ ] Open a PR with no linked issue — confirm gate fails with the sticky comment.
- [ ] Open a PR with `Closes #<N>` where #N has only `needs-triage` — confirm fail.
- [ ] Apply `ready-for-dev` to #N, push an empty commit — confirm gate passes.
- [ ] Apply `skip-issue-check` to a PR with no linked issue — confirm gate passes.
- [ ] Push 3 commits to a PR — confirm only one gate comment exists, edited in place.

## Post-merge (manual, one-time)

- Enable branch protection on `main` and add `gate` (job name in `issue-gate.yml`) to required status checks. See `docs/TRIAGE.md` for the steps.
EOF
)"
```

Expected: `gh` prints the PR URL.

- [ ] **Step 5: Confirm the PR shows the expected file count**

Open the PR URL printed by `gh`. The Files Changed tab should show exactly **9 new files**, all under `CONTRIBUTING.md`, `docs/TRIAGE.md`, or `.github/`.

---

## Spec coverage check (run before declaring the plan complete)

| Spec section | Implementing task |
|---|---|
| `CONTRIBUTING.md` (front-door / Contributing tab) | Task 1 |
| `docs/TRIAGE.md` (maintainer-side) | Task 2 |
| Issue templates (Bug / Feature / Question) + `config.yml` | Task 3 |
| `pull_request_template.md` | Task 4 |
| Labels (`needs-triage`, `needs-info`, `ready-for-dev`, `skip-issue-check`) | Task 5 (bootstrap step) |
| `label-new-issues.yml` workflow | Task 5 |
| `issue-gate.yml` workflow | Task 6 |
| Sticky comment behavior | Task 6 |
| `skip-issue-check` override | Task 6 |
| GraphQL `closingIssuesReferences` query | Task 6 |
| Testing & verification plan (live repo) | Task 7 (deferred to post-merge) |
| Branch protection note | Task 2 (`docs/TRIAGE.md`) + Task 7 (PR body) |

No section of the spec is unimplemented.
