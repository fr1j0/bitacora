# `/status` ÷ `/digest` split — design

**Date:** 2026-06-06
**Status:** approved (brainstorm)
**Scope:** `plugins/bitacora` — split the multi-ticket / aggregate half of `session-status`
into a new `session-digest` skill + `/bitacora:digest` command, leaving `session-status`
as a single-ticket read.

## Problem

`/bitacora:status` has accreted two distinct jobs:

- **Point-read** — "tell me about *this ticket*." Input is a known target; output is a
  synthesis through five audience lenses (`--for-self/eng/ops/pm/exec`). This was the
  command's original purpose.
- **Survey** — "scan *my landscape* and surface a pattern." Input is a *question*
  (`--mine --standup`, `--blocked`, the cross-ticket digest, epic rollup, and the planned
  `--debt`/`--risk`); output is a report across a *set* of tickets.

These are different mental models, inputs, and outputs, and the survey side is where all
future growth lives. Bundling both has made the `session-status` spec large and conceptually
overloaded. The audience lenses are **not** the problem (same data, different altitude — they
stay unified); the problem is the singular-vs-aggregate conflation.

## Decision

Split along the **singular vs aggregate** seam into two commands that share the `[CTX]`
read discipline (already centralized in `bitacora:jira-comment-format`) but own different
jobs.

### `/bitacora:status` (alias `/bit:status`) — singular

One ticket's own `[CTX]`, rendered through the five audience lenses, plus the
freshness/staleness signal and `--copy-as-slack`. Resolution order unchanged: explicit key
→ current branch → recent checkouts.

- **Multi-ticket invocation** (`--mine`, `--sprint`, `--jql`, two or more
  `project_key_pattern` keys, `--blocked`, `--standup`, `--since`) → **clean error + pointer**,
  no render:

  ```
  Multi-ticket reads now live in /bitacora:digest.
  Try:  /bitacora:digest --mine --standup
  ```

  The pointer echoes back the flags the user passed (`--mine --standup` above) so the
  redirect is copy-pasteable. A single exit; never a partial render.

