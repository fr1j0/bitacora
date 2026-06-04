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

Bitácora's scope is **status-tracking, continuity, and corpus-grounded sharpening of
existing tickets** — `[CTX]` comments, handoff, resume, status synthesis, morning
ticket-picking (`/bitacora:next`), and ticket rewriting (`/bitacora:improve`). Out of
scope:

- Ticket-authoring (creating new Jira tickets from scratch).
- `/spike` (creating timeboxed exploratory tickets from prompts) — considered and
  dropped; ticket-creation falls outside Bitácora's read-and-sharpen scope.

If an issue proposes any of the above, it's a polite close.

## SLA

Aspirational only: best-effort response within ~1 week. We're an alpha project run by
volunteers.

## Label ownership

Only the repo owner (@fr1j0) approves work. The `ready-for-dev` (on an issue) and
`skip-issue-check` (on a PR) labels **only count when the owner applied them** — the
issue-gate reads each label's `LABELED_EVENT` actor and fails the gate if anyone else
applied it. A non-owner `skip-issue-check` is ignored (the PR falls through to the normal
linked-issue check) rather than blocking. Self-applying these labels as a contributor will
not pass the gate.

This is intentionally owner-only. If a co-maintainer is added later, extend the owner
comparison (`actor == $OWNER`) in `.github/workflows/issue-gate.yml` to accept their login
as well.

## Branch protection (one-time admin)

To enforce the gate, a repo admin must enable branch protection on `main`:

1. Settings → Branches → Add branch protection rule for `main`.
2. Check **Require status checks to pass before merging**.
3. Add **`gate`** (the job name from `.github/workflows/issue-gate.yml`) to required checks.
4. Check **Require a pull request before merging** and disable direct pushes.

Until this is configured, the gate runs but doesn't block merges.
