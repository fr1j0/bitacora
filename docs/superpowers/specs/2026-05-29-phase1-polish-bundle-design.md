# Phase 1 polish bundle — design

Four small follow-ons identified by the 2026-05-29 UX-flow review. Bundled because each is
small (≤ 30 line diff per skill), each is additive (no behavior change for users who don't
opt in or trip the heuristic), and they cluster the read-side skills (`resume`, `status`,
`next`).

## Items

1. **`/bitacora:resume` — vagueness hint.** Emit a one-line suggestion at the end of the
   briefing when the loaded ticket looks under-specified, pointing the user at
   `/bitacora:improve <KEY>`.
2. **`/bitacora:resume` — since-when awareness.** Add a `Last touched:` line to the
   briefing header and adaptively widen the Done trajectory window when the gap since
   the prior `[CTX]` is large.
3. **`/bitacora:status` — `--copy-as-slack` flag.** A new flag that re-renders the
   audience-tailored summary in Slack `mrkdwn` and auto-copies to clipboard, so the
   engineer pastes a one-message status update without manual reformatting.
4. **`/bitacora:next` — team-JQL discoverability.** Documentation-only fix that surfaces
   the existing `next.jql` override as a team-scoped picker pattern, in the skill's
   Configuration section.

## Problem (per item)

**1. Vagueness hint.** `/bitacora:improve` is on-demand. If an engineer goes
`/bitacora:next` → `/bitacora:resume` and starts working, no one notices the ticket is
vague (one-sentence PM description, no acceptance criteria), and the corpus advantage of
the rewriter never lands. `/resume` already has the data — it just doesn't act on it.

**2. Since-when awareness.** `/resume` produces the same briefing depth for a 1-day gap
and a 30-day gap. After a long absence, an engineer wants more context: which prior
`[CTX]`s shipped in the interval, not just the latest one. The skill's
`resume.ctx_lookback` config gates this — currently it's a single static value (default 1)
that has to be set high all the time or stay low forever.

**3. `--copy-as-slack`.** When a PM Slacks "where are you on KEY-1234?", the engineer runs
`/bitacora:status --for-pm`, copies the output, and pastes — but the Markdown formatting
(`**bold**`, `[label](url)`, tables) renders wrong in Slack. The engineer hand-reformats.

**4. Team-JQL discoverability.** `next.jql` already accepts arbitrary JQL, so a team-scoped
picker is achievable today (`assignee in (currentUser(), bob@…, alice@…)`). The friction
is *discovery* — nothing in the skill or README says "here's how to make `/next` see the
team's tickets, not just yours".

## Goal

Land four cheap, additive UX improvements that close known friction points without
expanding Bitácora's scope.

## Prerequisites

None new. Reuses everything `session-resume`, `session-status`, `session-next` already
require (Atlassian Rovo MCP, no new permissions).

## Non-goals (YAGNI)

- **No webhook auto-post to Slack** (`#6` friction in the proposal). Adding a Slack
  webhook integration competes with Atlassian's native Slack app and is push-feature
  creep. `--copy-as-slack` ships the *rendering*, not the *delivery*.
- **No `next.team_jql` / `next.team_members` syntactic-sugar config keys** (`#7`). The
  documentation fix is enough; introducing a new config key for what `next.jql` already
  does adds surface area and earns shipment only if a real team adopts and reports
  friction.
- **No AC-section detection** for the vagueness hint (`#2`). Word-count + recent-archive
  check is the v1 heuristic. AC detection has too many false positives across teams that
  format AC differently ("Acceptance criteria" / "AC:" / "Definition of done" / inline
  bullets); not worth the parsing complexity now.
- **No new `[CTX]` lookback config** for the since-when bump (`#4`). The bump reuses the
  existing `resume.ctx_lookback` key, just adaptively per-invocation when the absence is
  long. New config keys earn their place only when the behavior can't be derived.
- **No PreCompact handoff hook** (`#3` friction). Separate brainstorm — the prompt-in-hook
  UX is novel and needs its own spec.
- **No `[CORRECTION]` prefix** (`#5` friction). Existing discipline (write a corrective
  `[CTX]` via the next handoff) already covers it; dropped during the proposal pass.
- **No `/bitacora:start` command** (`#1` friction). Jira state transitions are a
  Jira-native concern; dropped during the proposal pass.

## Design

### 1. Vagueness hint in `/bitacora:resume`