- **Epic key** → rendered as a **single node** (the epic's *own* `[CTX]`), flowing through
  the normal single-ticket path. No children rollup. When the epic has no own `[CTX]` (the
  common case), print the orientation line (workflow status + title) and a pointer:
  `For the children rollup, use /bitacora:digest <EPIC-KEY>`. This is the consistent
  application of the seam — `/status` is "this node," `/digest` is "the aggregate" — and it
  *removes* the epic-detection branch from `session-status` rather than adding a guard.

### `/bitacora:digest` (alias `/bit:digest`) — aggregate

Every many-ticket read:

- **Epic rollup** — point at an epic key → the children aggregate (health, confidence
  distribution, risk concentration, dependency graph, cost rollup, coverage), rendered in the
  chosen lens; epic default lens `exec` (from `digest.epic_default_mode`).
- **Scopes** — `--mine`, `--sprint`, `--jql "<q>"`, or two or more keys — through **query
  lenses**: `--blocked` (what's stuck), `--standup [--since 1d|2d|last-working-day]` (what
  moved, day-bucketed), or the default cross-ticket digest. The five `--for-*` lenses still
  select altitude. Future `--debt` / `--risk` land here.
- `--copy-as-slack` and `--include-all` carry over.

**Mirror guard.** A **single non-epic** explicit key passed to `/digest` → **error + pointer**
to `/status` (no render):

```
That's a single ticket — use /bitacora:status AT-1234.
```

A *scope* (`--mine` etc.) that happens to match exactly one ticket still renders a
(degenerate) one-item digest — the user asked for a survey, and it surveyed. The mirror guard
fires only for an explicit single non-epic **key**, not for a scope that resolves to one.

## Architecture

Two skills; shared read, no duplicated render logic.

| Unit | Responsibility |
|------|----------------|
| `skills/session-status/SKILL.md` | Single-ticket resolution + strict `[CTX]` read + the five audience-lens render templates + freshness. Epic key → single-node read. Multi-ticket flags → error+pointer. |
| `skills/session-digest/SKILL.md` (new) | Aggregate target resolution (epic key **or** scope) + the epic/scope aggregate signals + the aggregate render templates + the query lenses (`--blocked`, `--standup`) + cross-ticket digest. Single non-epic key → error+pointer. |
| `skills/jira-comment-format/SKILL.md` | Unchanged shared dependency: strict `[CTX]` extraction (READ rules) used by both. |

**Audience-lens altitude** (what each of self/eng/ops/pm/exec leads with and strips) is the
one piece both skills need. To avoid duplication, the canonical five-lens table lives in
**`session-status`** (where the single-ticket renders are richest), and `session-digest`
references it by name ("render the aggregate signals in the chosen lens, per the audience-lens
table in `bitacora:session-status`"), supplying only the aggregate-specific shaping per lens.

**Shared scripts** stay in `scripts/` and are now called by `/digest`:
`since-window.sh`, `standup-buckets.sh`, `staleness-check.sh` (staleness markers on digest
index entries).

### What moves from `session-status` → `session-digest`

- §2a scope resolution (the `--mine`/`--sprint`/`--jql`/2+-keys JQL table + cap handling).
- §4b epic-children read; §4c scope-set read.
- The aggregate **signals** computation and the aggregate **render** templates (all five
  lenses) including `By ticket:` / `By child:`.
- §7 query lenses (`--blocked`, `--standup`) and the cross-ticket digest, plus the
  staleness-marker and Slack ticket-key-link rules **for index entries**.
- Fixtures: `examples/multi-aggregate.txt`, `multi-aggregate-slack.txt`, `multi-blocked.txt`,
  `multi-standup.txt`, `epic-exec.txt`, `epic-eng.txt` → move to
  `skills/session-digest/examples/`.
- `scripts/test-multi-status-fixtures.sh` → `scripts/test-digest-fixtures.sh` (paths
  repointed; assertions unchanged).

### What stays in `session-status`

§4 single-ticket read, §4a removed (no epic branch), §5 single-ticket render templates (five
lenses) + freshness, `examples/self.txt`/`eng.txt`/`ops.txt`/`pm.txt`/`exec.txt`,
`--copy-as-slack` single-ticket rendering.

## Configuration

`status.*` splits; `digest.*` is read with **fallback to the old `status.*` key** so existing
configs don't silently break:

```yaml
status:
  ctx_lookback: 2        # stays — single-ticket Done/progress stitch
  default_mode: self     # stays — single-ticket default lens

digest:
  epic_type: Epic            # was status.epic_type
  epic_children_cap: 50      # was status.epic_children_cap
  epic_default_mode: exec    # was status.epic_default_mode
  multi_fanout_cap: 25       # was status.multi_fanout_cap
  default_mode: self         # default lens for a scope read (was the multi default)
```

Resolution rule for each moved key: read `digest.<key>`; if absent, read the legacy
`status.<key>`; if both absent, the built-in default. Documented in
`jira-comment-format`'s Configuration block.

## Surfaces to update

- **New:** `commands/digest.md`, `alias/bit-digest.md`, `skills/session-digest/SKILL.md`
  (+ `examples/`), `scripts/test-digest-fixtures.sh`.
- **Slim:** `commands/status.md`, `skills/session-status/SKILL.md`, `alias/bit-status.md`.
- **Register** the new skill + command per the plugin's discovery mechanism (verify whether
  `plugin.json` enumerates skills/commands or auto-discovers; update if it enumerates).
- **`help`** command/skill gains a `/bitacora:digest` entry and re-categorizes `/status` as
  single-ticket.
- **READMEs** (`README.md`, `plugins/bitacora/README.md`) document the two-command model.
- **`docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`** — M1–M9 (multi-ticket / epic) and the
  Slack/staleness items re-point to `/digest`; the single-ticket lens checks stay under
  `/status`; add the two new guard checks (status↔digest redirects).
- **CHANGELOG** — v0.7.0 entry.

## Testing

- `scripts/test-digest-fixtures.sh` — the existing deterministic multi/epic/standup/blocked
  render-contract assertions, carried over verbatim against the relocated fixtures.
- **New `/status` guard assertions** (lightweight, prose-contract — verified in the fixture
  lint where possible and the manual-acceptance checklist otherwise): multi-ticket flags →
  error+pointer; epic key → single-node render (own `[CTX]`, else orientation + pointer).
- **New `/digest` mirror-guard** assertion: single non-epic explicit key → error+pointer to
  `/status`.
- Helpers (`since-window.sh`, `standup-buckets.sh`, `staleness-check.sh`) — already unit-tested,
  unchanged.

## Error / edge behavior

- `/status` + any multi-ticket flag or 2+ keys → error+pointer to `/digest` (Q1).
- `/status <epic>` → epic's own `[CTX]` as a single node; no own `[CTX]` → orientation +
  pointer to `/digest` (Q2-A).
- `/digest` + single non-epic explicit key → error+pointer to `/status` (mirror guard).
- `/digest` scope matching zero → existing "matched nothing" message.
- `/digest` scope matching exactly one → degenerate one-item digest (no redirect).
- `/digest <epic>` with no children → existing "epic has no children" behavior.
- Atlassian MCP absent / auth fails → hard stop (unchanged), in both commands.

## Migration

This relocates the multi-ticket flags off `/status` — a breaking change to a v0.6.0 surface
that is days old. Acceptable at `0.x` alpha with a tiny install base; the clean error+pointer
makes the move self-documenting at the call site, and `digest.*`-with-`status.*`-fallback
keeps existing config working. Ships as a **minor** bump: **v0.7.0**.

## Out of scope

- `--debt` / `--risk` lenses (Phase B; they will land in `/digest`, not `/status`).
- `--board` (still reserved/unsupported).
- Any change to the single-ticket audience-lens *content* or the `[CTX]` format itself.
