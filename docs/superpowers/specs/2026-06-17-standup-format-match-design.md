# `--standup` format match (done/planned/blocked) — design

**Date:** 2026-06-17
**Status:** approved (brainstorm)
**Scope:** `plugins/bitacora/skills/session-digest` (`--standup` query lens only)
**Supersedes:** the day-bucketed render (`2026-06-05-standup-day-buckets-design.md`)

## Problem

The `--standup` lens renders chronological day buckets (`Yesterday:` / `Today:`,
weekend-aware `Friday` / `Earlier` headers), each line carrying both `Did` and `Next`
and inline `⚠` blockers. It reads as a movement log, not a standup.

The conventional standup format — as used by the Claude Code `standup` skill — is a
clean three-section split: **what got done → what's planned → what's stuck**, under
markdown headings. That shape is more scannable and is what readers expect to paste
into a standup channel. This change adopts both its *look* (markdown `##`/`###`
headings) and its *semantics* (done / planned / blocked), replacing the day-bucket
default.

## Design

### Semantic remap

The window cutoff (`since-window.sh`, `--since <token>`, default `last-working-day`)
and the "read **every** in-window `[CTX]` per reporting ticket" rule are unchanged.
What changes is how those `[CTX]` map to sections:

- **Yesterday = done.** For each reporting ticket, the `Did` (Done / status-change)
  text from **all** its in-window `[CTX]`, joined in `created`-ascending order with
  `; `. One line per ticket.
- **Today = plan.** The `Next` bullet(s) from the ticket's **latest** in-window
  `[CTX]` (earlier `Next`s are superseded). A ticket whose latest in-window `[CTX]`
  has no `Next` is omitted from Today.
- **Blockers = stuck.** The `⚠` Risk/Blockers one-liner from each ticket that has one,
  one bullet per ticket.

Day-of-week bucketing is **removed**: there is no Yesterday/Friday/Earlier derivation
and no both-buckets duplication. The past section is always literally `### Yesterday`;
the actual window is shown in the subtitle. `--since 2d` still widens the window — the
"Yesterday" heading stays loose per standup convention, with the exact span in the
subtitle.

### Per-ticket Jira status

Jira status is real signal orthogonal to the temporal sections ("In Review" = waiting
on a reviewer; not inferable from `Did`). It is shown **once per ticket**, as an
inline-code tag immediately after the title on the **Yesterday** line (every reporting
ticket appears there, since it moved in-window). Today and Blockers stay status-free to
avoid repetition. The backtick tag matches Bitácora's token-fencing house style and
degrades cleanly to `` `In Review` `` in Slack.

### Render shape (printed Markdown, default `self` lens)

```markdown
## Standup — <today UTC date, YYYY-MM-DD>
_since <token> · <coverage>_

### Yesterday
- <KEY> "<title>" `<Jira status>` — <all in-window Did, joined "; ">

### Today
- <KEY> — <Next from the latest in-window [CTX]>

### Blockers
- <KEY> — <Risk/Blockers one-liner>
```

- **Heading** is `## Standup — <date>`; the window/coverage context
  (`since 1d · 4 tickets (3 reporting, 1 no [CTX])`) moves to the italic subtitle so
  scope survives without cluttering the heading.
- **`### Blockers` is always rendered**; when no ticket has a blocker, its body is
  `- _None_` (keeps the consistent, scannable three-section shape).
- **`### Yesterday` / `### Today`** are omitted only if genuinely empty (rare — a
  reporting ticket always has a `Did`, so Yesterday is effectively always present).
- **No movement** trailing italic line — `_No movement: <KEY, …>_` — reporting
  tickets with no in-window `[CTX]`; omitted when none.
- **Empty result** unchanged: `No [CTX] activity since <token> across <coverage>.`
- **Staleness `· ⚠ behind Nd`** stays per-ticket, printed once on the ticket's
  Yesterday line.

### Slack (`--copy-as-slack`)

Same content, Slack `mrkdwn`:

- `## Standup — <date>` → `*Standup — <date>*`; each `### Heading` → `*Heading*`.
- `• ` bullets (U+2022), not Markdown `- `.
- Ticket-key links on each per-ticket leading key
  (`<https://<site>/browse/KEY|KEY>`), as today.
- Status tag `` `In Review` `` renders as backtick code in Slack — left as-is.
- Update the §"Slack mrkdwn rendering" wording that refers to "day headers" /
  "`--standup` bucket entries (under the day headers)" to point at the new
  Yesterday/Today/Blockers headings.

### Helper & tests

- **Retire `standup-buckets.sh` + `test-standup-buckets.sh`** — used only by the
  day-bucket render. Drop their CI lint references.
- `since-window.sh` (cutoff) and its test are **unchanged**.
- `examples/multi-standup.txt` — regenerate to the new three-section render.
- `test-digest-fixtures.sh` — update the `--standup` assertions: assert the
  `## Standup —`, `### Yesterday`, `### Today`, `### Blockers` headings and the inline
  status tag; drop the `Yesterday:` / `Today:` plain-label checks, the both-buckets
  (`>=2 occurrences`) check, and the `Moved:`-absence check (replace with new
  shape checks). Keep the `No movement:` and no-`[CTX]`-omission assertions.

## Carried over unchanged

UTC-day-aligned window, `--since <token>` semantics, the no-invention rule, `--standup`
remaining a multi-ticket-only lens, the five `--for-*` audience lenses selecting
altitude, and the read-only / clipboard-copy behavior.

## Out of scope

The `--blocked` lens, the cross-ticket aggregate digest, epic rollup, the `/status`
skill, and any change to other lenses' latest-`[CTX]`-authoritative read model.
Local-time bucketing. The CHANGELOG entry + version bump (handled as a separate release
step per the release runbook).