Extend `session-resume` step 4 (synthesize the briefing). After the briefing renders and
before the "safe to continue working" note, emit a one-line hint *only if* all three
conditions hold:

- `resume.improve_suggest.enabled` is true (default true)
- The ticket's `description` field is shorter than
  `resume.improve_suggest.min_description_words` (default 50 words; whitespace-split count
  on the description text)
- No `[ARCHIVE]` comment exists on the ticket within the last
  `resume.improve_suggest.suppress_window_days` (default 7 days) — i.e., the ticket
  hasn't already been improved recently

Hint format:

```
💡 This ticket's description is brief (18 words, no recent [ARCHIVE]).
    Consider /bitacora:improve <KEY> before starting — corpus-grounded rewrite
    grounded in [CTX] history, comments, Remember scratch, and git/PR refs.
```

The hint is **suggestion, not gate** — the engineer can ignore it. Suppression knob exists
(`enabled: false`) for teams whose tickets are intentionally terse.

**New config keys** (under `resume:`):

```yaml
resume:
  improve_suggest:
    enabled: true               # silence the hint entirely
    min_description_words: 50   # threshold; tickets below this are flagged
    suppress_window_days: 7     # skip if an [ARCHIVE] landed within this window
```

### 2. Since-when awareness in `/bitacora:resume`

Two changes to `session-resume`:

**Header line.** Step 4's briefing template adds a new line at the top, right after the
`Resuming KEY-1234 — "title"` line and before the ticket URL:

```
Resuming KEY-1234 — "OAuth callback handling"  (In Progress)
Last touched: 12 days ago (2026-05-17)
https://<site>/browse/KEY-1234
```

The timestamp comes from the latest compliant `[CTX]` comment's `created` field. If there
are zero `[CTX]` comments, the line reads `Last touched: never (no [CTX] yet)`.

**Adaptive trajectory.** Step 3's "read up to `resume.ctx_lookback` prior `[CTX]`" rule is
augmented: if days-since-last-`[CTX]` > `resume.long_absence_days` (default 7), the
lookback for *this invocation* is bumped to `resume.long_absence_lookback` (default 3).
The config keys aren't mutated; the bump is invocation-local. The briefing's "Recently
done" section now stitches more prior `[CTX]` content proportional to the absence.

**New config keys** (under `resume:`):

```yaml
resume:
  long_absence_days: 7          # threshold above which the lookback widens
  long_absence_lookback: 3      # invocation-local ctx_lookback when over the threshold
```

### 3. `--copy-as-slack` flag for `/bitacora:status`

Add an optional flag, compatible with the existing mode flags
(`--for-pm` / `--for-eng` / `--for-self`). When set:

- Step 5 renders the same audience-tailored summary content, but using Slack `mrkdwn`
  conventions:
  - `*bold*` instead of `**bold**`
  - `<https://example.com|label>` instead of `[label](https://example.com)`
  - Plain bulleted lines (`• item`) instead of Markdown lists (`- item`) — Slack renders
    Markdown lists inconsistently
  - **No Markdown tables.** If the original mode would have used a table (none currently
    do, but defensive), fall back to one bullet per row
  - Ticket key + URL surfaced prominently as the leading line, e.g.
    `*KEY-1234* — <https://site/browse/KEY-1234|OAuth callback handling>`
- Step 6 **always** copies to clipboard (skips the existing prompt) — the flag is the
  user's explicit "I want this for paste" signal. If clipboard is unavailable, print the
  rendered text and note that clipboard delivery wasn't possible.

The flag is purely a rendering+delivery variant. All read semantics (strict `[CTX]`
extraction, ticket resolution, error handling) are unchanged.

**No new config keys.** Slack format is fixed; teams that want it use the flag per call.

### 4. Team-JQL discoverability — documentation

Update `plugins/bitacora/skills/session-next/SKILL.md`'s Configuration section with an
expanded `next.jql` example block. Current text shows only the default override mechanism;
expanded text adds a team-scoped pattern:

```yaml
next:
  # Default JQL is: assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
  # Override to pick across multiple teammates:
  jql: "assignee in (currentUser(), bob@example.com, alice@example.com) AND statusCategory != Done ORDER BY updated DESC"
  stale_days: 30
```

Plus one sentence noting that the team members in the `in (...)` list must be Jira
account identifiers (email or accountId), not arbitrary usernames. No code change.

### Files touched

