# Collision detection on `/handoff` — design

**Date:** 2026-06-03
**Status:** Approved (brainstorm) — pending spec review → implementation plan
**Surface:** `bitacora:session-handoff` skill (`/bitacora:handoff`, `/bit:handoff`)

## Problem

`/handoff` writes a `[CTX]` comment per touched ticket without checking whether
someone else added context to that ticket while the current session was underway.
In a shared Jira, a teammate's recent `[CTX]` can be silently buried under a new
handoff that never accounted for it — the exact loss-of-context failure Bitácora
exists to prevent, occurring on its own write path.

The skill is deliberately stateless ("reconstruct — no hook/state"), so there is no
record of "what the latest `[CTX]` was when this session started." The design must
detect collisions without introducing persistent per-ticket baseline state.

## Detection signal (stateless, author-based)

A collision fires for a ticket when **all three** hold:

1. The ticket's **most-recent `[CTX]`** is authored by **someone other than the
   current Atlassian user** — identity resolved once per handoff via
   `atlassianUserInfo` → `accountId`.
2. That `[CTX]` is **newer than the current user's own most-recent `[CTX]`** on the
   same ticket, or the current user has no prior `[CTX]` on it (a takeover).
3. It falls within the **`collision_window`** (default **48h**).

Reads as: *"someone added context after mine, within the last 48h, that I haven't
folded in."* All inputs (comment author `accountId`, creation timestamp, body) come
from the `getJiraIssue` comment read the skill can already perform — no new state
file.

**Single-user case:** when every `[CTX]` on the ticket is authored by the current
user, the check never fires — zero added noise or cost for solo dogfooding.

## Where it hooks

- **Step 2 (draft `[CTX]`)** — today's *optional* continuity-read is promoted to a
  **performed** read that also captures the latest `[CTX]`'s author `accountId` and
  creation timestamp (not just its text). Still lenient: if the read fails or the MCP
  is absent, the check is skipped silently and the handoff proceeds.
- **Step 4 (confirm gate)** — the warning surfaces here, riding the existing gate. No
  new earlier prompt.

## Confirm-gate presentation

Per affected ticket, an inline flag with the colliding context excerpted:

```
[2] TESTING-15  → [CTX] drafted   ⚠ collision
    Latest [CTX] is by Alice Méndez, 3h ago (after your last update):
      Status: Auth flow blocked on token refresh — see PR #214
      Next:   Rotate the staging secret, then re-run e2e
    [merge] re-draft threading Alice's context · [proceed] write mine as-is · [skip]
```

Per-ticket actions:

- **merge** — re-draft the current user's `[CTX]` incorporating the colliding
  `Status`/`Next` (re-reads the full colliding comment first, then threads it into the
  draft). **In v1.**
- **proceed** — write the drafted `[CTX]` as-is (user has judged the overlap benign).
- **skip** — do not write this ticket's `[CTX]`.

**Warn-only, never blocking.** Consistent with the skill's "show everything, user
filters at the gate" model and its no-nag / local-only adaptivity. Other tickets in
the same handoff are unaffected by one ticket's collision.

## Failure / edge behavior

- **MCP absent / comment read fails / site unresolvable** — skip the check silently;
  handoff proceeds exactly as today. Collision detection never blocks a handoff.
- **All `[CTX]` authored by the current user** — never fires.
- **Same human via a second Atlassian account** — possible false-positive; acceptable
  because the outcome is a warn-only gate the user can dismiss with **proceed**.
- **Ticket has prior comments but none in `[CTX]` format** — no `[CTX]` baseline; the
  "newer than my last `[CTX]`" clause treats the user as having none, so a teammate's
  in-window `[CTX]` still warns (takeover path).
- **Multiple teammates' `[CTX]` after my last** — v1 detects and displays only the
  **single most-recent** colliding `[CTX]`, and **merge** threads that one. Folding the
  full set of intervening `[CTX]` is a follow-on; the most-recent is the highest-signal
  and keeps the gate readable.

## Scope (v1)

**`/handoff` write path only** — that is where context gets buried. A passive
"newer context exists" heads-up in `/resume` and `/status` is a natural follow-on and
is **explicitly out of v1 scope** (YAGNI) to keep the change tight.

## Implementation surface

- Edit `plugins/bitacora/skills/session-handoff/SKILL.md` — steps 2 and 4, and the
  Configuration block.
- New config key `collision_window` (default `48h`) in the handoff Configuration
  block, alongside `session_ticket_tracking` / `jira_cloud_id`. Same override files
  (`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`).
- A small, testable helper `plugins/bitacora/scripts/collision-check.sh` that takes the
  current-user `accountId`, the latest-`[CTX]` author `accountId` + timestamp, the
  current user's last-`[CTX]` timestamp (or none), and `now` + window, and returns
  fire / no-fire. Mirrors the repo's existing testable-helper pattern
  (`since-window.sh`, `validate-ctx.sh`) so it earns a fixture suite rather than living
  only as skill prose. Pure arithmetic on UTC epoch seconds — no GNU/BSD `date`
  divergence (follow the `since-window.sh` precedent).

## Testing

- **`collision-check.sh` fixture suite** — fires/no-fires across: author≠me in-window,
  author≠me out-of-window, author=me, no prior self-`[CTX]` (takeover), missing
  timestamps. Wired into CI alongside the existing helper suites.
- **Manual acceptance** (live MCP render) — added to `MANUAL-ACCEPTANCE.md`: a real
  two-account collision, the merge re-draft, proceed, skip, and the no-collision
  (solo) no-op.

## Out of scope / follow-ons

- Passive collision heads-up in `/resume` and `/status`.
- Persistent seen-marker state (the precise "changed since I last looked" signal) —
  the stateless author-based heuristic is sufficient for v1; revisit only if
  false-positive/negative rates warrant it.
