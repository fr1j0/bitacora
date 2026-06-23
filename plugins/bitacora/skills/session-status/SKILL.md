---
name: session-status
description: Synthesize one ticket's latest [CTX] into an audience-tailored summary across five lenses (--for-self/eng/ops/pm/exec). Supports jira (MCP) and github/gitlab (cli). Epics render as a single node (their own [CTX]); multi-ticket and epic-rollup reads live in /bitacora:digest. Read-only; prints and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
---

Read a ticket's latest `[CTX]` state and synthesize an **audience-tailored summary**, then
print it and offer to copy it to the clipboard. This is a **sibling to
`bitacora:session-resume`**: same ticket resolution and the same strict `[CTX]` read, but
status produces a standalone summary *for a human reader* rather than rehydrating the
working agent. It is strictly **read-only** — it never writes to Jira or mutates Remember,
so there is no confirmation gate. Follow the **READ** rules in
`bitacora:jira-comment-format` (strict `status_extraction`) for extracting state.

## Resolve the tracker (first)

Before any ticket lookup, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tracker.sh"   # → github | gitlab | jira
```

- **exit 4** (not a git repo / no remote / no explicit `tracker:`): tell the user to set
  `tracker:` in `.bitacora.yml` and stop.
- **exit 0**: branch once on **family** and keep that branch for all subsequent steps.

See `bitacora:tracker-adapter` for the capability table and verb reference.

### jira family (MCP)

Continue with steps 1–6 below as written (Atlassian MCP, `getJiraIssue`, etc.).

### cli family (github / gitlab)

Run `doctor` first:

```bash
TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" doctor
```

- **exit 5:** surface the auth/install guidance from stdout and **stop** (hard stop —
  same severity as a missing Atlassian MCP). No Jira call is made.
- **exit 0:** fetch the `[CTX]` corpus:

```bash
TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" comments <id>
# → [{author, createdAt, body}]
```

Grep bodies for the `[CTX]` marker exactly as the jira arm does; take the comment date
from `createdAt` (never from the body). The lookback stitching, staleness freshness line,
and all five audience lenses in steps 4–5 are **unchanged** — apply them to the
cli-fetched corpus. Step 3 (Atlassian site resolution) is **skipped entirely** on the cli
family. Jump directly to step 4 after fetching.

## 1. Parse arguments

- **Mode flag:** one of `--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, `--for-exec`.
  An explicit flag always wins; with no flag, fall back to `status.default_mode` (built-in
  default `self`). An unknown flag or more than one mode flag is an error — name the five
  valid modes and stop; never guess. See the *Audience lenses* table in
  `bitacora:jira-comment-format` for which lens a given role should pass.
- **Ticket key:** any `project_key_pattern` match in the arguments forces the target.
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
- **`--copy-as-slack`:** optional; re-render the summary in Slack `mrkdwn` and copy to
  clipboard automatically (skipping the prompt in step 6). Compatible with all five
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
  rules.

**Single-ticket only — multi-ticket reads moved to `/bitacora:digest`.** If the arguments
carry a scope selector (`--mine`, `--sprint`, `--jql`), a query lens (`--blocked`,
`--standup`, `--since`), or **two or more** `project_key_pattern` keys, do not render. Print
and stop, echoing the flags back so the redirect is copy-pasteable:

```
Multi-ticket reads now live in /bitacora:digest.
Try:  /bitacora:digest <the same flags/keys the user passed>
```

## 2. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order (identical to resume):

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct candidates
  surface, **list them and let the user pick**. Never guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 3. Resolve the Atlassian site (jira family only)

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the `jira_cloud_id`
override if configured, else ask. **If the MCP is absent, auth fails, or the site can't be
resolved, this is a hard stop** (see Error behavior) — status cannot do its job without
Jira read access. Skip this step on the cli family.

## 4. Read the ticket (strict [CTX])

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments per
the **strict** READ rules in `bitacora:jira-comment-format`:

- Count only **compliant** `[CTX]` comments (trimmed text starts with `[CTX]` and carries `Status:` + `Next:` — the strict-prefix rule in `bitacora:jira-comment-format`).
- The **latest** compliant `[CTX]` is authoritative for `Status` and `Next`.
- Stitch up to `status.ctx_lookback` prior `[CTX]` comments (default 2) to build a short
  Done/progress trajectory.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Also capture the ticket's `updated` timestamp (top-level field; request it alongside
  comments) — needed by the staleness `Freshness:` line in §5.
