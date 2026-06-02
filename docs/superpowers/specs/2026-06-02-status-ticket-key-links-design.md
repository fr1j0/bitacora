# Design — Linkify Ticket Keys in Multi-Ticket `/status` Renders

**Date:** 2026-06-02
**Status:** Approved design, ready for implementation planning
**Issue:** #87
**Scope:** Make the leading ticket key of each per-ticket **index entry** in the
multi-ticket / aggregate `/bitacora:status` renders a clickable link to the Jira ticket.
Read-side rendering only.

## Summary

The multi-ticket renders shipped in v0.4.0 (cross-ticket digest, `--blocked`, `--standup`)
and the epic rollup print ticket keys as **bare text** — a reader can't click through. This
applies the `[CTX]` format's existing *"compact references over bare URLs"* convention to
the read side: each per-ticket index entry leads with `[KEY](https://<site>/browse/KEY)`
instead of a bare `KEY`.

**Index-only.** Only the canonical per-ticket *list entry* is linked. Inline mentions of a
key — in `Health:`, `Top risks:`, and `Dependencies:` edges — stay bare, because a key can
repeat 3–4× in one render and linking every occurrence is visual noise. The index is the
one-link-per-ticket reference; that is enough to reach any ticket in one click.

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Link the index entry only**, not every occurrence | One clean link per ticket. Inline repeats (Health / Top risks / Dependencies) would clutter a terse render; the index already reaches every ticket. |
| D2 | **Markdown link form** `[KEY](https://<site>/browse/KEY)`; Slack form `<https://<site>/browse/KEY|KEY>` | Matches the `[CTX]` format's URL-wrapping rule (no bare URLs) and the existing Slack `mrkdwn` subsection. Renders clickable in the terminal; degrades to readable text elsewhere. |
| D3 | **Reuse the site already resolved in §3** (`getAccessibleAtlassianResources`) | No new lookup. `status` always has the site by the time it renders. |
| D4 | **Single-ticket `§5` renders unchanged** | They already carry a full URL line under the header. Re-linking the header is a separate rework of 5 established templates + their fixtures; out of scope here (possible follow-up). |
| D5 | **Linked spots are exactly the per-ticket index entries** | digest `By ticket:`, epic rollup `By child:`, `--blocked` entries, `--standup` `Moved:` entries. The `--standup` `No movement:` comma list stays bare (it's a tail, not entries). |

## Linked spots — precise

| Render | Linked | Stays bare |
|--------|--------|-----------|
| digest (default) | `By ticket:` entry keys | `Health`, `Top risks`, `Dependencies`, `Not yet reporting` tail |
| epic rollup | `By child:` entry keys | same as digest |
| `--blocked` | per-ticket entry keys | `Blocked on:` / `Waiting on:` body, `Clear:` tail |
| `--standup` | `Moved:` entry keys | `No movement:` comma list, `Did:` / `Next:` body |

Form: `- [KEY](https://<site>/browse/KEY) "<title>" — …`. Under `--copy-as-slack`:
`• <https://<site>/browse/KEY|KEY> "<title>" — …`.

## Touches

- `skills/session-status/SKILL.md` — §7 (digest / `--blocked` / `--standup` render
  templates), the *Aggregate render* templates (epic `By child:`), and the *Slack mrkdwn
  rendering* subsection (one new rule for ticket-key links). A one-line statement of the
  index-link rule near the top of §7 keeps the four templates DRY.
- `skills/session-status/examples/` — update the per-ticket index lines in
  `multi-aggregate.txt`, `multi-blocked.txt`, `multi-standup.txt`, `epic-exec.txt`, and
  `epic-eng.txt` to the linked form, using a placeholder site
  `https://example.atlassian.net`.
- `scripts/test-multi-status-fixtures.sh` — add an assertion that each reporting ticket's
  index entry is linked (`grep` for the `](https://…/browse/<KEY>)` form). The existing
  key-universe regex (`[A-Z][A-Z0-9]+-[0-9]+`) still matches inside the link, so the
  current checks stay green (the key now appears twice per linked line — label + URL — both
  in the allowed set).

## Testing

- The fixture-contract test gains a deterministic "index keys are linked" check per
  reporting ticket in each fixture; existing assertions unchanged.
- Live render (the actual markdown→clickable behavior, and the Slack form) stays under
  manual acceptance — add an `M9` item: *run the digest, confirm `By ticket:` keys are
  clickable links to the right tickets; run with `--copy-as-slack`, confirm
  `<url|KEY>` form.*

## Out of scope

- Single-ticket `§5` header linking (D4).
- Linking inline (`Health` / `Top risks` / `Dependencies`) occurrences (D1).
- Any change to the bare-key handling in `--standup`'s `No movement:` tail or
  `Not yet reporting:`.
