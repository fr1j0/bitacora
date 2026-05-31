---
name: session-status
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary across five lenses — --for-self (terse recall), --for-eng (technical handoff), --for-ops (deploy/operational), --for-pm (plain-language stakeholder status), --for-exec (business/risk/cost). Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
---

Read a ticket's latest `[CTX]` state and synthesize an **audience-tailored summary**, then
print it and offer to copy it to the clipboard. This is a **sibling to
`bitacora:session-resume`**: same ticket resolution and the same strict `[CTX]` read, but
status produces a standalone summary *for a human reader* rather than rehydrating the
working agent. It is strictly **read-only** — it never writes to Jira or mutates Remember,
so there is no confirmation gate. Follow the **READ** rules in
`bitacora:jira-comment-format` (strict `status_extraction`) for extracting state.

## 1. Parse arguments

- **Mode flag:** one of `--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, `--for-exec`.
  An explicit flag always wins; with no flag, fall back to `status.default_mode` (built-in
  default `self`). An unknown flag or more than one mode flag is an error — name the five
  valid modes and stop; never guess. See the role→lens table in §5 for which lens a given
  role should pass.
- **Ticket key:** any `project_key_pattern` match in the arguments forces the target.
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
- **`--copy-as-slack`:** optional; re-render the summary in Slack `mrkdwn` and copy to
  clipboard automatically (skipping the prompt in step 6). Compatible with all five
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
  rules.

## 2. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order (identical to resume):

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct candidates
  surface, **list them and let the user pick**. Never guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 3. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the `jira_cloud_id`
override if configured, else ask. **If the MCP is absent, auth fails, or the site can't be
resolved, this is a hard stop** (see Error behavior) — status cannot do its job without
Jira read access.

## 4. Read the ticket (strict [CTX])

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments per
the **strict** READ rules in `bitacora:jira-comment-format`:

- Count only **compliant** `[CTX]` comments (trimmed text starts with `[CTX]` and carries `Status:` + `Next:` — the strict-prefix rule in `bitacora:jira-comment-format`).
- The **latest** compliant `[CTX]` is authoritative for `Status` and `Next`.
- Stitch up to `status.ctx_lookback` prior `[CTX]` comments (default 2) to build a short
  Done/progress trajectory.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Surface excluded counts separately (non-`[CTX]`, malformed); never silently drop. With
  `--include-all`, print the excluded comments too.

### 4a. Single ticket or epic?

The `getJiraIssue` response in §4 carries `fields.issuetype`. Branch on it:

- **Epic** (issue type name equals the configured `status.epic_type`, default `Epic`) → run the
  **aggregate path** (§4b + §5's *Aggregate render*). The epic's own `[CTX]` is not required.
- **Anything else** (Story / Bug / Subtask / …) → the single-ticket path of §4 + §5 stands as
  today; skip §4b entirely.

Only the epic issue type triggers aggregation. A Story with subtasks is **not** rolled up in
this version (it renders as a single ticket). This keeps the trigger unambiguous and matches the
"point `status` at an epic → portfolio view" rule.

## 5. Render for the selected mode

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve the ticket URL verbatim. The `pm` and `exec` lenses strip internal references like PR/commit hashes while keeping the ticket link (below); the other lenses keep the references. Rephrasing the `Status:`
value into plain language for `pm`/`exec` is allowed; inventing facts is not.

**Role → lens.** Five lenses cover the org; pass the flag for the reader's role:

| Lens | Flag | Roles it serves | Leads with / strips |
|------|------|-----------------|---------------------|
| self | `--for-self` | you | terse recall — latest Status + Next |
| eng  | `--for-eng`  | frontend, backend, full-stack, staff, AI staff, tech lead | contract, `Artifacts:`, `Model/Eval:`, `Decisions:`+tags; keeps PR/commit links |
| ops  | `--for-ops`  | devops, infra, MLOps | `Deploy/Ops:`, rollback, watch-list, `Impact:`; keeps links |
| pm   | `--for-pm`   | product, technical managers | plain language; confidence; `Risk:`/`Dependencies:` as asks; strips PR/commit hashes, keeps ticket link |
| exec | `--for-exec` | CTO, CRAIO | business/risk/cost + confidence; strips implementation detail, keeps ticket link |

A lens **degrades gracefully**: if the `[CTX]` lacks a section the lens would lead with, omit it silently (a UI ticket under `--for-ops` simply has no `Deploy/Ops:` to show).

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