- Surface excluded counts separately (non-`[CTX]`, malformed); never silently drop. With
  `--include-all`, print the excluded comments too.

### 4a. Epics render as a single node

`/bitacora:status` does **not** roll up epics — that is `/bitacora:digest`'s job. An epic key
flows through the single-ticket path like any other ticket: render its **own** `[CTX]` (the
status comment on the epic itself) through the chosen lens. When the epic has no own `[CTX]`,
fall to the no-`[CTX]` edge (below) and add a pointer:
`For the children rollup, use /bitacora:digest <EPIC-KEY>`.

## 5. Render for the selected mode

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve the ticket URL verbatim. The `pm` and `exec` lenses strip internal references like PR/commit hashes while keeping the ticket link (below); the other lenses keep the references. Rephrasing the `Status:`
value into plain language for `pm`/`exec` is allowed; inventing facts is not.

**Audience lens.** Apply the lens for the reader's role per the *Audience lenses* table in
`bitacora:jira-comment-format` (the canonical altitude definitions). The single-ticket render
templates for each lens follow below.

### Freshness (all single-ticket lenses)

Independent of the audience lens, run the drift check on the resolved ticket using the
latest compliant `[CTX]`'s `created` epoch and the ticket's `updated` epoch (from §4), with
the shared `staleness_grace` (default `2d`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/staleness-check.sh" \
  --ctx-epoch "<latest-ctx-created-epoch>" \
  --updated-epoch "<ticket-updated-epoch>" \
  --grace "<staleness_grace>"
```

If it returns `stale Nd`, append one line to the render (after the lens's body):

```
Freshness: behind <N>d (ticket updated after the latest [CTX])
```

Omit the line entirely when `fresh` (no positive-state noise), when the ticket has no
compliant `[CTX]`, or when `updated` is missing. This is read-only and advisory.

### --for-self (default) — terse personal recall: latest Status, no Done trajectory (use --for-eng for that). Jargon + PR links fine.

```
PROJ-1234 "<title>" — <Jira status>
Left off:   <latest Status, incl. (confidence: …) if present>
Next:       <Next bullets>
Decisions:  <decision bullets, keep [precedent]/[debt]/[blast-radius] tags>  (only if present)
Risk:       <Risk bullets>            (only if present)
Blockers:   <bullets>                 (only if present)
```

### --for-eng — technical teammate handoff (keep links, rationale, detail)

```
PROJ-1234 "<title>" — <Jira status>
https://<site>/browse/PROJ-1234

Impact:     <Impact surfaces>          (only if present)
Done recently:                         (only if present)
- <Done across the lookback window>
Decisions:                             (only if present)
- <decision + rationale, keep [precedent]/[debt]/[blast-radius] tags>
Model/Eval:                            (only if present)
- <version, eval delta, inference $, model rollback>
Artifacts:                             (only if present)
- <PR / design / run / dashboard / runbook links>
Dependencies:                          (only if present)
- <cross-team / cross-ticket items>
Next:
- <Next bullets>
Risk / blockers / open questions:      (only if present)
- <Risk + Blockers + open questions>
```

### --for-ops — deploy / operational (devops, infra, MLOps; keep links, lead with operational posture)

```
PROJ-1234 "<title>" — <Jira status>
https://<site>/browse/PROJ-1234

Impact:      <Impact surfaces>          (only if present)
Deploy/Ops:                             (only if present)
- <environment, feature flag, rollback plan, infra $>
Watch:                                  (only if present — the watch-list from Deploy/Ops)
- <what to monitor>
Model rollback: <rollback plan from Model/Eval — only if present>
Next:
- <Next; deploy/promote/cutover steps first if present>
Risk / blockers:                        (only if present)
- <Risk + Blockers>
```

If the ticket has no `Deploy/Ops:` or `Model/Eval:`, ops degrades to the latest Status + Next (nothing operational to lead with).

### --for-pm — plain-language stakeholder status (strip jargon and PR/commit hashes, but keep the ticket link; lead with state/risk)

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:        <on track / at risk / blocked — plain words> (confidence: <cue, if present>)
Progress:      <outcome-oriented Done across the lookback, jargon stripped>
What's next:   <Next in plain language>
Risks / needs: <Risk + Blockers + Dependencies + Open questions, framed as asks>   (only if present)
```

### --for-exec — business / risk / cost (CTO, CRAIO; strip implementation detail, keep the ticket link, lead with state and money)

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:          <on track / at risk / blocked — plain words> (confidence: <cue, if present>)
Business impact: <what this delivers, in plain language, derived from Status/Done — no implementation detail. If the [CTX] states no concrete outcome, give the ticket's goal plainly; do not invent results, ratings, or compliance/revenue claims.>
Cost:            <infra + inference $ from Deploy/Ops or Model/Eval, only if present>
Risks / needs:   <Risk + Blockers + Dependencies, framed as decisions or asks>   (only if present)
Next milestone:  <Next as an outcome-level goal; if Next is all implementation detail, summarize the goal>
```

Strip PR/commit hashes, file paths, flag names, and tool jargon. Keep the ticket link. Invent nothing — if there is no cost line in the `[CTX]`, omit `Cost:`.

### Slack mrkdwn rendering (when `--copy-as-slack` is set)

Render the **same content** as the chosen mode (`--for-self` / `--for-eng` / `--for-ops` /
`--for-pm` / `--for-exec`), but with Slack `mrkdwn` conventions instead of Markdown:

- `*bold*` instead of `**bold**` (single asterisks for emphasis)
- `<https://example.com|label>` instead of `[label](https://example.com)` (Slack
  angle-bracket link form with `|` as the label separator)
