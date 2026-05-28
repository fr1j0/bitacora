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
