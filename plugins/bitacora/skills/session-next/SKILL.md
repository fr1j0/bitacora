---
name: session-next
description: Morning ticket picker — query the tickets assigned to you, categorize by pickup cost / readiness, annotate each with a one-phrase reason-to-pick, recommend the top candidate, and chain into /bitacora:resume. Read-only; no Jira writes. Use when the user runs /bitacora:next or /bit:next.
---

Read the tickets assigned to you and produce a categorized morning shortlist with a single
recommendation. The edge over a native tracker board is that it leans on the `[CTX]` corpus —
so "continue where you left off" reflects your own handoff trail (`Status` / `Next`), not
just a sort order. Strictly **read-only** — no writes, no clipboard, no gate. Follow
the **READ** rules in `bitacora:jira-comment-format` (strict `status_extraction`) when
extracting `[CTX]` state.

## 0. Resolve the tracker (first)

Run `resolve-tracker.sh` before any read step:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tracker.sh"   # → github | gitlab | jira
```

Branch **once** on family and follow the corresponding path below:

- **jira** → mcp family: proceed to step 1 (Atlassian site resolution) as today.
- **github / gitlab** → cli family: **skip steps 1–3**; go directly to
  [CLI path (github/gitlab)](#cli-path-githubgitlab) below.

If the script exits 4 (not a git repo or no remote and no explicit `tracker:` in
`.bitacora.yml`), hard stop: tell the user to set `tracker:` and do not guess.

For full backend capability notes, see `bitacora:tracker-adapter`.

## 1. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites are returned, use the
`jira_cloud_id` override if configured, else ask which. **If the MCP is absent, auth
fails, or the site can't be resolved, this is a hard stop** (see Error behavior) — `next`
cannot do its job without Jira read access.

## 2. Resolve the project scope (git / local)

The default query is always scoped to the current repo's Jira project — never a
site-wide dump of everything assigned to you. **Skip this step entirely when
`next.jql` is set** — the override is the user's verbatim query and owns its own
scoping.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-project-scope.sh"
```

(From the repo root: `plugins/bitacora/scripts/resolve-project-scope.sh`.) The script
reads the repo's git remote (`origin`, else the first remote), normalizes it to a
lowercase `host/owner/repo` slug, and resolves it through the
`next.remote_project_map` config table (repo-level `.bitacora.yml` entry overrides
the `~/.claude/bitacora.yml` one, per slug — see Configuration).

- **Exit 0** — stdout is the Jira project key; inject `AND project = <KEY>` into the
  default JQL (step 3).
- **Any non-zero exit** — **hard stop.** Relay the script's stderr message verbatim:
  for an unmapped slug (exit 3) it names the detected slug and shows the exact YAML
  to add; for a missing repo/remote (exit 4) it states the reason. Do **not** fall
  back to an unscoped query.

## 3. Query the tickets

`searchJiraIssuesUsingJql`. Default JQL (`<KEY>` is the project key from step 2):

```
assignee = currentUser() AND project = <KEY> AND statusCategory != Done ORDER BY updated DESC
```

Capped at ~50 results. `.bitacora.yml` → `next.jql` overrides the default verbatim
(no merging, no silent fallback, no scope injection — the override owns its scoping
and step 2 is skipped entirely). Request the fields needed for ranking: `summary`,
`status` (with `statusCategory`), `priority`, `issuetype`, `updated`, time-tracking and
story-points fields, and `issuelinks`. Empty result is **not** an error — see Edge behavior.

## 4. Gather signals (bounded [CTX] read)

From the search result, extract per ticket: status + `statusCategory`, priority, issue
type, `updated`, effort estimate (story points or time-tracking, whichever the project
populates), and issue links (outward `blocks`, inward `is blocked by`).