- Plain bulleted lines (`• item` with U+2022) instead of Markdown lists (`- item`) —
  Slack renders Markdown lists inconsistently
- **No Markdown tables.** If a mode would have used a table (none currently do, but
  defensive), fall back to one bullet per row
- Surface the ticket key + URL prominently as the leading line, e.g.:
  `*PROJ-1234* — <https://site/browse/PROJ-1234|OAuth callback handling>`

All read semantics (strict `[CTX]` extraction, ticket resolution, error handling) are
unchanged from the default render path.

See `examples/self.txt`, `examples/eng.txt`, `examples/ops.txt`, `examples/pm.txt`,
`examples/exec.txt` — the same enriched `[CTX]` (CHURN-42) rendered in all five lenses.

## 6. Print, then offer a clipboard copy

Print the rendered summary into the conversation. Then:

- **Default** (no `--copy-as-slack`): offer to copy to clipboard, gated by user
  confirmation. **Read-only, no Jira write, no gate beyond the copy prompt.**
- **`--copy-as-slack` set:** **always** copy to clipboard (skip the prompt — the user
  has declared intent). If clipboard delivery fails (no `pbcopy` / `wl-copy` / `xclip` /
  `clip` available), print a one-line note that the rendered text was not copied; the
  printed summary still stands on its own.

Clipboard is best-effort: pipe the rendered text to the first available of `pbcopy`
(macOS), `wl-copy` or `xclip -selection clipboard` (Linux), or `clip` (Windows). If
none is found in the default path, skip the offer silently. With `--copy-as-slack`,
surface the absence as a one-line note (see above) so the user knows to copy manually.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; do not pretend a local-only fallback.
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` so future summaries have something to
  read.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry with
  a different key. No retry loop.
- **No ticket resolved:** say so; suggest passing a key.
- **Invalid / conflicting mode flag:** error listing the valid modes; do not guess.
- **Multi-ticket flags / 2+ keys:** redirect to /bitacora:digest (see §1).

## Configuration

Reuses `project_key_pattern`, the compliance modes (strict for status), and `jira_cloud_id`
from the `bitacora:jira-comment-format` / handoff config
(`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is normal).
Two optional additions:

```yaml
status:
  ctx_lookback: 2        # prior [CTX] stitched for the Done/progress trajectory
  default_mode: self     # self | eng | ops | pm | exec — overrides the built-in default mode
```

See `bitacora:jira-comment-format` for the `digest.*` keys (epic rollup + multi-ticket scope).
