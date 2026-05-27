# `/bitacora:resume` — Read Back Into a Session

**Date:** 2026-05-27
**Status:** Draft (design) — pending review

## Problem

`/bitacora:handoff` is write-only: at the end of a session it pushes a structured
`[CTX]` comment to each touched ticket and a consolidated scratch to Remember. But
nothing reads the Jira side back. After a `/clear`, the only automatic rehydration is
Remember's local scratch — which is private, machine-local, and gone the moment you
switch machines or a teammate picks the ticket up. The clean, durable, shared state
written to the ticket just sits there unread until a human opens Jira.

So today the loop is half-open: handoff writes to Jira, but resume-from-Jira is manual.

## Goal

Add `/bitacora:resume [KEY]` (with an opt-in `/bit:resume` alias) that rehydrates a
fresh session from a ticket's latest `[CTX]` comment(s): it reads the structured state
off the ticket and prints a compact briefing — *where you left off, what's done, what
was decided and why, what's next* — into the conversation, so the agent and user
continue cleanly without re-deriving state from git or a degraded transcript.

It is the **read-side counterpart to `/bitacora:handoff`** and closes the loop the
[Why this exists] section of the README describes.

## Prerequisites

The **Atlassian Rovo MCP (read access) is required** — resume's whole function is reading
a ticket's `[CTX]`, so there is Jira to deal with or there is nothing to do. Unlike
handoff (which still saves a local scratch and so offers a courtesy local-only mode),
resume has **no useful local-only mode**: without the MCP it cannot run. Remember remains
optional and only enriches the briefing (see step 5).

## Non-goals

- **No writes.** Resume never comments on Jira and never mutates Remember. It is
  strictly read-only, so there is no confirmation gate (contrast handoff). This is a
  deliberate safety property, not an oversight.
- **Not a Remember replacement.** Remember still auto-injects local scratch at session
  start; resume covers the Jira gap that Remember cannot (cross-machine, cross-teammate,
  durable). The two are complementary.
- **No requirements rewrite.** Reading free-form ticket discussion to *understand or
  sharpen* requirements is `/bitacora:improve`'s job. Resume extracts *state*, which per
  the `jira-comment-format` discipline comes only from `[CTX]`-prefixed comments.
- **No multi-ticket "catch me up on everything."** Resume is about getting back into
  *one* line of work (see Decisions). Breadth across a board is `/bitacora:next`.

## Design

### New files

1. **`plugins/bitacora/commands/resume.md`** — registers `/bitacora:resume`.
   Frontmatter `description`; body delegates to the `session-resume` skill and passes
   `$ARGUMENTS` (mirrors `commands/handoff.md`).

2. **`plugins/bitacora/skills/session-resume/SKILL.md`** — the workflow (steps below).
   `allowed-tools` covers `Bash` (git), the Atlassian read MCP (`getJiraIssue`,
   `getAccessibleAtlassianResources`), and `Read`.

3. **`plugins/bitacora/alias/bit-resume.md`** — opt-in `/bit:resume`, mirroring
   `alias/bit-handoff.md`; delegates to the same skill.

### Edited files (on ship)

4. **Root `README.md`** — promote the `/bitacora:resume` row from 🚧 Planned to
   ✅ Phase 1 (or whichever phase ships it).
5. **`plugins/bitacora/README.md`** — add a `/bitacora:resume` row to the command table;
   extend the alias `cp` snippet to cover `bit-resume.md`.
6. **`commands/help.md` + `alias/bit-help.md`** — move `/bitacora:resume` from the
   Planned block to Shipped, kept in sync (the existing single-source discipline).

### Workflow (`session-resume` skill)

1. **Resolve the target ticket (single, focused).**
   - Explicit key in `$ARGUMENTS` (parsed with `project_key_pattern`) forces it.
   - Else parse the current branch: `git branch --show-current` → `project_key_pattern`.
   - Else scan recent checkouts (`git reflog`, capped ≈20, de-duplicated) — same heuristic
     handoff uses — and, if several candidates surface, **list them and let the user
     pick** rather than guessing. Resume is about focus, not breadth.
   - If nothing resolves: ask for a key (no nag).

2. **Resolve the Atlassian site.** `getAccessibleAtlassianResources` → `cloudId`; if
   multiple sites, use the `jira_cloud_id` override or ask (identical to handoff).

