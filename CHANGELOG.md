# Changelog

All notable changes to Bitácora are recorded here. The plugin follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html); while in alpha (`0.x.y`), expect the API to keep settling.

## [v0.6.0] — 2026-06-05 · Day-bucketed standup + clickable cross-ticket keys

Two refinements to `/status` and `/handoff`: the `--standup` lens now reads like a real
standup (grouped by day, past-first), and `/handoff` writes cross-ticket references as
clickable links instead of bare keys.

### Added

- **Day-bucketed `--standup`.** `/bitacora:status --standup` groups what moved into a past
  bucket then `Today`, **past-first**. The past header is data-driven and weekend-aware:
  `Yesterday` (the immediate prior day), a weekday name (e.g. `Friday`) when the prior worked
  day isn't yesterday, or `Earlier` for a wide `--since Nd` window. The lens now reads
  **every** in-window `[CTX]` per ticket (not just the latest), so a ticket touched on both
  the past day and today appears in both buckets with each day's `Did`/`Next`. Scoped to
  `--standup`; every other lens stays latest-`[CTX]`-authoritative.
  ([#102](https://github.com/fr1j0/bitacora/pull/102))
  - New pure-arithmetic `standup-buckets.sh` helper (UTC epoch → day index + weekday name),
    unit-tested on Linux and macOS; the committed `--standup` example and the multi-ticket
    fixture lint were updated to the two-bucket render.
- **Clickable cross-ticket keys in `[CTX]`.** When `/bitacora:handoff` drafts a `[CTX]`, any
  *other* ticket key it writes — in `Dependencies:`, a `Related:` line (siblings / parent
  initiative / epic), or inline — is now emitted as a compact reference link
  `[KEY](https://<site>/browse/KEY)` instead of a bare key, so the references click through in
  the rendered comment (applying the `jira-comment-format` compact-references convention).
  **Rendering only** — it creates no native Jira issue link and never touches the
  `parent`/epic field, staying inside the status-not-authoring scope.
  ([#103](https://github.com/fr1j0/bitacora/pull/103))

## [v0.5.1] — 2026-06-03 · Staleness signal

Read-side companion to v0.5.0's write-side guard: `/resume` and `/status` now flag when a
ticket's latest `[CTX]` has fallen **behind the ticket's own activity**, so you don't trust
a status the ticket has already moved past.

### Added

- **Staleness signal.** A ticket's latest `[CTX]` is **behind** when
  `ticket.updated − latest_[CTX].created > staleness_grace` (default **2d**) — i.e. the ticket
  got a status change / comment / activity *after* your last recorded context. Reported as
  `behind Nd`. This is **drift**, distinct from `/next`'s inactivity-`stale` (untouched for
  `next.stale_days`); it never fires when there is no `[CTX]` or when `updated ≤ created`.
  ([#96](https://github.com/fr1j0/bitacora/issues/96), [#97](https://github.com/fr1j0/bitacora/pull/97))
  - **`/bitacora:resume`** prepends a `⚠ This context may be behind …` banner under the
    header before rehydrating.
  - **`/bitacora:status`** adds a `Freshness: behind Nd` line (single-ticket) and a
    `· ⚠ behind Nd` marker on each stale per-ticket index entry (multi-ticket), composing with
    every `--for-*` / `--blocked` / `--standup` lens without changing their selection.
- **`staleness_grace` config key** (default `2d`; accepts `<N>h` / `<N>d`), top-level in the
  `[CTX]` format Configuration block since it is shared by `/resume` and `/status`.
- **Tests.** A pure-arithmetic `staleness-check.sh` helper (UTC epoch seconds) with an 11-case
  fixture suite wired into CI on Linux and macOS.

Read-only and advisory throughout — the signal never blocks a briefing or a summary.
Deferred by design: `/next` (it already carries an opposite inactivity-`stale`) and the
statusLine (it makes no synchronous network call).

## [v0.5.0] — 2026-06-03 · Collision detection on `/handoff`

Cashes in the write side of the shared-memory thesis: `/bitacora:handoff` now warns before
it buries a teammate's recent `[CTX]`, instead of writing blind. Stateless and author-based —
no new local state, and it never fires when you're the only one writing `[CTX]`.

### Added

- **Collision detection on `/bitacora:handoff`.** Before drafting, the (previously optional)
  continuity-read is now performed and also checks for a **collision**: when a ticket's
  most-recent `[CTX]` is authored by **someone other than you** (`accountId` resolved via
  `atlassianUserInfo`), is **newer than your own last `[CTX]`** there (or you have none — a
  takeover), and falls within **`collision_window`** (default **48h**), the confirm gate flags
  the ticket `⚠ collision` with the teammate's author, age, and a `Status`/`Next` excerpt, and
  offers three per-ticket actions:
  - **merge** — re-draft your `[CTX]` threading their `Status`/`Next` forward so their context
    is carried, not buried (re-shown before writing);
  - **proceed** — write your draft as-is;
  - **skip** — don't write that ticket.

  Warn-only — a collision never blocks the gate or the other tickets. Lenient throughout: MCP
  absent, read failure, unresolved identity, or no prior `[CTX]` → the check is skipped
  silently and the handoff proceeds. ([#93](https://github.com/fr1j0/bitacora/issues/93),
  [#94](https://github.com/fr1j0/bitacora/pull/94))
- **`collision_window` config key** (default `48h`; accepts `<N>h` / `<N>d`) in the handoff
  Configuration block — same override files as the other handoff keys.
- **Tests.** A pure-arithmetic `collision-check.sh` decision helper (UTC epoch seconds, no
  GNU/BSD `date` divergence) with a 12-case fixture suite wired into CI on Linux and macOS.
  The comment-extraction plumbing was verified live against real Jira data; the gate render is
  covered by a documented **dry-run** convention in `MANUAL-ACCEPTANCE.md` (ask the agent to
  simulate a teammate collision — it renders the gate and writes nothing).

Read paths and the single-user experience are unchanged.

## [v0.4.1] — 2026-06-03 · Ticket-key links are Slack-only

### Changed

- **Ticket-key links now appear only in `--copy-as-slack` output.** Printed `/bitacora:status`
  renders (digest, `--blocked`, `--standup`, epic rollup, every `--for-*` lens) show **bare**
  ticket keys again — the inline markdown links added in v0.4.0 were visual noise in a dense
  terminal glance. When you copy for Slack, each per-ticket index entry's key still renders as a
  `<https://<site>/browse/KEY|KEY>` link; inline / tail keys stay bare in both.
  ([#90](https://github.com/fr1j0/bitacora/issues/90))

## [v0.4.0] — 2026-06-02 · Multi-ticket `/status` — cross-ticket reads

Cashes in the read side of the shared-memory thesis: `/bitacora:status` now reads across an
**arbitrary multi-ticket scope**, not just one ticket or an epic's children. No new command or
alias — fully backward-compatible: `/status KEY` and `/status EPIC` are unchanged, and
multi-ticket mode activates only on a scope flag or 2+ keys.

### Added

- **Multi-ticket scope selectors for `/bitacora:status`** — `--mine`, `--sprint`,
  `--jql "<JQL>"`, or two-or-more ticket keys resolve (via JQL) to a set that is strict-read
  for each ticket's latest `[CTX]`, with honest coverage buckets (reporting / no-`[CTX]` /
  malformed / unreadable) and a capped fan-out (`status.multi_fanout_cap`, default 25) that
  discloses `showing N of M`. ([#83](https://github.com/fr1j0/bitacora/issues/83), [#84](https://github.com/fr1j0/bitacora/pull/84))
- **Two query lenses**, composing with the existing `--for-*` audience lenses:
  - `--blocked` — only tickets carrying `Blockers:`/`Dependencies:`, most-stale-first, with a
    `Clear: X of Y` tail.
  - `--standup [--since 1d|2d|last-working-day]` — what moved inside the window vs. a
    `No movement:` tail, backed by a deterministic, pure-arithmetic `since-window.sh` helper
    (UTC, no GNU/BSD `date` divergence).

  With no query lens, a multi-ticket scope renders the default **cross-ticket digest** — the
  epic-rollup renderer (health · confidence · risk concentration · dependency graph · cost)
  over an arbitrary set. The epic path keeps the term "portfolio"; the multi-ticket default is
  the "cross-ticket digest" (a deliberate split).
- **Ticket keys render as links.** In the multi-ticket / aggregate renders, each per-ticket
  index entry (`By ticket:` / `By child:` / `--blocked` / `--standup` `Moved:`) leads with a
  clickable `[KEY](https://<site>/browse/KEY)` link (Slack: `<url|KEY>`); inline mentions stay
  bare. ([#88](https://github.com/fr1j0/bitacora/pull/88))
- **Tests.** `since-window.sh` has a 13-case suite; a new CI-wired fixture-contract lint
  (`scripts/test-multi-status-fixtures.sh`) locks the multi-ticket example renders to the
  documented rules. The live-render layer stays under `MANUAL-ACCEPTANCE.md` (M1–M8).

Read-only throughout; strict `[CTX]` only. Phase B (`--debt`/`--risk`/`--deps`, `--board`,
saved-scope config) is tracked in [#85](https://github.com/fr1j0/bitacora/issues/85).

## [v0.3.3] — 2026-06-01 · Archive snapshot preserved verbatim

### Fixed

- `/bitacora:improve`'s `[ARCHIVE]` pre-improve snapshot now wraps the verbatim description in a
  **fenced code block** instead of a Markdown blockquote. Ticket descriptions are themselves
  Markdown, so the Markdown-to-ADF conversion dropped block-level constructs nested in the
  blockquote — clipping the snapshot after the first heading and defeating its rollback purpose.
  A fenced block preserves arbitrary content verbatim; the four-backtick widen rule is documented
  for the case where the source description contains its own fence. (#80, closes #79)

## [v0.3.2] — 2026-06-01 · Improve headings: h3

### Fixed

- `/bitacora:improve` section headings are now **`###` (h3)**, matching Jira's native AI
  "improve description" output (verified against the real rendered ProseMirror — every section
  is `heading-3`). v0.3.1 emitted `##` (h2). Skill §6 templates and all four golden examples
  updated; no other behavior change.

## [v0.3.1] — 2026-06-01 · Improve structure matches Jira's AI

### Changed

- **`/bitacora:improve` rewrites now mirror Jira's native AI "improve description" output.**
  Sections render as Markdown `##` headings (Stories: `User story` · `Context` ·
  `Acceptance criteria` · `Assumptions` · `Other information`) instead of bold-label lines, with
  bulleted lists throughout and **inline-code on every technical token** — endpoint URIs, RPC /
  service / method names, proto/field names, `package@version`, file paths, and identifiers — so the
  rewritten ticket is scannable. Bitácora's distinctive `Assumptions` section is kept. The
  `[ARCHIVE]` snapshot / accept-gate / no-invention discipline is unchanged.

## [v0.3.0] — 2026-06-01 · CTX enrichment

Makes the `[CTX]` record role-aware for a diverse org — frontend, backend, data science,
MLOps, AI staff, devops, infra, product, tech leads, and leadership — **without growing the
interface**. The net surface change across the whole cycle is two new flags on `/status`;
everything else is automatic. Fully backward-compatible: a minimal `[CTX]` (header + `Status:`
+ `Next:`) still validates, the validator's rules are unchanged, and the single-ticket
`/status` path is untouched.

### Added

- **Optional `[CTX]` enrichment vocabulary.** Beyond `Done`/`Decisions`/`Blockers`, a `[CTX]`
  can now carry `Artifacts:` (typed links), `Deploy/Ops:` (env · flag · rollback · watch-list ·
  infra $), `Model/Eval:` (model/prompt version · eval delta · inference $ · model rollback),
  `Dependencies:`, and `Risk:` — plus an `Impact:` surface line, an optional `Status:`
  `(confidence: …)` cue, and inline `Decisions:` tags (`[precedent]`/`[debt]`/`[blast-radius]`).
  `/handoff` populates these automatically from what the session actually did (work-type
  detection), from real evidence only. None affect compliance. ([#73](https://github.com/fr1j0/bitacora/pull/73))
- **Two new `/status` audience lenses** — `--for-ops` (deploy/operational) and `--for-exec`
  (business/risk/cost) — joining `--for-self`/`--for-eng`/`--for-pm`. A documented role→lens
  table maps 14 roles onto the 5 lenses; each lens routes the enrichment sections it cares about
  and strips what it doesn't (`pm`/`exec` drop internal references, keep the ticket link).
  ([#74](https://github.com/fr1j0/bitacora/pull/74))
- **Epic roll-up in `/status`.** Point `/status` at an Epic and it transparently fans out across
  the children, strict-reads each one's latest `[CTX]`, and renders a portfolio aggregate —
  health, confidence distribution, risk concentration, intra-epic dependency graph, and an
  approximate cost roll-up — in the chosen lens (epic default: `exec`). No new command; a
  story/bug still renders as a single ticket. ([#75](https://github.com/fr1j0/bitacora/pull/75))

## [v0.2.1] — 2026-05-29 · Alpha-ready

The first cut intended for an internal alpha audience. Validated end-to-end on a clean Claude Code profile.

### Behavior

- `/improve` no longer runs a pre-flight clarifying-questions round. It now produces a confident, opinionated rewrite in one pass and surfaces non-obvious choices as a new **Assumptions** section. Accept-or-cancel is the only user gate. ([#61](https://github.com/fr1j0/bitacora/pull/61))
- `[ARCHIVE]` snapshot header no longer carries a hand-typed timestamp — the Jira `created` metadata is authoritative, matching the rule the `[CTX]` format already enforced. ([#62](https://github.com/fr1j0/bitacora/pull/62))
- Identifier-backtick rule in the `[CTX]` format now explicitly names slash commands (`/bitacora:improve`), so command mentions render as inline `code` instead of bare prose. ([#63](https://github.com/fr1j0/bitacora/pull/63))

### Fixes

- **Handoff guardrail hook resolves correctly on installed plugins.** `precompact-handoff-check.sh` was sourcing `$DIR/handoff-pending.sh`, but the helper lives in `plugins/bitacora/statusline/`. The guard had been silently failing-open on every prompt since `v0.2.0`. The test stager was also corrected to mirror the production two-dir layout so future path drift fails CI rather than being masked. ([#60](https://github.com/fr1j0/bitacora/pull/60))
- Guardrail hook now prints `bitacora: jq not on PATH; handoff guardrail disabled` to stderr when `jq` is unavailable, instead of disabling silently. Fail-open behavior unchanged. ([#65](https://github.com/fr1j0/bitacora/pull/65))

### Docs

- **Installation section rewritten** with the verified direct-from-repo install path (`/plugin marketplace add fr1j0/bitacora` → `/plugin install bitacora@bitacora` → `/reload-plugins` → `/bitacora:help` to verify). Each step in its own code fence to prevent the paste-both-and-submit failure. ([#65](https://github.com/fr1j0/bitacora/pull/65), [#66](https://github.com/fr1j0/bitacora/pull/66))
- Auth-restart troubleshooting note added for the Claude Code quirk where in-session `/login` doesn't refresh the running process's auth state. ([#67](https://github.com/fr1j0/bitacora/pull/67))
- StatusLine and guardrail-hook opt-in instructions now use `jq`-in-place merges rather than heredoc clobbering — fixes a real risk where a colleague following the instructions verbatim could silently destroy their plugin install. ([#68](https://github.com/fr1j0/bitacora/pull/68))
- New top-level [`USAGE.md`](USAGE.md) with usage conventions for teams whose work passes through formal review or audit: `/improve` on formally controlled requirement tickets, `/status` as recall not source of truth, the load-bearing `Decisions:` line. ([#65](https://github.com/fr1j0/bitacora/pull/65))
- Project-key-pattern caveat added — the guardrail hook hardcodes the default uppercase pattern (`[A-Z][A-Z0-9]+-[0-9]+`) and does not yet read `.bitacora.yml` overrides. Tracked for a future enhancement. ([#65](https://github.com/fr1j0/bitacora/pull/65))
- Both READMEs' "Phase 1 shipped" intro lists now include every command. ([#69](https://github.com/fr1j0/bitacora/pull/69))

### Known limitations

- `/plugin install bitacora@bitacora` always installs from `main`. Pinning to a specific revision currently requires a fork. Versioned-tag install is on the roadmap once Claude Code's marketplace supports it.
- Atlassian Rovo MCP auth is account-scoped (lives outside `~/.claude/`). Revoking access in `claude.ai → Settings` affects every session for that account, not the testing profile alone.
- See [USAGE.md](USAGE.md) for usage conventions that aren't enforced by the plugin.

## [v0.2.0] — 2026-05-28

Initial public alpha. Phase 1 command surface — `/bitacora:handoff`, `/bitacora:resume`, `/bitacora:status`, `/bitacora:next`, `/bitacora:improve`, `/bitacora:help` — plus the opt-in statusLine context meter, the `/clear` handoff guardrail hook, and the `[CTX]` Jira-comment-format discipline.

[v0.2.1]: https://github.com/fr1j0/bitacora/releases/tag/v0.2.1
[v0.2.0]: https://github.com/fr1j0/bitacora/releases/tag/v0.2.0