The `[CTX]` read is **bounded for cost**: deep-read comments (strict `[CTX]` per
`bitacora:jira-comment-format`) **only for likely Continue candidates** — tickets that
are `In Progress` *or* `updated` within the last 7 days. Do **not** fetch comments for
all ~50 tickets every morning (that is ~50 extra calls); other buckets rank from
search fields alone. (The 7-day deep-read cutoff is intentionally tighter than
`next.stale_days` (default 30, which gates the Needs-attention tail) — the deep-read
cutoff governs morning latency cost, not what counts as "stale".)

For each Continue candidate, pull the latest compliant `[CTX]`'s `Status` and `Next` lines.

## 5. Categorize

Degrade gracefully when a signal is missing — never invent one.

- **Continue where you left off** — `In Progress` with recent activity and/or a recent
  `[CTX]`; lowest pickup cost. A recent `[CTX] Next` is the strongest signal.
- **Ready to start** — not started, unblocked, specced. Rank by priority, then by
  outward `blocks` links (what it unblocks).
- **Quick wins** — small estimate (story points or time-tracking). If no estimate field
  is populated on a ticket, it simply isn't classified here — never guess.
- **Needs attention** (collapsed tail, one line) — blocked (`Blocked` status or inward
  `is blocked by` links and silent ≥ a few days) or stale (`updated` older than
  `next.stale_days`, default 30). For cleanup awareness, not selection.

## 6. Reason-to-pick

One phrase per ticket, grounded in an **actual signal** and citing it. Examples:

- *"near completion — last handoff: token refresh next"* (cites the `[CTX] Next` line)
- *"unblocks PROJ-1290 + PROJ-1291"* (cites outward `blocks` links)
- *"~1h, isolated"* (cites the estimate)

Never invent a reason not supported by the data. If nothing strong is available, a brief
status-and-activity phrase is fine (*"in progress, last touched 3d ago"*).

## 7. Recommend

Exactly one `★` arrow on the single best item: the top **Continue** candidate, else the
top **Ready to start**. Never mark more than one; never mark a Quick win or a
Needs-attention item.

## 8. Render the shortlist

3 buckets + a single-line **Needs attention** tail. Footer offers exactly two actions:
rehydrate the chosen ticket via the already-shipped `/bitacora:resume`, or re-run for a
different cut. See `examples/shortlist.txt` for the exact shape.

```
Picked up <N> tickets assigned to you. Today's shortlist:

━━ Continue where you left off ━━
★ PROJ-1234  <summary>                          [<Jira status>]
  Last handoff: "<latest [CTX] Status>" · <updated relative>
  → <reason-to-pick>

━━ Ready to start ━━
  PROJ-1287  <summary>                          [<Jira status>]  <Pn>
  → <reason-to-pick>

━━ Quick wins ━━
  PROJ-1311  <summary>                          [<Jira status>]  <Pn>
  → <reason-to-pick>

Needs attention: <K> blocked (<key>, <Nd> silent) · <M> stale (<key>, <Nd>)

→ Continue: /bitacora:resume <KEY>   ·   → re-run /bitacora:next for a different cut
```

Print, then stop. Read-only — no gate, no write.

## CLI path (github/gitlab)

On the **cli family** the scope *is* the current repo — do not run
`resolve-project-scope.sh` and do not consult `next.remote_project_map`.

Run `bitacora-tracker.sh doctor` first; on exit 5 surface the auth/install
guidance and stop.

Fetch candidates with:

```bash
TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" list-mine
```

This returns a normalized JSON array `[{number, title, labels, updatedAt, milestone}]`
scoped to the current repo.

Rank and categorize with the **same pickup-cost / readiness logic** as the Jira path
(steps 4–8 above), mapping fields as follows:

- **labels** stand in for Jira status (e.g. `in-progress` → Continue; `blocked` →
  Needs attention; no milestone/estimate → Quick win unavailable unless a label
  signals effort).
