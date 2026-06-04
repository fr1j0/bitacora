# Issue-gate: enforce owner-applied approval labels

**Issue:** #92
**Date:** 2026-06-04
**Status:** Approved (design)

## Problem

`.github/workflows/issue-gate.yml` passes a PR when a linked closing issue carries
`ready-for-dev`, or when the PR carries `skip-issue-check`. It checks each label's
**presence**, not **who applied it**. `docs/TRIAGE.md` records this as a social contract
only: *"the gate workflow only trusts maintainer labels in practice; we don't hard-enforce
this."*

Consequence: anyone who can apply labels — a write/triage collaborator, or an automated
agent acting with such a token — can self-grant `ready-for-dev`/`skip-issue-check` and turn
the `gate` check green on their own PR, defeating the owner-approval intent. (External /
read-only contributors cannot apply labels, so the public is not exposed; the gap is
write-collaborators and agents.) A real instance occurred during v0.4.0/v0.4.1 work, where
an agent self-applied approval labels on its own PRs — technically green, but self-approved.

## Goal

The approval signal must count only when the label was applied by the **repo owner**
(`github.repository_owner`, i.e. `@fr1j0`). A label that is present but was applied by
anyone else — or present with no recorded `labeled` event — fails the gate.

This is deliberately **owner-only**, not a general maintainer/permission model. The owner
chose the simplest enforcement that matches the actual policy ("every PR needs my personal
approval"). No collaborator-permission API, no allowlist file, no extra token scope.

## Non-goals

- Multi-maintainer support. If a co-maintainer is ever added, their approvals will not
  count until the owner check is extended. This is an accepted trade-off, called out in
  code and docs so it is discoverable.
- Any product behaviour change. This is repo governance / CI only.
- Changing GitHub's native review requirement. PR merge already requires a code-owner
  approving review (`CODEOWNERS` is `* @fr1j0`, branch protection requires 1 code-owner
  review). This spec only makes the `gate` check itself honest; it does not touch reviews.

## Current behaviour (baseline)

`issue-gate.yml` runs on `pull_request_target` with `pull-requests: write`, `issues: read`,
`contents: read`. Its inline bash:

1. If the PR carries `skip-issue-check` → post sticky "Gate skipped", `exit 0`.
2. Else GraphQL-query `closingIssuesReferences` (first 20) with each issue's `labels`.
3. No linked issue → fail.
4. At least one linked issue carries `ready-for-dev` → pass; else fail.

Both decisions test label **presence** only.

## Design

### Mechanism: identify the actor, compare to owner

The only new capability required is knowing **who** applied a present label. GitHub records
this as a `LabeledEvent` in the issue/PR timeline.

Add a bash helper to the inline script:

```
# applied_by_owner <issue-or-pr-number> <label-name>
#   echoes the login of the actor of the LATEST matching LABELED_EVENT,
#   or empty if no such event exists.
# Returns 0 (owner-applied) iff that login == $OWNER.
```

Implementation notes:

- The actor is read from `timelineItems(itemTypes: [LABELED_EVENT])`, taking the **latest**
  (max `createdAt`) event whose `label.name` matches. Latest-wins handles the
  remove-then-re-add case correctly: the currently-present label is the one most recently
  added.
- `$OWNER` is `github.repository_owner` (already exported in the workflow env as `OWNER`).
- **Owner login comparison is exact.** No permission lookup, no `collaborators/permission`
  call — so no additional token scope is needed; `issues: read` already authorises reading
  issue/PR timeline events.

### Fail-closed rules

A label is treated as **not** owner-approved when:

- the latest `LABELED_EVENT` actor login != `$OWNER`, **or**
- the label is present but **no** `LABELED_EVENT` is found for it (unverifiable origin).

Both cases fail the gate with a clear sticky comment. There is no infra-fail branch: with
no permission API, the only API call is the timeline read, which shares the existing
GraphQL request and the existing failure-on-empty-response behaviour.

### Flow changes

The two decision points change from "present?" to "present **and** owner-applied?".

1. **`skip-issue-check` (PR override).**
   - Was: present on PR → pass.
   - Now: present on PR **and** `applied_by_owner <PR> skip-issue-check` → pass.
   - Present but not owner-applied → fall through to the normal linked-issue path (the PR is
     not skipped; it must then satisfy the `ready-for-dev` requirement) **and** surface a
     note in the sticky that the skip label was ignored because it was not owner-applied.
     *(Decision: a non-owner skip label is ignored, not a hard fail, so a contributor
     mislabelling does not block a PR that is otherwise legitimately linked to an
     owner-approved issue.)*

2. **`ready-for-dev` (linked issue approval).**
   - Was: at least one linked issue carries `ready-for-dev` → pass.
   - Now: at least one linked issue carries `ready-for-dev` **that was applied by the owner**
     → pass. An issue whose `ready-for-dev` was applied by a non-owner counts as
     **unapproved** for gate purposes.
   - The "at least one" semantics are preserved: multiple linked issues, any one
     owner-approved issue passes the gate.

### Failure messaging

Extend the existing sticky comments:

- **No owner-approved linked issue** (issues linked, label present but non-owner-applied or
  absent):
  > Gate failed — linked issue(s) #N are not approved by the repo owner.
  >
  > The `ready-for-dev` label must be applied by @fr1j0 (the repo owner). A label applied by
  > anyone else does not count. See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md).

  When a specific actor is known, name it: *"`ready-for-dev` on #N was applied by @actor, not
  the repo owner."*

