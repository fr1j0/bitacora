# `/bitacora:next` — Morning Ticket Picker

A read-only morning picker: read the tickets assigned to you, categorize them by pickup
cost / readiness, give a one-phrase reason-to-pick per ticket, and recommend the top
candidate. Its edge over a native Jira board is that it leans on the `[CTX]` corpus — so
"continue where you left off" reflects your own handoff notes (`Status` / `Next`), not just
a sort order. The last command on the Phase 2 roadmap; a *reader*, squarely inside
Bitácora's scope (it does not author tickets — see the `PLUGIN_BRIEF.md` roadmap notes on the
dropped `/improve` and `/spike`).

## Problem

Starting the day, "what should I pick up?" means scanning a board, remembering where each
in-flight ticket stood, and weighing readiness, blockers, and effort by hand. A native Jira
board sorts and filters but cannot synthesize *pickup cost* or surface "you left off here"
from your handoff trail. There is no single command that reads your tickets and produces a
ranked, reasoned shortlist grounded in the `[CTX]` continuity notes Bitácora already writes.

## Goal

`/bitacora:next` (alias `/bit:next`): query the user's open tickets, categorize into a small
set of decision-oriented buckets, annotate each with a reason-to-pick, mark one
recommendation, and render a compact shortlist whose footer chains into the already-shipped
`/bitacora:resume <KEY>`. Strictly read-only — no Jira writes, no clipboard.

## Prerequisites

- **Atlassian Rovo MCP** with read access to Jira (`searchJiraIssuesUsingJql`,
  `getJiraIssue`). MCP absent / auth fails / site unresolvable is a **hard stop** — the
  command cannot read boards without it.

## Non-goals (YAGNI)

- No Jira writes of any kind (no status transitions, no comments, no `/pick` command — the
  follow-up is the existing `/bitacora:resume`).
- No new ticket authoring (consistent with the dropped `/improve` / `/spike`).
- Deferred to post-v1: time-box filters (`/bitacora:next 90min`), mode filters
  (`--boring` / `--interesting`), and `--why-not` candidate explanations.
- No full 5-bucket backlog hygiene view — blocked/stale collapse into one tail line.

## Design

Skill-only, mirroring `handoff` / `resume` / `status`: a thin command delegates to a
`session-next` skill that runs the whole read-and-rank workflow in the main thread.

### New files

- `plugins/bitacora/commands/next.md` — thin trigger; delegates to `session-next`,
  passing `$ARGUMENTS` (unused in v1, reserved for the deferred filters).
- `plugins/bitacora/skills/session-next/SKILL.md` — the workflow (below).
- `plugins/bitacora/skills/session-next/examples/shortlist.txt` — a rendered example.
- `plugins/bitacora/alias/bit-next.md` — opt-in `/bit:next` alias (auto-synced into
  `~/.claude/commands/bit/` by the SessionStart hook).

### Edited files (on ship)

- `plugins/bitacora/commands/help.md` and `alias/bit-help.md` — move `/bitacora:next` from
  **Planned** to **Shipped**; add `/bit:next` to the alias line.
- `plugins/bitacora/README.md` and root `README.md` — add `/bitacora:next` to the command
  tables; add `/bit:next` to the alias list.

### Workflow (`session-next` skill)

1. **Resolve the Atlassian site** — `getAccessibleAtlassianResources` → `cloudId`; multiple
   sites use `jira_cloud_id` if configured, else ask. MCP/auth/site failure = **hard stop**.
2. **Query tickets** — `searchJiraIssuesUsingJql`. Default JQL:
   `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`, capped at
   ~50 results. `.bitacora.yml` → `next.jql` overrides the query verbatim. Request the
   fields needed for ranking (status, priority, issuetype, updated, time-tracking / story
   points, issuelinks, summary).
3. **Gather signals.** From the search result: status + statusCategory, priority, issue
   type, `updated`, effort estimate (story points or time-tracking), and issue links
   (blockers / blocks). **The `[CTX]` read is bounded for cost:** deep-read comments
   (strict `[CTX]` per `jira-comment-format`) only for *likely Continue* candidates —
   In Progress, or recently `updated`, assigned to the current user — to pull the latest
   `Status` / `Next`. Do not fetch comments for all ~50 (that is ~50 extra calls every
   morning).
