---
name: session-digest
description: Aggregate Jira [CTX] reads — roll up an epic across its children, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) through a query lens (--blocked, --standup) or the default cross-ticket digest, in any of five audience lenses. Read-only; prints and offers a clipboard copy. Use when the user runs /bitacora:digest or /bit:digest.
---

`bitacora:session-digest` is the aggregate sibling of `bitacora:session-status`: same
strict `[CTX]` READ rules per `bitacora:jira-comment-format` (`strict` `status_extraction`),
but focused on multi-ticket scope — rolling up an epic across its children or reading a set
of tickets through a query lens. It is strictly **read-only** — it never writes to Jira or
mutates Remember, so there is no confirmation gate. Apply the audience lens per the
*Audience lenses* table in `bitacora:jira-comment-format`.

## 1. Parse arguments

**Mirror guard (single ticket → /status).** If the arguments resolve to exactly **one
explicit non-epic `project_key_pattern` key** with no scope selector, this is a single-ticket
read — do not render. Print and stop:

```
That's a single ticket — use /bitacora:status <KEY>.
```

This fires only for an explicit single non-epic **key**. An epic key (rollup) and a scope that
happens to match one ticket (degenerate one-item digest) both proceed normally.

- **Scope (multi-ticket).** A scope selector activates digest's multi-ticket path: `--mine`,
  `--sprint`, `--jql "<JQL>"`, or **two or more** `project_key_pattern` keys in the
  arguments. Multi-ticket mode activates **iff** a scope flag is present or 2+ keys are
  passed — a single epic key keeps the epic-rollup behavior. `--board <id|name>` is
  **not supported** (a board is a saved JQL — use `--jql`): if passed, say exactly that
  and stop (do not silently fall back).
- **Query lens (multi-ticket only).** `--blocked` or `--standup` selects *what to surface*
  across the scope; with neither, the default is the cross-ticket digest (§6). Query lenses
  compose with the `--for-*` audience lens, which still selects altitude. A query lens with
  a single non-epic key triggers the mirror guard above. Two query lenses at once is an error.
- **`--since <token>` (only with `--standup`).** `<token>` ∈ `<N>d` (e.g. `1d`, `2d`) or
  `last-working-day` (the default). If passed without `--standup`, ignore it with a one-line
  note.