3. **Read the ticket.** `getJiraIssue` requesting comments. Extract `[CTX]` comments per
   the **READ** rules in `bitacora:jira-comment-format` (strict/lenient compliance). The
   **latest** `[CTX]` is authoritative for `Status` / `Next`. Optionally read the
   immediately prior `[CTX]` (lookback configurable, default 1) to reconstruct a short
   *Done* trajectory without re-quoting everything. Use the comment's own `created`
   timestamp — never a hand-typed date.

4. **Synthesize the briefing.** Faithful, condensed, no invention. Omit any section the
   `[CTX]` didn't contain. Preserve PR / links verbatim. Suggested shape:

   ```
   Resuming PROJ-1234 — "<ticket title>"  (Jira status: In Progress)
   https://<site>/browse/PROJ-1234

   Where you left off:  <latest Status line>
   Recently done:       <condensed Done bullets across the lookback window>
   Decisions:           <decision + rationale bullets>
   Next:                <actionable Next bullets>
   Blockers / open Qs:  <only if present>

   Suggested next step: <derived from the first Next item>
   ```

5. **Reconcile local scratch (optional, additive).** If a clean read of the Remember
   scratch is available, surface its private gotchas (dead ends, fragile-code warnings)
   under a separate "Local notes" heading. If not, skip silently — Remember already
   auto-injects at session start. This *enriches* the Jira briefing; it is never a
   substitute for it (a missing MCP is a hard stop, not something scratch can backfill).

6. **Print and stop.** Output the briefing into the conversation. Read-only: no gate, no
   write, note it's safe to continue working.

### Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop** — resume
  cannot do its job without Jira read. Report the reason and point to MCP setup; do not
  pretend a local-only fallback. (Surfacing any auto-injected Remember scratch is fine,
  but it is not "resume succeeding.")
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` at session ends so future resumes have
  something to read.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry
  with a different key. No retry loop.
- **Nothing to resume (no ticket resolved):** say so; suggest passing a key.

### Configuration

Reuses `project_key_pattern`, the compliance modes, and `jira_cloud_id` from the
`jira-comment-format` / handoff config (`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then
`~/.claude/bitacora.yml`). One optional addition:

```yaml
resume:
  ctx_lookback: 1     # how many prior [CTX] comments to stitch for the Done trajectory
```

## Decisions

- **Read-only, no confirmation gate.** Nothing is written, so the draft→confirm→write
  discipline that governs handoff does not apply. Stating this keeps the safety story
  clean: resume can never corrupt a ticket.
- **`[CTX]` is the resume source, not free-form comments.** Consistent with the format
  discipline — state comes from `[CTX]`; human discussion is ignored for state extraction.
- **Single-ticket focus.** Resume answers "get me back into *this* work," so it targets
  one ticket (branch-derived by default). Cross-board breadth is `/bitacora:next`.
- **Synthesized, not a verbatim dump.** The point of resume is a *compact* clean restart,
  not re-loading a wall of text. The briefing condenses faithfully and preserves links.
- **Counterpart to handoff.** Same ticket-resolution heuristics, same site resolution,
  same config — so the two commands feel like two halves of one loop.

## Resolved design choices

Confirmed 2026-05-27:

- **A. Single, branch-derived ticket.** Resume targets one line of work; cross-board
  breadth stays with `/bitacora:next`.
- **B. Synthesized briefing.** Compact, faithful summary — not a verbatim `[CTX]` dump.
  A `--full` verbatim flag is deferred to a later phase if wanted.
- **C. Latest + 1 prior `[CTX]`.** Latest is authoritative for `Status`/`Next`; one prior
  reconstructs the `Done` trajectory. `resume.ctx_lookback` (default 1) tunes this.
- **D. Surface local scratch if readable.** Additive "Local notes" section when a clean
  Remember read exists; otherwise skipped. Never a substitute for the Jira read.

## Testing / verification

- The three command/alias files parse (valid frontmatter); `validate-ctx.sh` is
  unaffected (resume reads, never writes `[CTX]`).
- The four command listings (help block, `bit-help`, plugin README, root README) agree
  after promotion from Planned → Shipped.
- Manual acceptance: on a branch named for a ticket that already has a `[CTX]`, run
  `/bitacora:resume` and confirm the briefing reflects the latest `Status` / `Next`; run
  it on a ticket with no `[CTX]` and confirm the graceful "nothing to resume" path; run it
  with the Atlassian MCP disabled and confirm the local-only fallback.
