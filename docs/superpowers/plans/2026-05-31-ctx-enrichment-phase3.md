# CTX Enrichment — Phase 3 (Status Epic Aggregation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach `/bitacora:status` to roll up an **epic** transparently — when the target is an epic, fan out across its children, strict-read each child's latest `[CTX]`, and render an aggregate in the chosen lens — with **no new command**.

**Architecture:** A single branch added to the existing `session-status` skill: after resolving + fetching the target, detect the Jira issue type. Story/Bug/Subtask → today's single-ticket path (unchanged). Epic → query children, strict-read each, compute aggregate signals (risk concentration, dependency graph, confidence distribution, cost rollup), and render per lens. Read-only; reuses the Phase 1 strict-`[CTX]` rules and the Phase 2 lenses. Default lens for an epic is `exec` (a portfolio's natural audience), overridable by an explicit flag.

**Tech Stack:** Markdown skill + command/alias files. Atlassian MCP (`getJiraIssue`, `searchJiraIssuesUsingJql`). Golden example renders. No application code, no validator (renders are model-produced; verification is grep for the wiring + a faithfulness check that aggregates invent nothing).

**Depends on:** Phases 1 (#73) + 2 (#74). This branch is stacked on `docs/ctx-enrichment-phase2`; rebase down the stack as #73 then #74 merge to `main`.

**Scope:** Epic aggregation only. Subtask/story-with-subtask rollup, cross-epic rollup, and `--jql`/`--sprint` selectors are explicitly out of scope (see end).

---

## Shared reference — the synthetic epic for examples (Task 6)

One epic, three reporting children, each with a latest `[CTX]`. Used only to author the golden aggregate renders. Site for links: `acme.atlassian.net`.

```
EPIC  CHECKOUT-100 "Checkout revamp"  (issue type Epic)
child CHECKOUT-101 "Serving cluster migration"
        Status: In Progress (confidence: high)
        Deploy/Ops: prod canary running; infra $: +2 nodes during cutover
        Next: prod canary 24h, then shift 100% traffic
child CHECKOUT-102 "Ranking model v3"
        Status: In Progress (confidence: medium)
        Model/Eval: NDCG +0.05; inference $ ≈ +0.4¢/call; rollback = pin alias to v2
        Risk: drift PSI could exceed threshold under peak traffic (mitigated by soak)
        Next: shadow eval, then promote behind a flag
child CHECKOUT-103 "Checkout summary panel"
        Status: In Progress (confidence: low)
        Risk: layout overflow on narrow viewports, unresolved before release
        Dependencies: blocked on CHECKOUT-102 (checkout UI consumes the new ranking model)
        Next: truncation pass + design QA
```

Every aggregate render below contains ONLY facts present in these three child `[CTX]`s — no invention. That is the faithfulness invariant the reviews check.

---

### Task 1: Detect an epic target and branch the read path

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` — insert a new subsection `### 4a. Single ticket or epic?` at the END of `## 4. Read the ticket (strict [CTX])` (after its last bullet, before `## 5`).

- [ ] **Step 1: Insert the branch-decision subsection**

After the last bullet of §4 (`...With --include-all, print the excluded comments too.`) and before `## 5. Render for the selected mode`, insert:

```markdown
### 4a. Single ticket or epic?

The `getJiraIssue` response in §4 carries `fields.issuetype`. Branch on it:

- **Epic** (issue type name equals the configured `status.epic_type`, default `Epic`) → run the
  **aggregate path** (§4b + §5's *Aggregate render*). The epic's own `[CTX]` is not required.
- **Anything else** (Story / Bug / Subtask / …) → the single-ticket path of §4 + §5 stands as
  today; skip §4b entirely.

Only the epic issue type triggers aggregation. A Story with subtasks is **not** rolled up in
this version (it renders as a single ticket). This keeps the trigger unambiguous and matches the
"point `status` at an epic → portfolio view" rule.
```

- [ ] **Step 2: Verify**

Run: `grep -n "4a. Single ticket or epic" plugins/bitacora/skills/session-status/SKILL.md`
Expected: one match, located between §4's last bullet and `## 5`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): detect epic target and branch to the aggregate read path"
```

---

### Task 2: Fan out and strict-read the epic's children

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` — insert `### 4b. Read the epic's children (aggregate path)` immediately after the §4a block from Task 1.

- [ ] **Step 1: Insert the fan-out subsection**

Immediately after the §4a block, insert:

```markdown
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
```

- [ ] **Step 2: Verify**

Run: `grep -n "4b. Read the epic" plugins/bitacora/skills/session-status/SKILL.md`
Expected: one match, immediately after §4a.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): fan out and strict-read an epic's children with capped, isolated reads"
```

---

### Task 3: Define the aggregate signals

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` — insert `### Aggregate signals (epic)` near the END of `## 5. Render for the selected mode`, immediately BEFORE the `See examples/...` pointer line (so that pointer stays the section's closing line).

- [ ] **Step 1: Insert the aggregate-signals subsection**

Find the Slack subsection's last line (`All read semantics ... unchanged from the default render path.`) followed by a blank line and the `See examples/...` pointer line. Insert the block below in that blank gap — **after** the Slack subsection and **before** the `See examples/...` pointer line:

```markdown
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
```

- [ ] **Step 2: Verify**

Run: `grep -n "Aggregate signals (epic)" plugins/bitacora/skills/session-status/SKILL.md`
Expected: one match, at the end of §5 before §6.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "docs(status): define epic aggregate signals (health, risk concentration, dep graph, cost rollup)"
```

---

### Task 4: Per-lens aggregate render templates + epic default lens

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` — insert `### Aggregate render` (with exec + eng skeletons and the ops/pm/self rule) immediately after the `### Aggregate signals (epic)` block from Task 3; and update §1's mode-flag bullet to state the epic default.

- [ ] **Step 1: Insert the aggregate render templates**

Immediately after the `### Aggregate signals (epic)` block, insert:

```markdown
### Aggregate render

Render the aggregate signals **in the chosen lens**. **Epic default lens:** when the target is an
epic and no `--for-*` flag was given, use `status.epic_default_mode` (default `exec`) instead of the
single-ticket default `self` — a portfolio's natural audience is leadership. An explicit flag always
wins. Lenses degrade gracefully: omit any signal that is empty (no risks → no `Top risks:` block).

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
- **self** — terse: `Health` line + the `By child` list only.

All five keep the `Coverage` line so the reader knows how complete the rollup is.
```

- [ ] **Step 2: Note the epic default in §1's mode-flag bullet**

In `## 1. Parse arguments`, find the mode-flag bullet ending `...See the role→lens table in §5 for which lens a given role should pass.` and append one sentence to that bullet:

```
  For an **epic** target with no flag, the default is `status.epic_default_mode` (default `exec`),
  not `self` — see §5's *Aggregate render*.
```

- [ ] **Step 3: Verify**

Run: `grep -nE "^### Aggregate render|epic_default_mode" plugins/bitacora/skills/session-status/SKILL.md`
Expected: the `### Aggregate render` heading and at least two `epic_default_mode` references (the §1 note and the render block); the exec + eng skeletons present with balanced ``` fences.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): per-lens epic aggregate render templates; exec as the epic default lens"
```

---

### Task 5: Config, error/edge, and the command-surface note

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` — add config keys; add epic error/edge rows.
- Modify: `plugins/bitacora/commands/status.md` and `plugins/bitacora/alias/bit-status.md` — one-line epic note.

- [ ] **Step 1: Add the two config keys**

In `## Configuration`, find the `status:` YAML block and add two keys under it (after `default_mode`):

```yaml
  epic_type: Epic            # issue type name that triggers aggregation (override for renamed epic types)
  epic_children_cap: 50      # max children read per epic; truncation is surfaced, never silent
  epic_default_mode: exec    # lens for an epic target when no --for-* flag is given
```

- [ ] **Step 2: Add epic error/edge rows**

In `## Error / edge behavior`, after the `**No `[CTX]` on the ticket:**` bullet, add:

```markdown
- **Epic with no children:** say so; show the epic's own workflow status + title (and its own
  `[CTX]` if it has one). Nothing to roll up.
- **Epic whose children have no `[CTX]` yet:** report `N children, none reporting a [CTX] yet`;
  suggest `/bitacora:handoff` on the children. Still show the per-child Status/title list for
  orientation.
- **Child listing fails (both `parent` and `Epic Link` JQL error):** report that children could
  not be fetched; fall back to rendering the epic itself as a single ticket. No retry loop.
```

- [ ] **Step 3: Add the command-surface note** to BOTH `plugins/bitacora/commands/status.md` and `plugins/bitacora/alias/bit-status.md`. In each file's body, after the sentence that ends `...selects the audience lens (default: self).`, append:

```
Point it at an **epic** and it rolls up the epic's children into a portfolio summary in the
chosen lens (no flag → `exec`); point it at a story/bug for the single-ticket summary.
```

- [ ] **Step 4: Verify**

Run: `grep -n "epic_children_cap\|epic_default_mode\|epic_type" plugins/bitacora/skills/session-status/SKILL.md`
Expected: the three config keys present.
Run: `grep -rn "rolls up the epic" plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md`
Expected: one match in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md
git commit -m "feat(status): epic config keys, epic error/edge handling, command-surface note"
```

---

### Task 6: Golden aggregate example renders

**Files:**
- Create: `plugins/bitacora/skills/session-status/examples/epic-exec.txt`
- Create: `plugins/bitacora/skills/session-status/examples/epic-eng.txt`
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` — extend the `See examples/...` pointer line to mention the epic examples.

- [ ] **Step 1: Create `epic-exec.txt`** (rendered from the synthetic epic at the top of this plan)

```
CHECKOUT-100 "Checkout revamp" — Epic · 3 children (3 reporting, 0 no [CTX])
https://acme.atlassian.net/browse/CHECKOUT-100

Health:       At risk — a low-confidence child with an open UI risk and an unresolved cross-child dependency.
Confidence:   high ×1 · medium ×1 · low ×1   (across 3 reporting children)
Top risks:
- CHECKOUT-103: checkout layout overflows on narrow viewports, unresolved before release
- CHECKOUT-102: model drift could exceed threshold under peak traffic (mitigated by the soak)
Dependencies:
- CHECKOUT-103 → CHECKOUT-102: the checkout UI waits on the new ranking model
Cost:         ~+0.4¢ per prediction, plus extra serving nodes (approximate, from 2 children)
By child:
- CHECKOUT-101 "Serving cluster migration" — on track (high)
- CHECKOUT-102 "Ranking model v3" — in progress (medium)
- CHECKOUT-103 "Checkout summary panel" — at risk (low)
```

- [ ] **Step 2: Create `epic-eng.txt`**

```
CHECKOUT-100 "Checkout revamp" — Epic · 3 children (3 reporting, 0 no [CTX])
https://acme.atlassian.net/browse/CHECKOUT-100

Dependency graph:
- CHECKOUT-103 → CHECKOUT-102 (checkout UI consumes the new ranking model)
By child:
- CHECKOUT-101 "Serving cluster migration" — In Progress; next: prod canary 24h, then 100% traffic; risk: —
- CHECKOUT-102 "Ranking model v3" — In Progress; next: shadow eval, then promote behind a flag; risk: drift PSI under peak
- CHECKOUT-103 "Checkout summary panel" — In Progress; next: truncation pass + design QA; risk: overflow on narrow viewports
Open risks / blockers:
- CHECKOUT-102: drift PSI could exceed threshold under peak traffic (mitigated by the soak)
- CHECKOUT-103: layout overflow on narrow viewports before release
Excluded: 0 children with no compliant [CTX]
```

- [ ] **Step 3: Extend the `See examples/...` pointer line**

Find:

```
See `examples/self.txt`, `examples/eng.txt`, `examples/ops.txt`, `examples/pm.txt`,
`examples/exec.txt` — the same enriched `[CTX]` (CHURN-42) rendered in all five lenses.
```

Replace with:

```
See `examples/self.txt`, `examples/eng.txt`, `examples/ops.txt`, `examples/pm.txt`,
`examples/exec.txt` — the same enriched `[CTX]` (CHURN-42) rendered in all five lenses; and
`examples/epic-exec.txt`, `examples/epic-eng.txt` — an epic (CHECKOUT-100) rolled up across its
children.
```

- [ ] **Step 4: Faithfulness check (no invention)**

Read both epic examples against the synthetic epic at the top of this plan. Confirm every fact in
each render traces to a child `[CTX]`: the three child statuses/confidences, the two risks
(CHECKOUT-102 drift, CHECKOUT-103 overflow), the dependency edge (103→102), and the cost (only
CHECKOUT-101 infra nodes + CHECKOUT-102 inference $ report cost — "from 2 children" is correct).
Confirm `epic-exec.txt` contains no PR/commit hashes or flag names (exec strips them), while the
content present is all derivable from the children.

Run: `ls plugins/bitacora/skills/session-status/examples/` → expect the five lens files plus `epic-exec.txt epic-eng.txt`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/skills/session-status/examples/
git commit -m "docs(status): golden epic aggregate renders (exec + eng) from a 3-child epic"
```

---

## Final verification

- [ ] **Wiring grep** — the aggregate path is wired end to end:

```bash
grep -nE "4a. Single ticket or epic|4b. Read the epic|Aggregate signals \(epic\)|^### Aggregate render" plugins/bitacora/skills/session-status/SKILL.md
grep -nE "epic_type|epic_children_cap|epic_default_mode" plugins/bitacora/skills/session-status/SKILL.md
grep -rn "rolls up the epic" plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md
```
Expected: §4a, §4b, the aggregate-signals heading, and the `### Aggregate render` heading all present; the three config keys; the command-surface note in both command files.

- [ ] **Fence balance** — `grep -cE '^```' plugins/bitacora/skills/session-status/SKILL.md` returns an **even** number (the exec + eng aggregate skeletons each add a balanced pair; the five single-ticket templates and the yaml block are unchanged).

- [ ] **Single-ticket path untouched** — confirm the five `### --for-*` single-ticket templates and §1–§4's single-ticket text are unchanged by this phase (the aggregate path is purely additive): `git diff docs/ctx-enrichment-phase2 -- plugins/bitacora/skills/session-status/SKILL.md` shows only insertions in §4a/§4b/§5-aggregate/§Config and the one §1 sentence + pointer-line edit — no deletions inside the single-ticket templates.

- [ ] **Examples present** — `ls .../examples/` shows `epic-exec.txt` and `epic-eng.txt` alongside the five lens files.

## Manual acceptance (post-merge, live session — maps to spec A7–A8)

Prerequisite (one-time test-data setup, not a code change): create a TESTING epic and link the
existing per-profile tickets (TESTING-16…20) under it, so there is a real multi-child epic with
diverse risk/confidence/cost/dependency signal.

- **A7:** `/bitacora:status <TESTING-epic> --for-exec` → aggregate: Health, confidence distribution,
  risk concentration (TESTING-17/19 risks first), dependency edge (TESTING-20 → TESTING-19), cost
  rollup; coverage line shows 5 children all reporting.
- **A8:** `/bitacora:status TESTING-16` (a story) → single-ticket summary, unchanged — no accidental
  aggregation.
- **Default-lens check:** `/bitacora:status <TESTING-epic>` with no flag → renders in `exec`, not
  `self`.
- **Graceful coverage:** temporarily point at an epic with a child that has no `[CTX]` → that child
  appears under `Not yet reporting:`, never silently dropped.

## Out of scope (this plan)

- Subtask rollup / story-with-subtasks (only the Epic issue type triggers aggregation).
- Cross-epic or `--jql` / `--sprint` / `--assignee` portfolio selectors (a single epic key is the
  only aggregation trigger).
- A separate `/bitacora:rollup` command (folded into `status` per the spec's D5).
- Caching or pagination beyond the first `epic_children_cap` children (truncation is surfaced, not
  paged).
- Any change to the Phase 1 capture vocabulary, the Phase 2 single-ticket lenses, or the validator.
