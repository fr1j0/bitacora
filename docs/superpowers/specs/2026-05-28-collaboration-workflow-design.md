# Collaboration Workflow — Issue-First Contributions

**Date:** 2026-05-28
**Status:** Draft (design) — pending review

## Problem

Bitácora is alpha and public. Today the repo has a `LICENSE` and `README.md` but no
`CONTRIBUTING.md`, no issue templates, no PR template, and no automated gate on what gets
proposed. A drive-by contributor can open a PR for anything — scope creep, work that
duplicates a parked idea (e.g. `/improve`, `/spike` — see [No ticket-authoring in
Bitácora](../../../.claude/projects/-Users-fernandocastillo-Projects-bitacora/memory/project_bitacora-no-ticket-authoring.md)),
or work the maintainers would have redirected.

The maintainers want a triage step **before** code gets written: every change starts as
an issue, gets reviewed for fit, and only after a maintainer applies an approval label
can a topic branch be opened. PRs without an approved issue should not merge.

## Goal

Establish a documented, lightly-automated **issue-first contribution flow**:

1. Contributor opens an issue via one of three templates (Bug / Feature / Question).
2. New issues are auto-labeled `needs-triage`.
3. A maintainer triages: closes, requests info (`needs-info`), or approves
   (`ready-for-dev`).
4. The contributor branches `<type>/issue-<N>-<slug>` off `main`, opens a PR with
   `Closes #<N>` in the body.
5. A GitHub Action verifies the PR is linked to an issue with `ready-for-dev` and fails
   the check otherwise. Maintainers can override with a `skip-issue-check` label for
   trivial fixes (typos, CI, docs-only).

`CONTRIBUTING.md` at the repo root acts as the front door — GitHub renders it as a
**"Contributing"** tab on the repo home page (alongside README and MIT license) and
links to it from the New Issue and New Pull Request screens.

## Prerequisites

- GitHub Actions enabled on the repo (already true — `test.yml` exists).
- `${{ secrets.GITHUB_TOKEN }}` with `pull-requests: write`, `issues: write`,
  `contents: read` scopes on the relevant workflows (default token scopes cover this
  when the workflow `permissions:` block declares them explicitly).
- No new third-party Actions or apps; everything uses `actions/checkout`, `gh` (the
  GitHub CLI, preinstalled on `ubuntu-latest`), and the GraphQL API.

## Non-goals

- **No branch-protection configuration.** That's a one-time admin action in the GitHub
  UI by the repo owner. The spec documents *that* it should be configured and what
  required checks to set, but doesn't try to script it.
- **No Code of Conduct file.** Worth adding eventually but out of scope here.
- **No Discussions enablement.** Optional follow-up; if enabled later, the Question
  template's `config.yml` can redirect there.
- **No changes to existing files.** `README.md`, `LICENSE`, and the existing
  `test.yml` workflow are not modified.
- **No bot installation** (no Welcome bot, no Sticky bot). One workflow re-uses a
  marker comment to behave as a sticky-comment without an app.
- **No retroactive triage of past PRs.** The flow applies going forward.

## What gets added

```
CONTRIBUTING.md                                  # the "Contributing" tab
docs/TRIAGE.md                                   # maintainer-side process
.github/
  ISSUE_TEMPLATE/
    config.yml                                   # disable blank issues
    bug_report.yml
    feature_request.yml
    question.yml
  pull_request_template.md
  workflows/
    label-new-issues.yml                         # auto-applies needs-triage
    issue-gate.yml                               # enforces ready-for-dev on PRs
```

## Components

### 1. `CONTRIBUTING.md` — the contract

Audience: a first-time contributor scanning before they open a PR. ~1 page,
plain-language.

Required sections:

- **Before you open a PR, open an issue.** Three template links inline.
- **The triage flow** — a numbered diagram: open issue → maintainer triages → label
  `ready-for-dev` applied → branch & PR.