- **Mode flag:** one of `--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, `--for-exec`.
  An explicit flag always wins; with no flag, fall back to `digest.default_mode` (built-in
  default `self`). For an **epic** target with no flag, the default is
  `digest.epic_default_mode` (default `exec`) — see §6's *Aggregate render*. An unknown flag
  or more than one mode flag is an error — name the five valid modes and stop; never guess.
  See the *Audience lenses* table in `bitacora:jira-comment-format` for which lens a given
  role should pass.
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
- **`--copy-as-slack`:** optional; re-render the summary in Slack `mrkdwn` and copy to
  clipboard automatically (skipping the prompt in §7). Compatible with all five mode flags.
  See §6's *Slack mrkdwn rendering* sub-section for the rendering rules.

The multi-ticket default audience is `self`. `--blocked`, `--standup`, and the aggregate all
honor an explicit `--for-*`. There is no `--debt` / `--risk` / `--deps` query lens — parked
debt is an aggregate **section** (§5), and the risk / dependency views are the aggregate's
existing Risk-concentration and Dependency-graph signals.

## 2. Resolve the aggregate target

An epic key resolves to the children read (§4); a scope selector resolves to the scope set (§4).

When §1 detected a scope selector or 2+ keys, resolve a *set* of keys. Resolve the Atlassian
site first (§3 — needed to run JQL), then build the list via `searchJiraIssuesUsingJql`,
requesting `summary,issuetype,status`:

| Scope | JQL |
|-------|-----|
| explicit keys (2+) | `key IN (KEY-1, KEY-2, …) ORDER BY updated DESC` |
| `--mine` | `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC` |
| `--sprint` | `assignee = currentUser() AND sprint IN openSprints() ORDER BY updated DESC` |
| `--jql "<q>"` | the user's `<q>` verbatim; append `ORDER BY updated DESC` only if `<q>` has no `ORDER BY` |

**Cap the set** at `digest.multi_fanout_cap` (default 25). If the JQL matched more, take the
first N in `updated DESC` order and **surface the truncation** in the render
(`showing N of M — narrow with --jql`); never silently drop. Edge cases:

- **Zero matches** → say so plainly and stop (e.g. `--mine matched no open tickets`).
- **Exactly one match** → treat it as a single target and proceed from §4 (if it is an epic, §4 still rolls it up); a one-ticket set needs no digest.
- **JQL error** (bad `--jql`, unknown field) → surface the error verbatim and stop; no retry loop.

## 3. Resolve the Atlassian site

Resolve `cloudId` exactly as `bitacora:session-status` §3 (`getAccessibleAtlassianResources`; `jira_cloud_id` override; hard-stop if the MCP is absent / auth fails).

## 4. Read

**Epic path (§4a).** When §1 resolved a single epic key, read the epic's children:

1. **List children via JQL.** Call `searchJiraIssuesUsingJql` with
   `jql: "parent = <EPIC-KEY> ORDER BY created ASC"`, requesting `summary,issuetype,status`.
   If that errors or returns zero, retry once with `jql: "\"Epic Link\" = <EPIC-KEY> ORDER BY created ASC"`
   (classic-project epics use the `Epic Link` field instead of `parent`). If both forms fail,
   see *Error / edge behavior*.
2. **Cap the set.** Read at most `digest.epic_children_cap` children (default 50). If the epic has
   more, read the first N by creation order and **surface the truncation** in the render
   (`showing first N of T children`) — never silently drop.
3. **Strict-read each child.** For each child, `getJiraIssue` **requesting comments** and extract
   its latest compliant `[CTX]` per the strict READ rules in `bitacora:jira-comment-format` (same
   rules §4 uses). Classify each child as:
   - **reporting** — has a compliant `[CTX]` (its latest is authoritative for that child);
   - **no-`[CTX]`** — no compliant `[CTX]` yet;
   - **malformed** — has a `[CTX]` attempt missing `Status:`/`Next:`.
4. **Never silently drop.** Carry the no-`[CTX]` and malformed counts into the render
   (`Not yet reporting: …`, and a malformed tally), exactly like the excluded-count discipline.

Child reads are independent; one child's 404 / permission error is isolated — count it as
unreadable and continue with the rest.

**Scope set path (§4b).** Runs when §2 resolved a set. For each key, `getJiraIssue`
**requesting comments** and extract its latest compliant `[CTX]` per the strict READ rules in
`bitacora:jira-comment-format` — identical classification to the epic path above: **reporting**
(has a compliant `[CTX]`, its latest is authoritative), **no-`[CTX]`**, or **malformed**. For
each reporting ticket also capture its latest-`[CTX]` `created` timestamp from comment metadata
(needed by `--blocked` staleness and `--standup` windowing — note `--standup` additionally
consumes **every** in-window `[CTX]` per ticket, not just the latest; see §6's `--standup`)
and the ticket's `updated` timestamp (needed by the staleness marker in §6). Reads are
independent — one key's 404 / permission error is isolated; count it **unreadable** and
continue. Carry the no-`[CTX]` / malformed / unreadable tallies into every §6 render as the
coverage line, exactly like the epic path's excluded-count discipline.

## 5. Aggregate signals

Compute these from the children's (or resolved scope set's) `[CTX]`s — the computation is
identical whether the source is an epic's children or a resolved scope set. Facts only — the
same **no-invention** rule applies; never synthesize a number or claim a ticket did not report:

- **Per-ticket line** — `CHILD-KEY "<title>" — <status> (confidence)`, one per reporting ticket.
- **Health** — a one-line rollup: if any ticket is `Blockers:`-blocked → *blocked*; else if any
  ticket has `confidence: low` or an open `Risk:` → *at risk*; else *on track*. State the reason briefly.
- **Confidence distribution** — tally the `(confidence: …)` cues across reporting tickets
  (`high ×A · medium ×B · low ×C`). Omit tickets that carry no cue from the tally.
- **Risk concentration** — the tickets carrying `Risk:` or `Blockers:`, listed risk-bearing first,
  one line each. When the same surface or dependency recurs across 2+ tickets, flag it as
  **concentrated** — name the recurring surface once and list the tickets sharing it
  (`Concentrated: <surface> recurs across KEY-A + KEY-B`, extending with `+ KEY-C` for each
  additional ticket; append the line after the per-ticket risk lines). Recurrence is evidence-based:
  only flag a surface the bullets actually share; never infer a theme. Empty if none.
- **Dependency graph** — parse each ticket's `Dependencies:`; when a dependency names another ticket
  in the same set, render it as an edge `KEY-A → KEY-B (what blocks what)`. Cross-set deps are
  listed as plain bullets. Empty if none.
- **Parked debt** — every `[debt]`-tagged `Decisions:` bullet across the reporting tickets,
  grouped by ticket in `By ticket:` / `By child:` order — one ledger line each:
  `KEY · the deferred decision · follow-up KEY` — omit the follow-up segment when the
  bullet names none. Empty if none. No new data is read — this is a pivot on the `[debt]` tags the strict read already
  captures. Same **no-invention** rule: only `[debt]` tags that actually exist; never
  synthesize a debt item.
- **Cost rollup** — sum the numeric infra + inference `$` values across tickets that report them;
  label it **approximate** and note how many tickets contributed. Omit if no ticket reports cost.
- **Coverage** — `N tickets (M reporting, K no [CTX], J malformed, U unreadable)`, dropping any zero terms — plus any truncation note from
  §4. Always shown so the reader knows the rollup's basis.

## 6. Render

The **query lens** (§1) selects the pivot (`--blocked` / `--standup` / the default digest);
the `--for-*` **audience lens** still selects altitude. Facts only — the same no-invention rule
as the single-ticket renders. Every render carries a **coverage** line —
`N tickets (M reporting, K no [CTX], J malformed, U unreadable)`, dropping any zero terms —
plus any `showing N of M — narrow with --jql` truncation note from §2.

### Aggregate render

Render the aggregate signals **in the chosen lens**. **Epic default lens:** when the target is an
epic and no `--for-*` flag was given, use `digest.epic_default_mode` (default `exec`) instead of the
default `self` — a portfolio's natural audience is leadership. An explicit flag always wins.
Lenses degrade gracefully: omit any signal that is empty (no risks → no `Top risks:` block).

**Ticket-key links:** `By child:` / `By ticket:` entry keys print **bare**; they become Slack
links only under `--copy-as-slack`, per *Ticket-key links (Slack only)* below.

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
Debt:                                        (omit if none)
- <CHILD-KEY: parked tradeoff carried forward, business framing (+ follow-up KEY if named)>
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
Parked debt:                                 (omit if none)
- <CHILD-KEY · deferred decision · follow-up KEY (omit if not named)>
Excluded: <K no [CTX] (J malformed)>         (omit if zero)
```