- **`updatedAt`** stands in for Jira's `updated` field (staleness, `next.stale_days`).
- There is no `[CTX]` deep-read for issues that have no comments matching the
  corpus selector — fall back to activity/label signals exactly as the Jira path
  falls back when no `[CTX]` is found.
- Issue numbers are bare integers (`#N`) — display as `#<number>  <title>` in the
  shortlist in place of `PROJ-<key>  <summary>`.

Render the same 3-bucket shortlist (Continue / Ready to start / Quick wins + Needs
attention tail). Footer offers `/bitacora:resume #<N>` (or the repo+number form) and
re-run.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup. Do not pretend a local-only fallback — without Jira read,
  there is nothing to pick from.
- **No project scope** (repo's remote slug not in `next.remote_project_map`, repo has
  no remote, or the project dir is not a git repo) and no `next.jql` override:
  **hard stop.** Relay `resolve-project-scope.sh`'s stderr verbatim (for an unmapped
  slug it names the detected slug and the exact YAML to add). Never degrade to the
  unscoped site-wide query — that surfaces another project's backlog with full
  confidence (#118).
- **Empty result:** say "nothing open assigned to you — inbox zero"; not an error.
- **Bad override JQL** (`next.jql` set, server returns a parse / field error): surface the
  offending query and Jira's error message; stop. Do **not** silently fall back to the
  default — that would hide the user's config mistake.
- **No `[CTX]` on Continue candidates:** fine — fall back to activity / status signals for
  the reason-to-pick; never block.
- **HTTP 429 / rate-limit during the bounded `[CTX]` read loop** (up to ~50 candidates
  is the cost ceiling that makes this realistic): stop fetching comments immediately,
  use available search-field signals for remaining Continue candidates, and surface a
  one-line rate-limit note in the footer. Do **not** retry mid-loop — back off until
  the next invocation.
- **Per-ticket `getJiraIssue` failure** (timeout, transient 5xx, isolated 403): log the
  failure, fall back to activity/status signals for that ticket's reason-to-pick, and
  continue the loop. One bad fetch should not abort the shortlist.
- **All tickets fall in Needs attention** (nothing fresh enough to surface above): still
  render the tail; recommend nothing (no `★`) and suggest the user pick from the tail
  manually or revisit `next.stale_days`.
- Strictly read-only: no transitions, comments, or other writes — even on error.

## Configuration

Reuses `project_key_pattern`, the strict `[CTX]` read modes, and `jira_cloud_id` from the
`bitacora:jira-comment-format` / handoff config (`${CLAUDE_PROJECT_DIR}/.bitacora.yml`
then `~/.claude/bitacora.yml`; absence is normal). Optional additions:

```yaml
next:
  # The default JQL is:
  #   assignee = currentUser() AND project = <KEY> AND statusCategory != Done ORDER BY updated DESC
  # where <KEY> comes from remote_project_map below. Override the whole query for
  # team-scoped pickers. Teammates must be referenced by Jira accountId —
  # `assignee in (...)` does not accept email addresses or usernames in Jira Cloud
  # (GDPR-era privacy migration). Use `lookupJiraAccountId` to resolve a teammate's
  # email → accountId once, then paste the accountId here.
  jql: ""            # overrides the default query verbatim when set (owns its own
                     # scoping; remote_project_map is not consulted); e.g.:
                     #   "assignee in (currentUser(), 5a17b8c2..., 5b22d9e3...) AND statusCategory != Done ORDER BY updated DESC"
  stale_days: 30     # "stale" threshold for the Needs-attention tail
  # Git-remote → Jira-project table that scopes the default query. The repo's
  # remote is normalized to a lowercase host/owner/repo slug and resolved here;
  # no entry → hard stop (never an unscoped dump). Keep the central table in
  # ~/.claude/bitacora.yml; a repo-level .bitacora.yml entry overrides the home
  # one for the same slug.
  remote_project_map:
    "github.com/org/ai-advisor-portal": "AT"
    "github.com/org/some-other-repo": "TESTING"
```