- **Branching** — `<type>/issue-<N>-<slug>` (e.g. `feat/issue-42-context-meter`,
  `fix/issue-17-empty-ctx`). Off `main`. Never push to `main`.
- **Opening a PR** — must include `Closes #<N>` in the body. The PR will be checked
  automatically; if the linked issue isn't `ready-for-dev`, the check fails and the
  PR can't merge.
- **Maintainer exception** — typo/CI/docs-only fixes from maintainers may carry the
  `skip-issue-check` label and skip the gate.
- **Scope reminder** — link to the `README.md` "What lives where" section and the
  `docs/TRIAGE.md` scope notes (so contributors self-screen on out-of-scope work like
  `/improve` or `/spike`).
- **License footer** — "By contributing you agree the work is MIT-licensed
  (see LICENSE)."

### 2. `docs/TRIAGE.md` — maintainer-side

Audience: maintainers. ~half-page. Sections:

- **Inbox query:** `is:issue is:open label:needs-triage`.
- **Decisions:** for each issue, the maintainer does one of:
  - **Duplicate** → close, link to original.
  - **Out of scope** → close with a short note, link to scope reminder.
  - **Need more info** → add `needs-info`, remove `needs-triage`, ask the question.
  - **Approve** → add `ready-for-dev`, remove `needs-triage`.
- **Scope guardrails:** Bitácora is *status-tracking and continuity*; ticket-authoring,
  `/improve`, `/spike`, and similar are off-limits (linked from CLAUDE memory note).
- **SLA:** aspirational only — best-effort response within ~1 week.
- **Label ownership:** only maintainers apply `ready-for-dev` and `skip-issue-check`.

### 3. Issue templates — GitHub Issue Forms (`.yml`)

GitHub's structured form syntax renders these as fields instead of free text — better
triage signal, fewer half-empty issues.

**`bug_report.yml`** — fields:
- `summary` (textarea, required)
- `repro_steps` (textarea, required, placeholder shows numbered steps)
- `expected_vs_actual` (textarea, required)
- `environment` (textarea, required) — Claude Code version, Atlassian MCP version, OS
- `logs` (textarea, optional)
- `confirmation` (checkboxes, required): "I searched existing issues", "I'm running
  latest `main`"
- `labels`: `bug`, `needs-triage` (auto-applied by template — the workflow in §6 is
  a belt-and-suspenders fallback)

**`feature_request.yml`** — fields:
- `problem` (textarea, required) — "What can't you do today / what's painful?"
- `proposed_solution` (textarea, required)
- `alternatives` (textarea, optional)
- `scope_check` (checkboxes, required): "I've read the
  ['What lives where' section](../README.md) and believe this is within scope
  (status-tracking / continuity)"
- `labels`: `enhancement`, `needs-triage`

**`question.yml`** — fields:
- `goal` (textarea, required) — "What are you trying to do?"
- `tried` (textarea, required) — "What have you tried?"
- `stuck_where` (textarea, required)
- Footer note: "Questions may be converted to a Discussion or closed without triage."
- `labels`: `question`, `needs-triage`

**`config.yml`:**
```yaml
blank_issues_enabled: false
contact_links:
  - name: README — what Bitácora is and isn't
    url: https://github.com/fr1j0/bitacora#what-lives-where--status-vs-scratch
    about: Before opening an issue, skim the scope notes.
```

### 4. `.github/pull_request_template.md`

Renders as the default body for every new PR. Markdown, ~20 lines:

```markdown
## Linked issue
Closes #<!-- issue number -->

<!-- A linked issue with the `ready-for-dev` label is required.
     Maintainers may apply `skip-issue-check` for typo/CI/docs-only PRs. -->

## What & why
<!-- 1-3 sentences. Why this change, not what (the diff shows that). -->

## Test plan
<!-- How you verified this. -->

## Checklist
- [ ] Linked issue is labeled `ready-for-dev` (or this PR is maintainer-only and
      carries `skip-issue-check`)
- [ ] Branch name follows `<type>/issue-<N>-<slug>`
- [ ] Tests added/updated where reasonable
```

