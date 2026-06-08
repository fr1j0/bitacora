# `/handoff` self-collision guard — design

**Date:** 2026-06-08
**Status:** approved (brainstorm)
**Issue:** [#100](https://github.com/fr1j0/bitacora/issues/100)
**Scope:** `plugins/bitacora/scripts/collision-check.sh`, `skills/session-handoff`,
manual-acceptance.

## Problem

`/handoff` writes `[CTX]` via `addCommentToJiraIssue`, which is **append-only** — every
invocation posts a new comment. The existing collision detection (#94, `collision-check.sh`)
only fires for a **teammate's** `[CTX]`: it reports a collision iff `latest_author != me`.
When the most-recent `[CTX]` is the current user's **own**, the check prints `clear` and
nothing warns. Re-running `/handoff` on the same ticket in quick succession therefore stacks
near-identical `[CTX]` comments by the same author. It doesn't corrupt reads (`/resume`,
`/status`, `/digest` use the *latest* `[CTX]`), but it clutters the ticket's `[CTX]` trail —
which undercuts the trail's value for `/digest --standup` and per-ticket history.

(Only the Jira side accumulates; the local Remember scratch is already overwritten, not
stacked.)

## Decision

A **self-collision guard** at the same confirm-before-write gate, symmetric to the teammate
collision path (#94). Warn-only — it never blocks the gate or the other tickets. First cut is
a **time-window** check; content/trivial-diff detection and in-place `[CTX]` edit are
deferred (see *Out of scope*).

## Mechanism — `--self` mode in `collision-check.sh`

Self-collision is the mirror of the teammate rule on the same inputs, so it lives in the same
tested helper behind a `--self` flag rather than a duplicate script.

- **Default mode (unchanged):** report `collision` iff
  `latest_author != me AND latest_epoch > mine_epoch (or mine omitted) AND latest_epoch >= now − window`.
- **`--self` mode (new):** report `collision` iff
  `latest_author == me AND latest_epoch >= now − window`.
  `--mine-epoch` is irrelevant in self mode — when the latest `[CTX]` is mine, that *is* my
  recent self-handoff.

The `--self` flag reuses the existing arg parsing, the `<N>h`/`<N>d` window-token resolution,
and the injectable `--now` (deterministic tests). Output contract unchanged: prints
`collision` or `clear`, exit 0; invalid args → stderr + exit 2.

## Handoff flow (`session-handoff` SKILL.md)

The existing continuity-read/collision step already resolves the current user (`me` via
`atlassianUserInfo`) and extracts the ticket's most-recent `[CTX]` author + `created` epoch
and the user's own most-recent `[CTX]` `created`. The teammate and self checks are **mutually
exclusive** on *whose `[CTX]` is latest*, so it remains **one decision per ticket**:

- If `latest_author == me` → run `collision-check.sh --self --me <id> --latest-author <id>
  --latest-epoch <epoch> --window <self_handoff_window>`. If `collision` → flag the ticket
  **`⚠ recent self-handoff`** for the gate.
- Else → the existing teammate check (`--window <collision_window>`) → `⚠ collision`
  (unchanged).

**Lenient throughout** (same as #94): if the MCP is absent, `me` can't be resolved, or there
is no prior `[CTX]`, skip the self-check silently and draft as normal — it never blocks a
handoff.

## Gate render (step 4)

A new marker variant **`⚠ recent self-handoff`**, symmetric to the existing `⚠ collision`
block. For a flagged ticket, show the age of the user's own last `[CTX]` and the window, e.g.:

```
[2] PROJ-5678  (branch fix/PROJ-5678-flaky-test)       → [CTX] drafted   ⚠ recent self-handoff
      Your own [CTX] here is 18m ago (within the 2h self-handoff window).
      [append] write this [CTX] anyway · [skip] don't write this ticket
```

Per-ticket actions (warn-only — never blocks the gate or other tickets):
- **append** → write the drafted `[CTX]` as normal (you've judged the second handoff
  legitimate).
- **skip** → do not write this ticket's `[CTX]`.

This composes with the existing `Approve all` / `Review individually` / `Skip specific` /
`Cancel` gate choices; a self-flagged ticket simply carries the extra marker + actions, like a
teammate-collision ticket does.

## Configuration

New key in the handoff Configuration block, next to `collision_window`:

```yaml
self_handoff_window: 2h   # flag a re-handoff when your own latest [CTX] on the ticket is newer
                          # than this (<N>h | <N>d). Default 2h — catches rapid re-runs without
                          # nagging a legitimate end-of-day second handoff.
```

## Testing

- **`test-collision-check.sh`** — add `--self`-mode cases (deterministic via `--now`):
  - latest == me, recent (within window) → `collision`.
  - latest == me, stale (outside window) → `clear`.
  - latest == me, exactly at the window boundary → boundary behavior matches the default
    mode's `>= now − window`.
  - latest != me under `--self` → `clear` (self mode only fires for one's own latest).
  - existing default-mode cases continue to pass unchanged (no regression).
- **Manual acceptance** — one item: re-run `/handoff` on a ticket within 2h of your own last
  `[CTX]` → gate shows `⚠ recent self-handoff` + append/skip; `append` writes, `skip` doesn't;
  a handoff hours later (outside the window) shows no marker.

## Files

- `plugins/bitacora/scripts/collision-check.sh` — add `--self` mode.
- `plugins/bitacora/scripts/test-collision-check.sh` — self-mode cases.
- `plugins/bitacora/skills/session-handoff/SKILL.md` — self-check branch in the
  continuity/collision step; `⚠ recent self-handoff` gate marker + actions; `self_handoff_window`
  in Configuration.
- `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` — self-collision item.

## Out of scope (per issue #100)

- **Trivial/content-diff detection** — flagging only when the new draft is *substantively*
  close to the prior `[CTX]`. A larger lift; time-window is the first cut. Follow-up.
- **In-place `[CTX]` update** — editing the prior agent comment instead of appending. Changes
  `[CTX]` from append-only to editable, which interacts with the trail/history model and the
  staleness signal (#97); needs its own design decision. Default stays warn + append/skip.
