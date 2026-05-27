# `/bitacora:status` — Audience-Tailored Ticket Summary

**Date:** 2026-05-27
**Status:** Draft (design) — pending review

## Problem

`/bitacora:resume` rehydrates *one line of work into the current agent's context* — terse,
self-oriented, "get me back to coding." But the same `[CTX]` state on a ticket is often
needed for a *different* reader: a PM who wants plain-language progress and risk, or a
teammate picking the ticket up who wants the technical decisions and what's next. Today
producing those summaries is manual: open Jira, read the comments, translate by hand.

The `jira-comment-format` skill already reserves `/status` as a **strict-read** consumer
and the README already advertises the three audience modes (`--for-pm`, `--for-eng`,
`--for-self`) as Planned. This spec builds it.

## Goal

Add `/bitacora:status [KEY] [--for-pm|--for-eng|--for-self]` (with an opt-in `/bit:status`
alias) that reads a ticket's latest `[CTX]` state and **synthesizes an audience-tailored
summary** — different sections foregrounded and a different voice per mode — then prints it
and offers to copy it to the clipboard for pasting into a standup, Slack, or a PR.

It is a **sibling to `/bitacora:resume`**: both read `[CTX]` off a ticket using the same
resolution and strict-read machinery, but resume targets *the working agent* while status
targets *a human audience*.

## Prerequisites

The **Atlassian Rovo MCP (read access) is required** — status's whole function is reading a
ticket's `[CTX]`. Without the MCP it cannot run (same hard dependency as resume). Remember
is irrelevant here: status summarizes the *shared, durable* Jira state, not local scratch.

## Non-goals

- **No writes.** Status never comments on Jira and never mutates Remember. It is strictly
  read-only, so there is no confirmation gate (same safety property as resume). The
  clipboard copy is local and opt-in; it is not a Jira write.
- **Not resume.** Status does not frame output as "resuming" or inject a "suggested next
  step" for the agent to act on; it produces a *standalone summary for a reader*. Resume
  stays the self-into-context path.
- **No requirements rewrite.** Reading free-form discussion to sharpen requirements is
  `/bitacora:improve`'s job. Status extracts *state*, which per the format discipline comes
  only from `[CTX]`-prefixed comments (strict).
- **No multi-ticket roll-up.** Status summarizes *one* ticket. Cross-board breadth is
  `/bitacora:next`.
- **No new rendering test harness.** The per-mode rendering is model-driven prose, not
  deterministic code; we do not pretend to unit-test it (see Testing).

## Design

### New files

1. **`plugins/bitacora/commands/status.md`** — registers `/bitacora:status`. Frontmatter
   `description`; body delegates to the `session-status` skill and passes `$ARGUMENTS`
   (mirrors `commands/resume.md`).

2. **`plugins/bitacora/skills/session-status/SKILL.md`** — the workflow (steps below).
   `allowed-tools` covers `Bash` (git + clipboard tool), the Atlassian read MCP
   (`getJiraIssue`, `getAccessibleAtlassianResources`), and `Read`.

3. **`plugins/bitacora/skills/session-status/examples/`** — the *same* `[CTX]` rendered in
   all three modes (`self.txt`, `eng.txt`, `pm.txt`). Doubles as documentation and a manual
   acceptance reference.

4. **`plugins/bitacora/alias/bit-status.md`** — opt-in `/bit:status`, mirroring
   `alias/bit-resume.md`; delegates to the same skill. (Auto-copied by the existing
   `bit-*.md` glob, so no README opt-in snippet change beyond listing it.)

### Edited files (on ship)

5. **Root `README.md`** — promote the `/bitacora:status` row from 🚧 Planned to
   ✅ **Phase 1**; refine the description to match shipped behavior.
6. **`plugins/bitacora/README.md`** — add a `/bitacora:status` row to the command table.
7. **`commands/help.md` + `alias/bit-help.md`** — move `/bitacora:status` from the Planned
   block to Shipped, kept in sync (the existing single-source discipline).

### Workflow (`session-status` skill)

1. **Parse arguments.**
   - **Mode flag:** `--for-pm` | `--for-eng` | `--for-self`. An explicit flag always wins;
     with no flag, fall back to `status.default_mode` (built-in default `self`). Unknown
     flag or more than one mode flag → error that lists the valid modes; do not silently
     guess.
   - **Ticket key:** any `project_key_pattern` match in `$ARGUMENTS` forces the target.
   - **`--include-all`:** optional; reveal excluded (non-`[CTX]` / malformed) comments.

2. **Resolve the target ticket (single, focused).** Identical to resume:
   - Explicit key (forces it) → current branch (`git branch --show-current`) → recent
     checkouts (`git reflog`, capped ≈20, de-duplicated). If several candidates surface,
     **list them and let the user pick**. If nothing resolves: ask for a key once (no nag).

3. **Resolve the Atlassian site.** `getAccessibleAtlassianResources` → `cloudId`; if
   multiple sites, use the `jira_cloud_id` override or ask (identical to resume). MCP
   absent / auth fails / site unresolvable → **hard stop**.