4. **Categorize** (degrade gracefully when a signal is missing):
   - **Continue where you left off** — In Progress with recent activity and/or a recent
     `[CTX]`; lowest pickup cost. A recent `[CTX] Next` is the strongest signal.
   - **Ready to start** — not started, unblocked, specced; ranked by priority and by what
     it unblocks (outward "blocks" links).
   - **Quick wins** — small estimate. If no estimate field is populated, the ticket is
     simply not classified here (no guessing).
   - **Needs attention** (collapsed tail, one line) — blocked (Blocked status or inward
     "blocked by" links, silent ≥ N days) or stale (`updated` older than
     `next.stale_days`). For cleanup awareness, not selection.
5. **Reason-to-pick** — one phrase per ticket, grounded in an actual signal and citing it
   (e.g. *"near completion — last handoff: token refresh next"*, *"unblocks two P1s"*,
   *"~1h, isolated"*). Never invent a reason not supported by the data.
6. **Recommend** — a `★` arrow on the single best item: the top *Continue* candidate, else
   the top *Ready to start*.
7. **Render** — the bucketed shortlist (3 buckets + the Needs-attention tail). Footer offers
   exactly two actions: `→ /bitacora:resume <KEY>` (rehydrate the chosen ticket) and
   `→ re-run /bitacora:next for a different cut`.

### Rendered shape (example)

```
Picked up 23 tickets assigned to you. Today's shortlist:

━━ Continue where you left off ━━
★ PROJ-1234  OAuth callback handling            [In Progress]
  Last handoff: "callback wired, next is token refresh" · 3d ago
  → near completion, lowest context cost

━━ Ready to start ━━
  PROJ-1287  Migrate user prefs to new schema    [Ready]  P1
  → spec finalized; unblocks PROJ-1290 + PROJ-1291

━━ Quick wins ━━
  PROJ-1311  Fix flaky auth integration test     [Ready]  P2
  → ~1-2h, isolated race in mock setup

Needs attention: 1 blocked (PROJ-1298, 6d silent) · 1 stale (PROJ-1156, 47d)

→ Continue: /bitacora:resume PROJ-1234   ·   → re-run /bitacora:next for a different cut
```

### Error / edge behavior

- **MCP absent / auth fails / site unresolvable:** hard stop; report the reason, point to
  MCP setup.
- **Empty result:** say "nothing open assigned to you — inbox zero"; not an error.
- **Bad override JQL:** surface the offending query and Jira's error message; stop. Do not
  silently fall back to the default (that would hide the user's config mistake).
- **No `[CTX]` on Continue candidates:** fine — fall back to activity/status signals for the
  reason-to-pick; never block.
- Strictly read-only: no transitions, comments, or other writes.

### Configuration

Reuses `project_key_pattern`, the strict `[CTX]` read for activity signals, and
`jira_cloud_id` from `jira-comment-format` / handoff config (`.bitacora.yml` then
`~/.claude/bitacora.yml`; absence is normal). Adds two optional keys:

```yaml
next:
  jql: ""            # overrides the default query verbatim when set
  stale_days: 30     # "stale" threshold for the Needs-attention tail
```

## Decisions

- **Skill-only, no subagent** — consistent with the shipped siblings; the render is a single
  synchronous read-and-rank with no interactive gate.
- **Default JQL `assignee = currentUser() AND statusCategory != Done`** — works on day one
  with zero config; `next.jql` is the escape hatch for team boards.
- **Focused 3 buckets + collapsed Needs-attention tail**, not the brief's full five — keeps
  the picker a decision aid rather than a backlog manager, and avoids diluting the
  what-to-work-on signal.
- **Bounded `[CTX]` read** — only deep-read comments for likely *Continue* candidates, to
  cap morning latency/cost; other buckets rank from search fields alone.
- **Reuse `/bitacora:resume` as the follow-up**, no new `/pick` command — `/pick`'s only job
  (load a ticket into context) is exactly what `/resume` already does.
- **Read-only, print-only** — no clipboard (unlike `/status`); this is a live dashboard, not
  a shareable artifact.

## Testing / verification

- The skill is workflow prose; there is no shell logic to unit-test. Ship a rendered example
  fixture under `skills/session-next/examples/` for documentation and review.
- **Live acceptance test** (per the brief): run `/bitacora:next` in the morning against real
  assigned tickets; it must produce a categorized shortlist with a reason-to-pick on every
  line and exactly one `★` recommendation, and chain to `/bitacora:resume`. Soft quality
  bar: pick-correctness > 50% (the recommended item is one a human would reasonably pick).
