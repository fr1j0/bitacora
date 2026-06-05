# `--standup` day-bucketed render — design

**Date:** 2026-06-05
**Status:** approved (brainstorm)
**Scope:** `plugins/bitacora/skills/session-status` (`--standup` query lens only)

## Problem

The `--standup` query lens currently dumps every ticket that moved into a single
flat `Moved:` block, with no sense of *when* within the window each thing happened:

```
Standup — since 1d · 4 tickets (3 reporting, 1 no [CTX])

Moved:
- DATA-77 "Feature store migration" — In Progress
    Did: cut over the read path to the new store; backfill verified
    Next: enable dual-write, monitor lag
    ⚠ drift PSI could exceed threshold under May traffic
No movement: AUTH-12, UI-30
```

A standup reads more naturally as a chronological narration: **what got done on the
previous worked day → what's happening today.**

## Design

### Buckets & ordering

Two buckets, rendered **past-first**:

1. **Past bucket** — in-window `[CTX]` whose `created` is *before* today's UTC midnight.
2. **Today** — in-window `[CTX]` whose `created` is *at/after* today's UTC midnight.

Empty buckets are omitted (today-only → only `Today`; past-only → only the past
section). Within a bucket, entries sort by that bucket's `[CTX]` `created` **descending**
(most recent work first).

### Past-bucket header (data-driven, weekend-aware)

Computed from the distinct UTC days actually present in the past bucket:

- one day, and it is `today − 1` → **`Yesterday`**
- one day, not yesterday (a weekend / non-working gap sits between) → that **weekday
  name**, e.g. **`Friday`**
- spans multiple days (only possible with a wide `--since Nd`) → **`Earlier`**

This yields `Friday` for a Monday `last-working-day` run and `Yesterday` for a midweek
run, driven by where the `[CTX]` actually lands rather than a hardcoded label. `Today`
is always literally `Today`.

### Multi-day tickets

The `--standup` lens parses **every in-window `[CTX]` per reporting ticket**, not just
the latest. A ticket worked on the previous day *and* today appears in **both** buckets,
each line showing that day's own `Did` / `Next`.

This is **not** extra API calls — `getJiraIssue` already returns all comments; the lens
simply stops discarding the earlier in-window ones. Within a bucket, if a ticket has more
than one `[CTX]`, its latest in that bucket drives the line.

This per-`[CTX]` read is **scoped to `--standup` only**. `--blocked`, the cross-ticket
digest, and every single-ticket / epic path keep the latest-`[CTX]`-authoritative rule
unchanged.

### Render shape

```
Standup — since <token> · <coverage>

<Yesterday | Friday | Earlier>:
- <KEY> "<title>" — <Jira status>
    Did: <Done / Status change from that day's [CTX]>
    Next: <first Next bullet>
    ⚠ <Risk or Blockers one-liner>            (only if present)

Today:
- <KEY> "<title>" — <Jira status>
    Did: …
    Next: …

No movement: <KEY, …>    (reporting tickets with no in-window [CTX]; omit if none)
```

- **Empty result** unchanged: `No [CTX] activity since <token> across <coverage>.`
- **Staleness `· ⚠ behind Nd`** stays per-ticket — printed once, on the ticket's entry
  in the *latest* bucket it appears in (no double-printing).
- **Slack (`--copy-as-slack`)**: ticket-key links on every per-index entry in **both**
  buckets; bucket headers and the `No movement:` tail stay bare. The `--for-*` audience
  lens still selects altitude exactly as today.

### Helper & tests

- Extend `since-window.sh` (or add a small sibling) with a "bucket-meta" mode that, given
  the token + now, emits `cutoff_epoch`, `today_midnight_epoch`, and the previous-day
  weekday name — all pure UTC integer arithmetic, same as today (no GNU/BSD `date`
  divergence). The `Earlier`-vs-single-day decision is made by the skill after bucketing.
- Tests: helper unit cases (midweek → `Yesterday`; Monday → `Friday`; multi-day →
  `Earlier`) + a fixture scenario exercising all four shapes (yesterday-only, today-only,
  a both-buckets ticket, and a weekend gap).
- Update `examples/multi-standup.txt` to the new two-bucket render.

## Carried over unchanged

UTC-day alignment (documented v1 simplification), `--since <token>` semantics, the
coverage line, the no-invention rule, and `--standup` remaining a multi-ticket-only lens.

## Out of scope

Local-time bucketing; per-day buckets beyond two; changing any other lens's read model.
