---
name: session-status
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary across five lenses (--for-self/eng/ops/pm/exec), roll up an epic across its children, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) through a query lens (--blocked, --standup) or the default cross-ticket digest. Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
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
  For an **epic** target with no flag, the default is `status.epic_default_mode` (default `exec`),
  not `self` — see §5's *Aggregate render*.
- **Ticket key:** any `project_key_pattern` match in the arguments forces the target.
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
- **`--copy-as-slack`:** optional; re-render the summary in Slack `mrkdwn` and copy to
  clipboard automatically (skipping the prompt in step 6). Compatible with all five
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
  rules.
- **Scope (multi-ticket).** A scope selector switches `status` from a single ticket to a
  multi-ticket read: `--mine`, `--sprint`, `--jql "<JQL>"`, or **two or more**
  `project_key_pattern` keys in the arguments. Multi-ticket mode activates **iff** a scope
  flag is present or 2+ keys are passed — a single key (including an epic key) keeps the
  existing single-ticket / epic-rollup behavior verbatim. `--board <id|name>` is **reserved for a
  later phase**: if passed, say it is not yet supported and stop (do not silently fall back).
- **Query lens (multi-ticket only).** `--blocked` or `--standup` selects *what to surface*
  across the scope; with neither, the default is the cross-ticket digest (§7). Query lenses
  compose with the `--for-*` audience lens, which still selects altitude. A query lens in
  single-ticket mode is an error — name the multi-ticket scopes and stop. Two query lenses
  at once is an error.
- **`--since <token>` (only with `--standup`).** `<token>` ∈ `<N>d` (e.g. `1d`, `2d`) or
  `last-working-day` (the default). If passed without `--standup`, ignore it with a one-line
  note.

The multi-ticket default audience is `self`, like the single-ticket default. `--blocked`,
`--standup`, and the aggregate all honor an explicit `--for-*`; `--debt`/`--risk` will read
naturally at `--for-eng`/`exec` when they land in Phase B.

## 2. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order (identical to resume):

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct candidates
  surface, **list them and let the user pick**. Never guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

### 2a. Resolve a multi-ticket scope (when scope mode is active)

When §1 detected a scope selector or 2+ keys, **skip §2's single-target resolution** and
resolve a *set* of keys. Resolve the Atlassian site first (§3 — needed to run JQL), then
build the list via `searchJiraIssuesUsingJql`, requesting `summary,issuetype,status`:

| Scope | JQL |
|-------|-----|
| explicit keys (2+) | `key IN (KEY-1, KEY-2, …) ORDER BY updated DESC` |
| `--mine` | `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC` |
| `--sprint` | `assignee = currentUser() AND sprint IN openSprints() ORDER BY updated DESC` |
| `--jql "<q>"` | the user's `<q>` verbatim; append `ORDER BY updated DESC` only if `<q>` has no `ORDER BY` |

**Cap the set** at `status.multi_fanout_cap` (default 25). If the JQL matched more, take the
first N in `updated DESC` order and **surface the truncation** in the render
(`showing N of M — narrow with --jql`); never silently drop. Edge cases:

- **Zero matches** → say so plainly and stop (e.g. `--mine matched no open tickets`).
- **Exactly one match** → treat it as a single target and proceed from §4 (if it is an epic, §4a still rolls it up); a one-ticket set needs no digest.
- **JQL error** (bad `--jql`, unknown field) → surface the error verbatim and stop; no retry loop.

## 3. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the `jira_cloud_id`
override if configured, else ask. **If the MCP is absent, auth fails, or the site can't be
resolved, this is a hard stop** (see Error behavior) — status cannot do its job without
Jira read access.

## 4. Read the ticket (strict [CTX])

**Multi-ticket mode (§2a) bypasses this section.** §4/§4a/§4b below are the single-ticket
and epic paths; when a scope set was resolved, skip straight to §4c.

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

### 4b. Read the epic's children (aggregate path)

Runs only when §4a found an Epic. Read-only throughout.