- **`skip-issue-check` ignored:** prepend a line to whatever sticky is posted:
  > Note: `skip-issue-check` was ignored — it was not applied by the repo owner.

The existing "no linked issue" and "gate passed" messages are unchanged except that
"approved" now means owner-approved.

### GraphQL shape

Extend the single existing query rather than adding round-trips. Per linked issue, fetch
`labels` (existing) plus `timelineItems(first: 100, itemTypes: [LABELED_EVENT])` with
`label { name }`, `actor { login }`, `createdAt`. Add a sibling query for the PR's own
`timelineItems` to resolve the `skip-issue-check` actor (the PR is queried via
`pullRequest(number:)`, which exposes `timelineItems` and `labels`).

`first: 100` timeline events per issue is a pragmatic cap; issues in this repo do not
approach that many label events. If an issue ever exceeds it, latest-wins still holds for
the page returned in `createdAt` order — but note this cap in a code comment so a future
maintainer knows the bound exists (no silent truncation).

## Components touched

| File | Change |
|---|---|
| `.github/workflows/issue-gate.yml` | Add timeline fields to the GraphQL query; add `applied_by_owner` helper; gate both label paths on owner-applied; extend sticky messages. |
| `docs/TRIAGE.md` | Rewrite "Label ownership" — the gate now **enforces** owner-applied approval; drop the "we don't hard-enforce this / social contract" caveat. Note the owner-only limitation. |

No new scripts, no test-fixture harness (consistent with the existing gate, which has no
unit tests and is validated by running on real PRs). Validation is by shellcheck + the
gate dogfooding on its own PR (#92's `ready-for-dev` is owner-applied, confirmed).

## Testing / validation

- `shellcheck` passes on the workflow's shell (run locally; the gate's run-block is bash).
- **Dogfood:** this change's own PR is `Closes #92`; #92 carries `ready-for-dev` applied by
  @fr1j0, so the hardened gate must report **pass** on this PR. That is the live positive
  test.
- **Negative path** is asserted by inspection: a label whose latest `LABELED_EVENT` actor
  is not `$OWNER` takes the fail branch. (A fully automated negative test would require
  mocking `gh api` / GraphQL responses — out of proportion for a gate that has never had a
  unit harness; logged here as a deliberate scope choice.)

## Risks

- **Owner-only brittleness on team growth** — documented non-goal; the `applied_by_owner`
  helper is the single place to extend to a maintainer set later.
- **Timeline page cap (`first: 100`)** — bounded and commented; not a real limit for this
  repo's issues.
- **`pull_request_target` surface** — unchanged. The workflow still reads metadata only and
  does not check out PR head code; the new timeline read uses the same token and scopes.

## Out of scope

- Co-maintainer / permission-based trust.
- Touching branch protection or the code-owner review requirement.
- Release/version bump (handled separately per the release runbook if the owner wants this
  in a tagged version).