**--for-ops / --for-pm / --for-self** reuse the same aggregate structure, shaped by that lens's
single-ticket emphasis:
- **ops** — `By child` leads each reporting child with its `Deploy/Ops:` posture (env/flag/rollback)
  and a combined `Watch:` list across children; keeps links. Children with no `Deploy/Ops:` show
  Status + Next only.
- **pm** — plain-language portfolio: `Health` and `Confidence` first, `By child` as one plain
  sentence each, `Risks / needs` framed as asks; strip PR/commit hashes, keep the ticket link.
- **self** — terse: `Health` line + the `By child` list, then a terse `Parked debt:` tail
  (one ledger line per `[debt]` item, same `KEY · decision · follow-up KEY` shape — your
  own parked debt; omit when empty), plus the
  `Not yet reporting:` / coverage tail — never drop no-`[CTX]` tickets.

**Parked debt is an oversight signal** — it renders only in `--for-exec` (`Debt:`, business
framing), `--for-eng` (`Parked debt:`, technical, with the follow-up key), and `--for-self`
(terse `Parked debt:` tail). `--for-pm` / `--for-ops` omit it (not their altitude). An empty ledger omits
the section entirely, like `Top risks:`. The recurrence-flagged risk lines render wherever
the lens's existing risk section already renders (`Top risks:` in exec, `Open risks /
blockers:` in eng) — the flag is a phrasing addition, not a new slot.

All five keep the coverage figure in the header line (`Epic · <coverage>`) so the reader knows how complete the rollup is.

See `examples/epic-exec.txt`, `examples/epic-eng.txt` — an epic (CHECKOUT-100) rolled up across its children.

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

### --standup — what moved, by day

Resolve the window cutoff with the helper (deterministic, pure-arithmetic UTC):

```bash
cutoff=$("${CLAUDE_PLUGIN_ROOT}/scripts/since-window.sh" "<token>")
# <token> defaults to last-working-day; also accepts <N>d (1d, 2d, …).
# Prints a UTC epoch; a [CTX] whose `created` epoch is >= cutoff is "in the window".
```

(From the repo root the helper is `plugins/bitacora/scripts/since-window.sh`.)

**Read model — all in-window `[CTX]` (standup only).** Unlike every other lens, `--standup`
does **not** stop at the latest `[CTX]`. For each reporting ticket, take **every** compliant
`[CTX]` whose `created >= cutoff` (the comments are already in hand from §4 — just stop
discarding the earlier in-window ones; this is **no** extra API calls). A ticket with no
in-window `[CTX]` has **not moved**. This per-`[CTX]` read is scoped to `--standup`;
`--blocked`, the digest, and all epic paths keep latest-`[CTX]`-authoritative.

**Bucket each in-window `[CTX]` by its UTC day.** Get today's day index once, and each
`[CTX]`'s day index + weekday name, from the helper:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/standup-buckets.sh" "<epoch>"   # prints "<day_index> <Weekday>"
```

