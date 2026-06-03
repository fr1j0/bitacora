# Staleness signal — design

**Date:** 2026-06-03
**Status:** Approved (brainstorm) — pending spec review → implementation plan
**Surfaces (v1):** `bitacora:session-resume` and `bitacora:session-status`

## Problem

A ticket's latest `[CTX]` can fall *behind reality*: the ticket gets a status
transition, new comments, or linked PR/commit activity **after** the last `[CTX]` was
written. A reader who rehydrates from (`/resume`) or summarizes (`/status`) that `[CTX]`
trusts a status that no longer reflects the ticket. Nothing currently flags this drift.

This is **distinct** from the existing `/next` inactivity-`stale` (ticket `updated` older
than `next.stale_days`, default 30) — that flags tickets where *nothing* has happened.
Staleness here is the opposite: *something happened after your context*.

## The signal: drift with a grace window

A ticket's latest `[CTX]` is **stale (behind)** when:

```
ticket.updated − latest_[CTX].created  >  staleness_grace   (default 2d)
```

- **Drift-based**, not age-based — it means "the ticket moved after your last handoff."
- The **grace window** is the noise filter: a trivial same-day field edit (relabel,
  reassign) won't trip it; the ticket must have been active ≥ `staleness_grace` past the
  `[CTX]`. Default `2d` absorbs normal edit churn and weekends.
- **Cheap:** both timestamps are already fetched — `/status` and `/next` JQL order by
  `updated`, and the `[CTX]` read yields each comment's `created`. No extra Jira call.
- **Magnitude:** the drift in whole days (`floor((updated − created) / 86400)`) is
  reported as `behind Nd` so renders can show *how far* behind.

**Not stale:**
- A ticket with **no `[CTX]`** — that is a separate "no context" state (existing coverage
  bucket / `/resume`'s "Last touched: never"), never reported as stale.
- `ticket.updated ≤ latest_[CTX].created` — the `[CTX]` is the most recent activity →
  `fresh`.

## Shared core: a testable helper

`plugins/bitacora/scripts/staleness-check.sh` — pure arithmetic on UTC epoch seconds,
mirroring `collision-check.sh` / `since-window.sh`:

```
staleness-check.sh --ctx-epoch <N> --updated-epoch <N> [--grace <token>]
  --ctx-epoch     creation time (epoch s) of the latest compliant [CTX].
  --updated-epoch the ticket's `updated` time (epoch s) from the Jira API.
  --grace         drift tolerance as <N>h | <N>d (default 2d).
Output : "fresh", or "stale <D>d" where D = floor((updated−ctx)/86400). exit 0.
Errors : missing/invalid args -> reason on stderr, exit 2.
```

Logic: `updated ≤ ctx` → `fresh`; else `drift = updated − ctx`; `drift > grace_seconds`
→ `stale <floor(drift/86400)>d`, else `fresh`. Unit-tested + CI-wired.

## Surface 1: `/resume` (rehydration banner)

`/resume` is the strongest home — it rehydrates the agent *from* the latest `[CTX]`.

- **Step 3 (read the ticket):** the existing `getJiraIssue` call must also request the
  `updated` field (it already requests comments). Capture `ticket.updated`.
- **Step 4 (synthesize the briefing):** after computing `latest_[CTX].created` (already
  done for the `Last touched:` line), call `staleness-check.sh`. If it returns
  `stale Nd`, prepend a one-line banner to the briefing, directly under the header:

  ```
  Resuming TESTING-15 — "OAuth refresh"  (Jira status: In Progress)
  ⚠ This context may be behind — the ticket was updated 4d after this [CTX];
    re-check the ticket before relying on it.
  Last touched: 6 days ago (2026-05-28)
  ...
  ```

  Advisory only — never blocks the briefing. If the ticket has no `[CTX]` (the existing
  "Last touched: never" path), the check is skipped entirely.

## Surface 2: `/status` (freshness marker)

- **Single-ticket render:** add one line under the summary —
  `Freshness: behind 4d (ticket updated after the latest [CTX])` when stale; omit the
  line entirely when fresh (no positive "fresh" noise).
- **Multi-ticket digest / `--mine` / aggregate index:** append a `⚠ behind Nd` marker to
  each stale ticket's per-ticket index entry (the `By ticket:` / `By child:` lines),
  alongside the existing key + status. Fresh tickets get no marker.
- Composes with every existing lens (`--for-*`, `--blocked`, `--standup`); the marker is
  orthogonal to *what* each lens surfaces. `--standup` already reasons about movement
  windows, so it shows the marker but does not change its own selection logic.

## Configuration

`staleness_grace` is used by more than one command, so it lives **top-level** in the
`bitacora:jira-comment-format` Configuration block (beside `project_key_pattern`), not in
a single command's namespace. Same override files
(`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`):

```yaml
staleness_grace: 2d             # drift tolerance (<N>h | <N>d) before a [CTX] is "behind"
```

## Failure / edge behavior

- **No `[CTX]` on the ticket** → never stale (separate "no context" state).
- **`updated ≤ created`** (the `[CTX]` is the latest activity, or clock skew) → `fresh`.
- **Missing `updated` field** (should not happen; Jira always sets it) → skip the check
  silently; render as if fresh.
- Read-only and advisory throughout — staleness never blocks a briefing or a summary.

## Scope (v1) and deferrals

**In v1:** the shared helper + `/resume` banner + `/status` marker.

**Deferred (documented):**
- **`/next`** — already carries an inactivity-`stale` tail; introducing a second, opposite
  "stale" (drift) meaning in the same render needs wording care. Fast-follow once the
  `/resume` + `/status` phrasing is proven in use.
- **statusline** — cannot do a synchronous Jira read (the reason it never hangs). A
  local-cached staleness marker (written by the last `/status` / `/resume` / `/handoff`)
  is a separate design.

## Testing

- **`staleness-check.sh` fixture suite** — `fresh` (updated ≤ ctx), `fresh` (drift within
  grace), `stale` at the grace boundary ±1s, magnitude rounding, `<N>h` and `<N>d` grace
  tokens, and arg-validation errors. CI-wired alongside the existing helper suites.
- **Manual acceptance** — added to `MANUAL-ACCEPTANCE.md`. Unlike collision detection this
  is **trivially solo-testable**: write a `[CTX]`, edit the ticket a few days later (or
  inject the timestamps), run `/resume` and `/status`, confirm the banner/marker appear,
  and confirm a fresh ticket shows neither.