1. **List children via JQL.** Call `searchJiraIssuesUsingJql` with
   `jql: "parent = <EPIC-KEY> ORDER BY created ASC"`, requesting `summary,issuetype,status`.
   If that errors or returns zero, retry once with `jql: "\"Epic Link\" = <EPIC-KEY> ORDER BY created ASC"`
   (classic-project epics use the `Epic Link` field instead of `parent`). If both forms fail,
   see *Error / edge behavior*.
2. **Cap the set.** Read at most `status.epic_children_cap` children (default 50). If the epic has
   more, read the first N by creation order and **surface the truncation** in the render
   (`showing first N of T children`) — never silently drop.
3. **Strict-read each child.** For each child, `getJiraIssue` **requesting comments** and extract
   its latest compliant `[CTX]` per the strict READ rules in `bitacora:jira-comment-format` (same
   rules §4 uses). Classify each child as:
   - **reporting** — has a compliant `[CTX]` (its latest is authoritative for that child);
   - **no-`[CTX]`** — no compliant `[CTX]` yet;
   - **malformed** — has a `[CTX]` attempt missing `Status:`/`Next:`.
4. **Never silently drop.** Carry the no-`[CTX]` and malformed counts into the render
   (`Not yet reporting: …`, and a malformed tally), exactly like §4's excluded-count discipline.

Child reads are independent; one child's 404 / permission error is isolated — count it as
unreadable and continue with the rest.

### 4c. Read the scope set (multi-ticket path)

Runs when §2a resolved a set. For each key, `getJiraIssue` **requesting comments** and
extract its latest compliant `[CTX]` per the strict READ rules in `bitacora:jira-comment-format`
— identical classification to §4b: **reporting** (has a compliant `[CTX]`, its latest is
authoritative), **no-`[CTX]`**, or **malformed**. For each reporting ticket also capture its
latest-`[CTX]` `created` timestamp from comment metadata (needed by `--blocked` staleness and
`--standup` windowing). Reads are independent — one key's 404 / permission error is isolated;
count it **unreadable** and continue. Carry the no-`[CTX]` / malformed / unreadable tallies
into every §7 render as the coverage line, exactly like §4b's excluded-count discipline.

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
- **Ticket-key links in index entries** (the multi-ticket / aggregate `By ticket:` / `By child:`
  / `--blocked` / `--standup` `Moved:` lists): render the leading key as
  `<https://<site>/browse/KEY|KEY>`. This is the **only** place keys are linked — printed
  renders leave them bare. Inline / tail keys stay bare even here.

All read semantics (strict `[CTX]` extraction, ticket resolution, error handling) are
unchanged from the default render path.

### Aggregate signals (epic)

When §4a routed to the aggregate path, compute these from the children's `[CTX]`s (facts only —
the same **no-invention** rule applies; never synthesize a number or claim a child did not report):

- **Per-child line** — `CHILD-KEY "<title>" — <status> (confidence)`, one per reporting child.
- **Health** — a one-line rollup: if any child is `Blockers:`-blocked → *blocked*; else if any child
  has `confidence: low` or an open `Risk:` → *at risk*; else *on track*. State the reason briefly.
- **Confidence distribution** — tally the `(confidence: …)` cues across reporting children
  (`high ×A · medium ×B · low ×C`). Omit children that carry no cue from the tally.
- **Risk concentration** — the children carrying `Risk:` or `Blockers:`, listed risk-bearing first,
  one line each. Empty if none.
- **Dependency graph** — parse each child's `Dependencies:`; when a dependency names another child
  of the same epic, render it as an edge `CHILD-A → CHILD-B (what blocks what)`. Cross-epic deps are
  listed as plain bullets. Empty if none.
- **Cost rollup** — sum the numeric infra + inference `$` values across children that report them;
  label it **approximate** and note how many children contributed. Omit if no child reports cost.
- **Coverage** — `N children (M reporting, K no [CTX], J malformed)`, plus any truncation note from
  §4b. Always shown so the reader knows the rollup's basis.

### Aggregate render

Render the aggregate signals **in the chosen lens**. **Epic default lens:** when the target is an
epic and no `--for-*` flag was given, use `status.epic_default_mode` (default `exec`) instead of the
single-ticket default `self` — a portfolio's natural audience is leadership. An explicit flag always
wins. Lenses degrade gracefully: omit any signal that is empty (no risks → no `Top risks:` block).