**Edited:**
- `plugins/bitacora/skills/session-resume/SKILL.md` — items 1 + 2: step 3 (lookback
  bump), step 4 (briefing header + vagueness hint), Configuration block (3 + 2 new
  keys = 5 new keys under `resume.improve_suggest` and `resume.long_absence_*`).
- `plugins/bitacora/skills/session-status/SKILL.md` — item 3: step 1 (parse the new
  flag), step 5 (Slack-mrkdwn rendering branch), step 6 (always-copy when flag set).
- `plugins/bitacora/skills/session-next/SKILL.md` — item 4: Configuration block (expand
  the `next.jql` example).

**New:** none.

**Test fixtures touched:** none. The skill prose is the surface; validate-ctx
classification of `[ARCHIVE]` (item 1's suppression check) is already locked in by the
existing `archive.txt` fixture.

## Decisions

- **Bundle, don't split.** All four items are small, additive, and cluster the read-side
  skills. One PR keeps the diff comparable, the rationale shared, and the review pass
  efficient. Splitting would multiply CI runs and review overhead for no gain.
- **Word count for vagueness, not AC detection.** Word count is dumb but predictable; AC
  detection requires per-team format awareness (which Bitácora doesn't have). Hint is a
  suggestion, not a gate — predictable-but-coarse is fine.
- **Suppression by recent `[ARCHIVE]`, not by `[CTX]` count.** A ticket with many `[CTX]`s
  but a stale vague description should still be flagged; the relevant signal is "has the
  description itself been sharpened recently" — `[ARCHIVE]` is exactly that record.
- **Invocation-local lookback bump (not config mutation).** The widened trajectory for
  long absences is an emergent property of the read, not a state change. The user's
  config stays whatever they set; only that invocation's read window widens.
- **Slack flag = render + always-copy.** The existing copy-prompt was for the default
  mode where the user may want to read on-screen first. Setting `--copy-as-slack`
  declares intent ("I want this for paste"), so skipping the prompt removes a needless
  confirmation.
- **No new config for team-JQL.** `next.jql` already does the job. Adding a `team_jql` /
  `team_members` pair would duplicate capability and add a maintenance surface (two
  ways to do the same thing). Document the existing escape hatch instead.
- **Bundle title `phase1-polish-bundle`.** Marks this as the "polish v1" pass following
  the 2026-05-29 UX flow review; future polish bundles can take their own dated
  suffixes.

## Testing / verification

The four changes are all skill prose; no shell logic to unit-test. Verification is
primarily by live invocation against real Jira tickets.

**Live acceptance tests:**

- **Item 1 (vagueness hint):** invoke `/bitacora:resume` on a ticket with a short
  description (≤ 50 words by default) and no recent `[ARCHIVE]`. Confirm the hint
  appears with the right word count and suggests `/bitacora:improve`. Then run
  `/bitacora:improve` on the same ticket and confirm the next `/bitacora:resume`
  suppresses the hint (recent `[ARCHIVE]` exists within the window).
- **Item 2 (since-when):** invoke `/bitacora:resume` on two tickets — one with a recent
  `[CTX]` (≤ 7 days), one with an older one (> 7 days). Confirm the older one's briefing
  has the `Last touched:` line + a wider Done trajectory (3 prior `[CTX]`s) vs the
  recent one's narrower window (1 prior).
- **Item 3 (`--copy-as-slack`):** invoke `/bitacora:status KEY-1234 --for-pm
  --copy-as-slack` and confirm the clipboard contains Slack `mrkdwn` (single-asterisk
  bold, `<url|label>` links, no Markdown tables), with the ticket key + URL surfaced as
  the leading line. Paste into a Slack thread to confirm rendering.
- **Item 4 (team-JQL docs):** configure a `.bitacora.yml` with the team-JQL example from
  the new docs and confirm `/bitacora:next` returns tickets assigned to multiple
  teammates.

**No regression tests needed** in `test-validate-ctx.sh` or other shell suites — items
1–3 don't touch any shell script or config schema beyond skill prose. The `[ARCHIVE]`
recency check (item 1) reuses the `validate-ctx.sh not-in-format` classification already
asserted by the `archive.txt` fixture.

**Spec self-review:** placeholder scan clean, no TBDs; per-item designs are internally
consistent with the spec's non-goals; ambiguity around vagueness heuristic is resolved by
the explicit word-count choice; the bundle is scope-checked at ~4 changes across 3 skill
files, fits a single implementation plan.
