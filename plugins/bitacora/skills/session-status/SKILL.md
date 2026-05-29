---
name: session-status
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary — --for-self (terse recall), --for-eng (technical handoff), or --for-pm (plain-language stakeholder status). Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
---

Read a ticket's latest `[CTX]` state and synthesize an **audience-tailored summary**, then
print it and offer to copy it to the clipboard. This is a **sibling to
`bitacora:session-resume`**: same ticket resolution and the same strict `[CTX]` read, but
status produces a standalone summary *for a human reader* rather than rehydrating the
working agent. It is strictly **read-only** — it never writes to Jira or mutates Remember,
so there is no confirmation gate. Follow the **READ** rules in
`bitacora:jira-comment-format` (strict `status_extraction`) for extracting state.

## 1. Parse arguments

- **Mode flag:** `--for-pm`, `--for-eng`, or `--for-self`. An explicit flag always wins;
  with no flag, fall back to `status.default_mode` (built-in default `self`). An unknown
  flag or more than one mode flag is an error — name the valid modes and stop; never guess.
- **Ticket key:** any `project_key_pattern` match in the arguments forces the target.
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
- **`--copy-as-slack`:** optional; re-render the summary in Slack `mrkdwn` and copy to
  clipboard automatically (skipping the prompt in step 6). Compatible with all three
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

## 5. Render for the selected mode

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve the ticket URL verbatim. PM mode is the only one that strips anything — internal references like PR/commit hashes — and it still keeps the ticket link (below). Rephrasing the `Status:`
value into plain language for PM is allowed; inventing facts is not.

### --for-self (default) — terse personal recall: latest Status, no Done trajectory (use --for-eng for that). Jargon + PR links fine.

```
PROJ-1234 "<title>" — <Jira status>
Left off:   <latest Status>
Next:       <Next bullets>
Decisions:  <decision bullets>        (only if present)
Blockers:   <bullets>                 (only if present)
```

### --for-eng — technical teammate handoff (keep links, rationale, detail)

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

### --for-pm — plain-language stakeholder status (strip jargon and PR/commit hashes, but keep the ticket link; lead with state/risk)

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:        <on track / blocked / in progress — plain words>
Progress:      <outcome-oriented Done across the lookback, jargon stripped>
What's next:   <Next in plain language>
Risks / needs: <Blockers + Open questions, framed as asks>   (only if present)
```

### Slack mrkdwn rendering (when `--copy-as-slack` is set)

Render the **same content** as the chosen mode (`--for-self` / `--for-eng` / `--for-pm`),
but with Slack `mrkdwn` conventions instead of Markdown:

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

See `examples/self.txt`, `examples/eng.txt`, `examples/pm.txt` — the same `[CTX]` rendered
in all three modes.

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
  default_mode: self     # self | eng | pm — overrides the built-in default mode
```