4. **Read the ticket.** `getJiraIssue` requesting comments. Extract `[CTX]` comments under
   the **strict** READ rules in `bitacora:jira-comment-format` (`status_extraction:
   strict`): only comments that start with `[CTX]` and carry `Status:`+`Next:` count.
   - The **latest** `[CTX]` is authoritative for `Status` and `Next`.
   - Stitch up to `status.ctx_lookback` prior `[CTX]` (default 2) to build a short
     Done/progress trajectory.
   - Use each comment's own `created` timestamp from the API — never a hand-typed date.
   - Surface excluded counts separately (non-`[CTX]`, malformed); `--include-all` reveals
     them. Never silently drop.

5. **Render per mode.** Faithful, no invention; omit any section the `[CTX]` did not
   contain; preserve URLs verbatim (except where a mode strips them, below).

   - **`--for-self` (default)** — terse personal recall. Jargon and PR links fine.
     ```
     PROJ-1234 "<title>" — <Jira status>
     Left off:   <latest Status>
     Next:       <Next bullets>
     Decisions:  <decision bullets>        (only if present)
     Blockers:   <bullets>                 (only if present)
     ```

   - **`--for-eng`** — technical teammate handoff; keeps links, rationale, detail.
     ```
     PROJ-1234 "<title>" — <Jira status>
     https://<site>/browse/PROJ-1234

     Done recently:
     - <Done across the lookback window>
     Decisions:
     - <decision + rationale>
     Next:
     - <Next bullets>
     Blockers / open questions:
     - <only if present>
     ```

   - **`--for-pm`** — plain-language stakeholder status; strip jargon and PR hashes/code
     detail; lead with state and risk; keep the ticket link.
     ```
     PROJ-1234 "<title>"
     https://<site>/browse/PROJ-1234

     Status:        <on track / blocked / in progress — plain words>
     Progress:      <outcome-oriented Done across the lookback, jargon stripped>
     What's next:   <Next in plain language>
     Risks / needs: <Blockers + Open questions, framed as asks>   (only if present)
     ```

6. **Print, then offer clipboard copy.** Print the rendered summary into the conversation.
   Then offer to copy it to the clipboard (read-only, no Jira write, no gate). Clipboard is
   best-effort: try `pbcopy` (macOS), else `wl-copy`/`xclip` (Linux), else `clip` (Windows);
   if no tool is found, skip the offer silently — the printed summary always stands on its
   own.

### Error / edge behavior (mirrors resume)

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; no local-only pretense.
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` so future summaries have something to
  read.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry with
  a different key. No retry loop.
- **No ticket resolved:** say so; suggest passing a key.
- **Invalid / conflicting mode flag:** error listing the valid modes; do not guess.

### Configuration

Reuses `project_key_pattern`, `comment_compliance` (strict for status), and `jira_cloud_id`
from the `jira-comment-format` / handoff config (`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then
`~/.claude/bitacora.yml`; absence is normal). Two optional additions:

```yaml
status:
  ctx_lookback: 2        # prior [CTX] stitched for the Done/progress trajectory
  default_mode: self     # self | eng | pm — overrides the built-in default mode
```

## Decisions

- **Read-only + opt-in clipboard, no confirmation gate.** Nothing is written to Jira, so
  the draft→confirm→write discipline does not apply. The clipboard copy is a local
  convenience, offered after the print, never automatic.
- **Three modes ship together; default `self`.** The audience tailoring *is* the feature —
  shipping one mode would be indistinguishable from resume. `self` is the default because
  the most common caller is the working engineer.
- **Modes differ by section emphasis AND tone**, not just verbosity: `pm` foregrounds
  state/progress/risk in plain language and drops PR hashes; `eng` keeps technical
  decisions, links, and blockers; `self` is terse recall. This is the richest of the
  options considered and the reason `/status` earns its own skill.
- **Strict `[CTX]` read.** Per the format discipline and the strict/lenient table, status
  counts only compliant `[CTX]` comments and tallies excluded ones separately.
- **Latest authoritative + small lookback (default 2).** Latest `[CTX]` drives `Status`/
  `Next`; a couple of prior comments give the PM view a "recently" narrative without a full
  timeline (rejected: latest-only loses trajectory; full-history risks long output and
  heavy reads).
- **Sibling to resume, not folded into it.** Same resolution/site/strict-read machinery,
  but a distinct purpose (audience summary vs. self-into-context). Folding them would muddy
  resume's deliberately narrow contract; a shared helper skill is premature with only two
  consumers (rule of three — `jira-comment-format` already centralizes the READ rules).

## Testing / verification

- The three command/alias files parse (valid frontmatter); `validate-ctx.sh` and
  `test-validate-ctx.sh` are unaffected (status reads, never writes `[CTX]`); the strict
  classification status relies on is already covered there.
- The four command listings (help block, `bit-help`, plugin README, root README) agree
  after promotion from Planned → Shipped.
- The `examples/{self,eng,pm}.txt` fixtures render the same source `[CTX]` and visibly
  differ in section emphasis and tone (serves as the rendering acceptance reference).
- Manual acceptance against the live guinea-pig ticket (folding into the live-Jira
  acceptance pass already underway): run each mode and confirm section emphasis/tone;
  confirm the no-`[CTX]` graceful path; confirm the hard stop with the MCP disabled;
  confirm the clipboard offer copies on macOS and skips silently where no tool exists.