**Ticket-key links:** `By child:` / `By ticket:` entry keys print **bare**; they become Slack
links only under `--copy-as-slack`, per §7's *Ticket-key links (Slack only)* rule.

**--for-exec** (default for epics):

```
EPIC-1 "<title>" — Epic · <coverage>
https://<site>/browse/EPIC-1

Health:       <one-line rollup + reason>
Confidence:   high ×A · medium ×B · low ×C   (across M reporting children)
Top risks:                                   (omit if none)
- <CHILD-KEY: risk one-liner, business framing; risk-bearing children first>
Dependencies:                                (omit if none)
- <CHILD-A → CHILD-B: what blocks what>
Cost:         <summed infra + inference $ — approximate, from K children>   (omit if none)
By child:
- <CHILD-KEY "<title>" — plain status (confidence)>
Not yet reporting: <CHILD-KEY, …>            (omit if none)
```

**--for-eng**:

```
EPIC-1 "<title>" — Epic · <coverage>
https://<site>/browse/EPIC-1

Dependency graph:                            (omit if none)
- <CHILD-A → CHILD-B (what blocks what)>
By child:
- <CHILD-KEY "<title>" — Status; next: <first Next bullet>; risk: <Risk if any, else —>>
Open risks / blockers:                       (omit if none)
- <CHILD-KEY: risk/blocker>
Excluded: <K no [CTX] (J malformed)>         (omit if zero)
```

**--for-ops / --for-pm / --for-self** reuse the same aggregate structure, shaped by that lens's
single-ticket emphasis:
- **ops** — `By child` leads each reporting child with its `Deploy/Ops:` posture (env/flag/rollback)
  and a combined `Watch:` list across children; keeps links. Children with no `Deploy/Ops:` show
  Status + Next only.
- **pm** — plain-language portfolio: `Health` and `Confidence` first, `By child` as one plain
  sentence each, `Risks / needs` framed as asks; strip PR/commit hashes, keep the ticket link.
- **self** — terse: `Health` line + the `By child` list (plus the `Not yet reporting:` / coverage tail — never drop no-`[CTX]` tickets).

All five keep the coverage figure in the header line (`Epic · <coverage>`) so the reader knows how complete the rollup is.

See `examples/self.txt`, `examples/eng.txt`, `examples/ops.txt`, `examples/pm.txt`,
`examples/exec.txt` — the same enriched `[CTX]` (CHURN-42) rendered in all five lenses; and
`examples/epic-exec.txt`, `examples/epic-eng.txt` — an epic (CHECKOUT-100) rolled up across its
children.

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

## 7. Multi-ticket render (query lenses)

Runs only on the multi-ticket path (§2a + §4c). The **query lens** (§1) selects the pivot;
the `--for-*` **audience lens** still selects altitude. Facts only — the same no-invention
rule as §5. Every render carries a **coverage** line —
`N tickets (M reporting, K no [CTX], J malformed, U unreadable)`, dropping any zero terms —
plus any `showing N of M — narrow with --jql` truncation note from §2a.