### 5. Labels

| Label | Color (hex) | Meaning | Applied by |
|---|---|---|---|
| `needs-triage` | `#fbca04` (yellow) | New issue, awaiting maintainer review | Auto (workflow + template) |
| `needs-info` | `#d4a017` (orange) | Maintainer asked for more info; waiting on reporter | Maintainer |
| `ready-for-dev` | `#0e8a16` (green) | Triaged and approved; safe to start coding | Maintainer |
| `skip-issue-check` | `#cccccc` (gray) | PR exempt from issue-gate (typo/CI/docs-only) | Maintainer |

Existing stock labels (`bug`, `enhancement`, `documentation`, `question`,
`good first issue`, `help wanted`, `duplicate`, `invalid`, `wontfix`) stay unchanged.

**Bootstrap:** `label-new-issues.yml` includes an idempotent setup step on first run
(`gh label create … || true` for each new label) so no manual repo setup is required.
The step is a no-op after the labels exist.

### 6. `.github/workflows/label-new-issues.yml`

Trigger: `on: issues: types: [opened]`.

Two steps:

1. **Bootstrap labels** (idempotent). Creates `needs-triage`, `needs-info`,
   `ready-for-dev`, `skip-issue-check` with the colors above. `|| true` so re-runs
   don't fail when labels exist.
2. **Apply `needs-triage`** to the opened issue:
   `gh issue edit "$ISSUE_NUMBER" --add-label needs-triage`.

`permissions: { issues: write }`. Uses `${{ secrets.GITHUB_TOKEN }}`.

### 7. `.github/workflows/issue-gate.yml`

Trigger: `on: pull_request_target: types: [opened, synchronize, edited, reopened, labeled, unlabeled]`.

(`pull_request_target` rather than `pull_request` so the workflow runs with the
target repo's permissions on PRs from forks. `pull_request` triggered from a fork
gets a read-only `GITHUB_TOKEN`, which would block posting the sticky comment;
`pull_request_target` gets a write token. The workflow does *not* check out PR
head code, so this is safe — see Risks.)

`permissions: { pull-requests: write, issues: read, contents: read }`.

Single job `gate`, on `ubuntu-latest`, ~50 lines of bash and `gh api graphql`:

1. **Override check** — if PR carries `skip-issue-check` label, post (or update) the
   sticky comment with `✅ Skipped — maintainer override` and `exit 0`.
2. **Find linked closing issues** via GraphQL:
   ```graphql
   query($owner: String!, $name: String!, $number: Int!) {
     repository(owner: $owner, name: $name) {
       pullRequest(number: $number) {
         closingIssuesReferences(first: 20) {
           nodes { number, labels(first: 20) { nodes { name } } }
         }
       }
     }
   }
   ```
   This is the *same* relation GitHub uses for "Closes #N / Fixes #N / Resolves #N"
   in PR bodies and the manually-linked-issues UI.
3. **Fail if no linked closing issues** — exit 1 after posting the sticky comment
   with "No linked issue found. Please add `Closes #<N>` to your PR body or link an
   issue in the sidebar. See CONTRIBUTING.md."
4. **Fail if no linked issue carries `ready-for-dev`** — exit 1 after posting the
   sticky comment with "Linked issue(s) #X, #Y are not yet approved for coding. A
   maintainer needs to triage and apply `ready-for-dev`."
5. **Pass** — exit 0 after posting/updating the sticky comment with "✅ Linked to
   approved issue(s) #X."

**Sticky comment:** the workflow searches existing PR comments for a marker line
(`<!-- bitacora-issue-gate -->`) and either edits that comment in place or posts a new
one. Prevents comment spam on each push.

**Becomes a required check** once a maintainer enables branch protection on `main`
and selects `gate` as required — but that's a manual one-time admin step, documented
in `CONTRIBUTING.md` and `docs/TRIAGE.md`, not done by this change.

## Edge cases (decided)