- **Today** — `[CTX]` whose day index equals today's.
- **Past** — `[CTX]` whose day index is *less than* today's (still ≥ cutoff).

Render the **past bucket first, then Today** (chronological). **Omit an empty bucket.** Within
a bucket, order entries by `[CTX]` `created` descending. A ticket with in-window `[CTX]` on
**both** the past day and today appears in **both** buckets, each line carrying that day's own
`Did` / `Next` (within a bucket, the ticket's latest `[CTX]` in that bucket drives the line).

**Past-bucket header** — derived from the distinct day indices present in the past bucket
(call that set D; let `T` = today's day index):

- `|D| == 1` and that day is `T − 1` → **`Yesterday`**
- `|D| == 1` and that day is `< T − 1` (the past day is not the immediate prior calendar
  day — e.g. a weekend or non-working gap) → that **weekday name** (e.g. `Friday`)
- `|D| > 1` (only possible with a wide `--since Nd`) → **`Earlier`**

`Today` is always literally `Today`. Render in the chosen lens (default `self`):

```
Standup — since <token> · <coverage>

<Yesterday | Friday | Earlier>:
- <KEY> "<title>" — <Jira status>
    Did: <Done / Status change from that day's [CTX]>
    Next: <first Next bullet>
    ⚠ <Risk or Blockers one-liner>            (only if present)
- …

Today:
- <KEY> "<title>" — <Jira status>
    Did: …
    Next: …
- …

No movement: <KEY, KEY, …>   (reporting tickets with no in-window [CTX]; omit if none)
```

If nothing moved, print `No [CTX] activity since <token> across <coverage>.` The window is
UTC-day-aligned (a deliberate v1 simplification — a Monday `last-working-day` run picks up
Friday + weekend, all under the `Friday` header); `--since 2d` widens it. The per-ticket
**staleness marker** (below) is printed **once per ticket**, on its entry in the **latest**
bucket it appears in (Today if present, else the past bucket). See
`examples/multi-standup.txt`.

### Slack mrkdwn rendering (when `--copy-as-slack` is set)

Render the **same content** as the chosen mode, but with Slack `mrkdwn` conventions instead
of Markdown:

- `*bold*` instead of `**bold**` (single asterisks for emphasis)
- `<https://example.com|label>` instead of `[label](https://example.com)` (Slack
  angle-bracket link form with `|` as the label separator)
- Plain bulleted lines (`• item` with U+2022) instead of Markdown lists (`- item`) —
  Slack renders Markdown lists inconsistently
- **No Markdown tables.** If a mode would have used a table (none currently do, but
  defensive), fall back to one bullet per row
- Surface the scope / epic key + URL prominently as the leading line, e.g.:
  `*EPIC-1* — <https://site/browse/EPIC-1|Checkout revamp>` (for a scope: `*Scope: --mine*`).

**Ticket-key links (Slack only).** Printed renders show **bare** keys. Only under
`--copy-as-slack` does each per-ticket **index entry** — the `By ticket:` / `By child:` lists
(rendered via *Aggregate render*), the `--blocked` entries, and the `--standup` bucket
entries (under the day headers) — render its **leading key** as a Slack link
`<https://<site>/browse/KEY|KEY>`, where `<site>` is the Atlassian site resolved in §3.
Even in Slack, inline mentions (`Health:`, `Top risks:`, `Dependencies:` edges, the
`Debt:` / `Parked debt:` ledger lines) and the `Not yet reporting:` / `No movement:` tails
stay bare. This is the **only** place keys are
linked — printed renders leave them bare. Inline / tail keys stay bare even here.

All read semantics (strict `[CTX]` extraction, error handling) are unchanged from the default
render path. See `examples/multi-aggregate-slack.txt`.

### Staleness marker

For each **reporting** ticket, run the drift check using its latest-`[CTX]` `created` and its
`updated` (both captured in §4), with the shared `staleness_grace` (default `2d`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/staleness-check.sh" \
  --ctx-epoch "<latest-ctx-created-epoch>" \
  --updated-epoch "<ticket-updated-epoch>" \
  --grace "<staleness_grace>"
```

When it returns `stale Nd`, suffix that ticket's per-index entry — `By ticket:` / `By child:`,
`--blocked` entries, the `--standup` bucket entry in the ticket's latest bucket — with
` · ⚠ behind <N>d`, after the Jira status (and, in Slack, after the key-link). Fresh /
no-`[CTX]` tickets get no marker. The marker is orthogonal to the query lens: it never
changes `--blocked` / `--standup` selection, only annotates the entries a lens already shows.

## 7. Print, then offer a clipboard copy

Print the render, then offer/copy to clipboard exactly as `bitacora:session-status` §6
(best-effort `pbcopy`/`wl-copy`/`xclip`/`clip`; `--copy-as-slack` always copies).

## Error / edge behavior

- **Single non-epic key:** the mirror guard (§1) redirects to `/bitacora:status`.
- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; do not pretend a local-only fallback.
- **Epic with no children:** say so; show the epic's own workflow status + title (and its own
  `[CTX]` if it has one). Nothing to roll up.
- **Epic whose children have no `[CTX]` yet:** report `N children, none reporting a [CTX] yet`;
  suggest `/bitacora:handoff` on the children. Still show the per-child Status/title list for
  orientation.
- **Child listing fails (both `parent` and `Epic Link` JQL error):** report that children could
  not be fetched; fall back to rendering the epic itself as a single ticket. No retry loop.
- **Scope matched zero tickets:** say which scope and that it matched nothing; suggest
  narrowing or a different scope. No retry loop.
- **All reporting tickets have no `[CTX]`:** render the coverage line and the per-ticket
  Status/title list for orientation; suggest `/bitacora:handoff` on them. Nothing to aggregate
  or filter.
- **`--board` passed:** not supported (a board is a saved JQL — use `--jql`); say so and stop.
- **Bad `--jql` / unknown field:** surface the JQL error verbatim; stop. No retry loop.
- **Invalid / conflicting mode flag:** error listing the valid modes; do not guess.

## Configuration

`/bitacora:digest` reads `digest.*` keys, each **falling back to the legacy `status.*` key**
of the same name (then the built-in default) so existing configs keep working. The
`bitacora:jira-comment-format` Configuration block is the source of truth for the full
override resolution chain (`${CLAUDE_PROJECT_DIR}/.bitacora.yml` → `~/.claude/bitacora.yml` →
built-in defaults).

The five digest keys:

```yaml
digest:
  epic_type: Epic            # issue type that triggers epic rollup (was status.epic_type)
  epic_children_cap: 50      # max children read per epic (was status.epic_children_cap)
  epic_default_mode: exec    # lens for an epic target with no --for-* (was status.epic_default_mode)
  multi_fanout_cap: 25       # max tickets read per scope (was status.multi_fanout_cap)
  default_mode: self         # lens for a scope read with no --for-* (was the multi default)
```

Resolution per key: `digest.<key>` → legacy `status.<key>` → built-in default.