**Ticket-key links (Slack only).** Printed renders show **bare** keys. Only under
`--copy-as-slack` does each per-ticket **index entry** — the `By ticket:` / `By child:` lists
(rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup` `Moved:`
entries — render its **leading key** as a Slack link `<https://<site>/browse/KEY|KEY>`, where
`<site>` is the Atlassian site resolved in §3. Even in Slack, inline mentions (`Health:`,
`Top risks:`, `Dependencies:` edges) and the `Not yet reporting:` / `No movement:` tails stay
bare. See step 5's *Slack mrkdwn rendering*.

### Default (no query flag) — cross-ticket digest

Compute the **Aggregate signals** exactly as the epic path does (health, confidence
distribution, risk concentration, dependency graph, cost rollup, coverage), but over the
resolved set instead of an epic's children, and render them with the **Aggregate render**
template for the chosen lens (default `self`). Three things differ from the epic path:
the header names the **scope** rather than an epic, there is no parent-epic link, and
`By child:` becomes **`By ticket:`** throughout (a scope has no parent–child relationship).

Header form by scope: `Scope: --mine`, `Scope: --sprint`, `Scope: <N> keys`, or
`Scope: custom JQL` — followed by ` — <coverage>`. See `examples/multi-aggregate.txt`
(the `--for-self` digest over a 4-ticket `--mine` scope).

### --blocked — what's stuck

Filter the set to tickets whose latest `[CTX]` carries a `Blockers:` **or** `Dependencies:`
section. Sort **most-stale first** (oldest latest-`[CTX]` `created`). Omit every ticket with
neither section. `stale <Nd>` = whole days between that ticket's latest-`[CTX]` `created` and
now. Render in the chosen lens (default `self`):

```
Blocked — <coverage>

- <KEY> "<title>" — <Jira status> · stale <Nd>
    Blocked on: <Blockers bullets>
    Waiting on: <Dependencies bullets — who/what>          (omit this line if no Dependencies)
- …
Clear: <count> of <M reporting> have no blockers/deps.
```

If **no** ticket in the set is blocked, print `Nothing blocked across <coverage>.` and stop.
`--for-pm`/`--for-exec` strip PR/commit hashes and frame `Waiting on:` as an ask; the other
lenses keep references. See `examples/multi-blocked.txt`.

### --standup — what moved in the window

Resolve the window cutoff with the helper (deterministic, pure-arithmetic UTC):

```bash
cutoff=$("${CLAUDE_PLUGIN_ROOT}/scripts/since-window.sh" "<token>")
# <token> defaults to last-working-day; also accepts <N>d (1d, 2d, …).
# Prints a UTC epoch; a [CTX] whose `created` epoch is >= cutoff is "in the window".
```

(From the repo root the helper is `plugins/bitacora/scripts/since-window.sh`.) A reporting
ticket **moved** if its latest compliant `[CTX]` has `created >= cutoff`. Render in the
chosen lens (default `self`):

```
Standup — since <token> · <coverage>

Moved:
- <KEY> "<title>" — <Jira status>
    Did: <one line from that [CTX]'s Done / Status change>
    Next: <first Next bullet>
    ⚠ <Risk or Blockers one-liner>                         (only if present)
- …
No movement: <KEY, KEY, …>   (reporting tickets whose latest [CTX] predates the cutoff; omit if none)
```

If nothing moved, print `No [CTX] activity since <token> across <coverage>.` The window is
UTC-day-aligned for `last-working-day` (a deliberate v1 simplification — a Monday run picks
up Friday + weekend); `--since 2d` widens it when a teammate's day boundary differs. See
`examples/multi-standup.txt`.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; do not pretend a local-only fallback.
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` so future summaries have something to
  read.
- **Epic with no children:** say so; show the epic's own workflow status + title (and its own
  `[CTX]` if it has one). Nothing to roll up.
- **Epic whose children have no `[CTX]` yet:** report `N children, none reporting a [CTX] yet`;
  suggest `/bitacora:handoff` on the children. Still show the per-child Status/title list for
  orientation.
- **Child listing fails (both `parent` and `Epic Link` JQL error):** report that children could
  not be fetched; fall back to rendering the epic itself as a single ticket. No retry loop.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry with
  a different key. No retry loop.
- **No ticket resolved:** say so; suggest passing a key.
- **Scope matched zero tickets (multi-ticket):** say which scope and that it matched nothing;
  suggest narrowing or a different scope. No retry loop.
- **All reporting tickets have no `[CTX]` (multi-ticket):** render the coverage line and the
  per-ticket Status/title list for orientation; suggest `/bitacora:handoff` on them. Nothing
  to aggregate or filter.
- **`--board` passed:** not yet supported (Phase B); say so and stop.
- **Bad `--jql` / unknown field:** surface the JQL error verbatim; stop. No retry loop.
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
  epic_type: Epic            # issue type name that triggers aggregation (override for renamed epic types)
  epic_children_cap: 50      # max children read per epic; truncation is surfaced, never silent
  epic_default_mode: exec    # lens for an epic target when no --for-* flag is given
  multi_fanout_cap: 25       # max tickets read per multi-ticket scope; truncation is surfaced, never silent
```