- **PR title-only `Closes #N`** — works. GraphQL `closingIssuesReferences` reads PR
  *body* and the linked-issues sidebar, **not the title.** `CONTRIBUTING.md` says
  "in the body" and the PR template seeds it there.
- **Multiple linked issues** — pass if **at least one** carries `ready-for-dev`.
  Common case: a feature PR closes the main feature issue and a follow-up bug issue;
  only the main issue needs approval.
- **Issue's label changes mid-PR** — the workflow's `labeled`/`unlabeled` triggers
  fire when the *PR itself* is (un)labeled, not when the linked issue's labels
  change. **Open gap:** applying `ready-for-dev` to the linked issue does not
  automatically re-run the gate on open PRs. Workaround: a maintainer pushes an
  empty commit, re-opens the PR, or applies-and-removes any PR label to retrigger.
  Acceptable for v1; the "Future enhancements" section captures the proper fix.
- **PR opened from a fork** — `pull_request_target` runs with repo secrets, which is
  why we use it. The workflow does *not* check out PR code; it only queries the
  GitHub API. Safe.
- **Issue deleted after PR opens** — GraphQL returns zero linked issues; gate fails
  with the standard "no linked issue" message. Acceptable.
- **Closes #N references an issue in another repo** — GraphQL only returns
  intra-repo links here, so cross-repo refs are ignored by the gate (i.e. they don't
  count as "linked"). If someone needs a cross-repo close, they file a local issue
  too.
- **Draft PRs** — same gate applies. Failing gate on a draft is fine; it just
  signals what's needed before "ready for review."

## Testing & verification plan

After implementation, before declaring done, the maintainer runs through these on
the live repo (or a fork for the destructive ones):

1. **Issue auto-labeling** — open a throwaway issue via each template; confirm
   `needs-triage` appears (plus the template's own label like `bug`).
2. **Gate fails on no linked issue** — open a PR with no `Closes #N`; the workflow
   posts the sticky comment and the check is red.
3. **Gate fails on unapproved issue** — open a PR with `Closes #<N>` where #N is
   labeled `needs-triage` only; check is red, sticky comment names the issue.
4. **Gate passes after approval** — apply `ready-for-dev` to #N, push an empty
   commit (`git commit --allow-empty -m "retrigger"`) to re-run; check goes green
   and sticky comment updates.
5. **Override** — apply `skip-issue-check` to a PR with no linked issue; check
   passes immediately.
6. **Sticky comment stays singular** — push three commits to the PR; verify only
   *one* gate comment exists on the PR, edited in place.

## Risks

- **Workflow-permissions friction.** `pull_request_target` plus PR-write permissions
  is more powerful than `pull_request`. The workflow is read-only against the repo
  contents (no checkout, no script execution from the PR head); the risk surface is
  bounded to the GraphQL query and the sticky-comment post. Documented in a
  comment at the top of `issue-gate.yml`.
- **Maintainer-bottleneck.** All approvals route through the maintainer's
  `needs-triage` inbox. The `docs/TRIAGE.md` SLA acknowledges this is best-effort;
  not a system-design problem to solve here.
- **Stale `ready-for-dev`.** A long-approved issue may drift out of relevance.
  Out of scope to detect; maintainers can remove the label.
- **Label-color drift.** If a maintainer hand-edits a label color, the bootstrap
  step's `|| true` won't reset it. Acceptable.

## Future enhancements (parked, not in this spec)

- Auto-retrigger the gate when a *linked issue*'s labels change (an `issues:
  [labeled, unlabeled]` workflow that finds all open PRs referencing the issue and
  re-runs `gate` on each).
- Optional `welcome-new-contributor` workflow that comments on first issues/PRs.
- `CODE_OF_CONDUCT.md` (adds a "Code of conduct" tab).
- `SECURITY.md` (adds a "Security policy" tab; routes vuln reports privately).
- Enable Discussions and convert `question.yml` into a `config.yml` redirect.
- Stale-issue Action to auto-close `needs-info` issues after N weeks of silence.
