# CTX Enrichment — Phase 2 (Render Lenses) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two audience lenses (`--for-ops`, `--for-exec`) to `/bitacora:status` and route the Phase 1 enrichment sections per lens, so 14 roles map onto 5 lenses — adding only two flags to the interface.

**Architecture:** `bitacora:session-status` already renders `--for-self/--for-eng/--for-pm` from a ticket's latest `[CTX]`. Phase 2 adds `ops` and `exec` to the fixed lens enum, documents a role→lens table, and teaches every lens template which Phase 1 sections (`Artifacts:`, `Deploy/Ops:`, `Model/Eval:`, `Dependencies:`, `Risk:`, `Impact:`, the confidence cue, decision tags) to surface or strip. Read-only; no Jira writes; lenses degrade gracefully when a section is absent.

**Tech Stack:** Markdown skill + command + alias files (prompt-driven plugin). Golden example renders under `skills/session-status/examples/`. No application code, no validator (renders are model-produced; verification is grep for the wiring + a faithfulness check that no render invents facts absent from the source `[CTX]`).

**Depends on:** Phase 1 (PR #73) — the enrichment vocabulary in `jira-comment-format`. This branch is stacked on `docs/ctx-enrichment-design`; rebase onto `main` once #73 merges.

**Scope:** Phase 2 only. Phase 3 (`status` epic auto-aggregation) gets its own plan.

---

## Shared reference — the enriched source `[CTX]` for examples

Tasks 5 uses ONE enriched source `[CTX]` rendered across all five lenses (replacing the older AUTH-204 trio so the example set is coherent and shows routing differences). The canonical source for the example renders is:

```
CHURN-42 "Churn model v2 rollout"  — Jira status: In Progress

[CTX] Status update

Status: In Progress (confidence: medium)

Impact: model-serving, infra

Done:
- Retrained churn model on the Q2 cohort and deployed v2 to staging
- Added an offline eval gate to CI on the held-out set

Decisions:
- Promote behind a feature flag, not a hard cutover [blast-radius]
- Standardized on the registry-alias rollback pattern for model services [precedent]

Model/Eval:
- churn v2: AUC 0.82 → 0.87; no regression on the fairness slice suite
- inference $ ≈ +0.4¢/call vs v1
- model rollback = pin registry alias churn:prod back to v1

Deploy/Ops:
- On staging behind flag churn_v2; rollback = flip the flag off
- Watch: p95 inference latency, null-feature rate
- infra $: +1 GPU node on the serving pool during the soak

Artifacts:
- training run mlflow#441 (https://mlflow.example.internal/runs/441)
- PR #812 (https://github.com/example/ml/pull/812)

Dependencies:
- Needs DATA-77 feature backfill before prod promote

Risk:
- Drift PSI could exceed threshold under the May traffic mix; mitigated by the soak + watch-list

Next:
- 48h staging soak, then promote churn_v2 to prod once DATA-77 lands
```

Site for ticket links in examples: `acme.atlassian.net`. Every render below contains ONLY facts present in this source — no invention. This is the faithfulness invariant the reviews check.

---

### Task 1: Recognize `ops` and `exec` as valid modes (parse + config + frontmatter)

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` (frontmatter line 3; `## 1. Parse arguments` mode-flag bullet ~line 16; `## Configuration` `default_mode` comment ~line 161)

- [ ] **Step 1: Update the mode-flag bullet in §1**

Find:

```
- **Mode flag:** `--for-pm`, `--for-eng`, or `--for-self`. An explicit flag always wins;
  with no flag, fall back to `status.default_mode` (built-in default `self`). An unknown
  flag or more than one mode flag is an error — name the valid modes and stop; never guess.
```

Replace with:

```
- **Mode flag:** one of `--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, `--for-exec`.
  An explicit flag always wins; with no flag, fall back to `status.default_mode` (built-in
  default `self`). An unknown flag or more than one mode flag is an error — name the five
  valid modes and stop; never guess. See the role→lens table in §5 for which lens a given
  role should pass.
```

- [ ] **Step 2: Update the frontmatter description (line 3)**

Find (the `description:` value):

```
Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary — --for-self (terse recall), --for-eng (technical handoff), or --for-pm (plain-language stakeholder status). Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
```

Replace with:

```
Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary across five lenses — --for-self (terse recall), --for-eng (technical handoff), --for-ops (deploy/operational), --for-pm (plain-language stakeholder status), --for-exec (business/risk/cost). Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
```

- [ ] **Step 3: Update the `default_mode` config comment**

Find:

```
  default_mode: self     # self | eng | pm — overrides the built-in default mode
```

Replace with:

```
  default_mode: self     # self | eng | ops | pm | exec — overrides the built-in default mode
```

- [ ] **Step 4: Verify**

Run: `grep -nE "for-ops|for-exec|self \| eng \| ops" plugins/bitacora/skills/session-status/SKILL.md`
Expected: matches in the §1 bullet, the frontmatter, and the config comment.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): recognize --for-ops and --for-exec as valid lenses"
```

---

### Task 2: Add the role → lens mapping table

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` (insert at the top of `## 5. Render for the selected mode`, immediately after its intro paragraph and before the `### --for-self` heading)

- [ ] **Step 1: Insert the mapping table**

Immediately before the `### --for-self (default)` heading, insert:

```markdown
**Role → lens.** Five lenses cover the org; pass the flag for the reader's role:

| Lens | Flag | Roles it serves | Leads with / strips |
|------|------|-----------------|---------------------|
| self | `--for-self` | you | terse recall — latest Status + Next |
| eng  | `--for-eng`  | frontend, backend, full-stack, staff, AI staff, tech lead | contract, `Artifacts:`, `Model/Eval:`, `Decisions:`+tags; keeps PR/commit links |
| ops  | `--for-ops`  | devops, infra, MLOps | `Deploy/Ops:`, rollback, watch-list, `Impact:`; keeps links |
| pm   | `--for-pm`   | product, technical managers | plain language; confidence; `Risk:`/`Dependencies:` as asks; strips PR/commit hashes, keeps ticket link |
| exec | `--for-exec` | CTO, CRAIO | business/risk/cost + confidence; strips implementation detail, keeps ticket link |

A lens **degrades gracefully**: if the `[CTX]` lacks a section the lens would lead with, omit it silently (a UI ticket under `--for-ops` simply has no `Deploy/Ops:` to show).
```

- [ ] **Step 2: Verify**

Run: `grep -n "Role → lens" plugins/bitacora/skills/session-status/SKILL.md`
Expected: one match, located between the §5 intro and `### --for-self`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "docs(status): add role→lens mapping table"
```

---

### Task 3: Add the two new render templates + route enrichment sections in all five

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` (the `### --for-self`, `### --for-eng`, `### --for-pm` template blocks in §5; add `### --for-ops` and `### --for-exec`)

- [ ] **Step 1: Extend the `--for-self` template** to surface present enrichment compactly.

Find the `--for-self` code block:

```
PROJ-1234 "<title>" — <Jira status>
Left off:   <latest Status>
Next:       <Next bullets>
Decisions:  <decision bullets>        (only if present)
Blockers:   <bullets>                 (only if present)
```

Replace with:

```
PROJ-1234 "<title>" — <Jira status>
Left off:   <latest Status, incl. (confidence: …) if present>
Next:       <Next bullets>
Decisions:  <decision bullets, keep [precedent]/[debt]/[blast-radius] tags>  (only if present)
Risk:       <Risk bullets>            (only if present)
Blockers:   <bullets>                 (only if present)
```

- [ ] **Step 2: Extend the `--for-eng` template** to surface contract / Artifacts / Model-Eval / Dependencies.

Find the `--for-eng` code block:

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

Replace with:

```
PROJ-1234 "<title>" — <Jira status>
https://<site>/browse/PROJ-1234

Impact:     <Impact surfaces>          (only if present)
Done recently:
- <Done across the lookback window>
Decisions:
- <decision + rationale, keep [precedent]/[debt]/[blast-radius] tags>
Model/Eval:                            (only if present)
- <version, eval delta, inference $, model rollback>
Artifacts:                             (only if present)
- <PR / design / run / dashboard / runbook links>
Dependencies:                          (only if present)
- <cross-team / cross-ticket items>
Next:
- <Next bullets>
Risk / blockers / open questions:
- <Risk + Blockers + open questions, only if present>
```

- [ ] **Step 3: Extend the `--for-pm` template** to carry the confidence cue and Dependencies.

Find the `--for-pm` code block:

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:        <on track / blocked / in progress — plain words>
Progress:      <outcome-oriented Done across the lookback, jargon stripped>
What's next:   <Next in plain language>
Risks / needs: <Blockers + Open questions, framed as asks>   (only if present)
```

Replace with:

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:        <on track / at risk / blocked — plain words> (confidence: <cue, if present>)
Progress:      <outcome-oriented Done across the lookback, jargon stripped>
What's next:   <Next in plain language>
Risks / needs: <Risk + Blockers + Dependencies + Open questions, framed as asks>   (only if present)
```

- [ ] **Step 4: Add the `--for-ops` template** immediately after the `--for-eng` block and BEFORE the `### --for-pm` block (keeping the technical→business order self / eng / ops / pm / exec).

Insert:

```markdown
### --for-ops — deploy / operational (devops, infra, MLOps; keep links, lead with operational posture)

```
PROJ-1234 "<title>" — <Jira status>
https://<site>/browse/PROJ-1234

Impact:      <Impact surfaces>
Deploy/Ops:
- <environment, feature flag, rollback plan, infra $>
Watch:
- <the watch-list — what to monitor>
Model rollback: <from Model/Eval, only if present>
Next:
- <deploy / promote / cutover steps>
Risk / blockers:
- <Risk + Blockers, only if present>
```

If the ticket has no `Deploy/Ops:` or `Model/Eval:`, ops degrades to the latest Status + Next (nothing operational to lead with).
```

- [ ] **Step 5: Add the `--for-exec` template** immediately after the `--for-pm` block (and before the `### Slack mrkdwn rendering` heading).

Insert:

```markdown
### --for-exec — business / risk / cost (CTO, CRAIO; strip implementation detail, keep the ticket link, lead with state and money)

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:          <on track / at risk / blocked — plain words> (confidence: <cue, if present>)
Business impact: <what this delivers, in plain language — no implementation detail>
Cost:            <infra + inference $ from Deploy/Ops / Model/Eval, only if present>
Risks / needs:   <Risk + Blockers + Dependencies, framed as decisions or asks>
Next milestone:  <Next in plain language, outcome not mechanism>
```

Strip PR/commit hashes, file paths, flag names, and tool jargon. Keep the ticket link. Invent nothing — if there is no cost line in the `[CTX]`, omit `Cost:`.
```

- [ ] **Step 6: Verify**

Run: `grep -nE "^### --for-(self|eng|ops|pm|exec)" plugins/bitacora/skills/session-status/SKILL.md`
Expected: all five headings present, in the order self, eng, ops, pm, exec (ops inserted between eng and pm; exec after pm).

- [ ] **Step 7: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): add ops/exec render templates; route enrichment sections per lens"
```

---

### Task 4: Extend Slack mrkdwn rendering to five lenses

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` (the `### Slack mrkdwn rendering` paragraph, ~line 104)

- [ ] **Step 1: Update the lens enumeration**

Find:

```
Render the **same content** as the chosen mode (`--for-self` / `--for-eng` / `--for-pm`),
but with Slack `mrkdwn` conventions instead of Markdown:
```

Replace with:

```
Render the **same content** as the chosen mode (`--for-self` / `--for-eng` / `--for-ops` /
`--for-pm` / `--for-exec`), but with Slack `mrkdwn` conventions instead of Markdown:
```

- [ ] **Step 2: Update the compatibility line in §1's `--copy-as-slack` bullet**

Find (in `## 1. Parse arguments`):

```
  clipboard automatically (skipping the prompt in step 6). Compatible with all three
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
```

Replace with:

```
  clipboard automatically (skipping the prompt in step 6). Compatible with all five
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
```

- [ ] **Step 3: Verify**

Run: `grep -n "all five mode flags" plugins/bitacora/skills/session-status/SKILL.md`
Expected: one match (in §1's `--copy-as-slack` bullet).

Run: `grep -n "for-ops.*for-pm.*for-exec\|for-self.*for-eng.*for-ops" plugins/bitacora/skills/session-status/SKILL.md`
Expected: a match on the Slack-rendering paragraph that now enumerates all five lenses.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): extend Slack mrkdwn rendering to ops/exec lenses"
```

---

### Task 5: Golden example renders — one enriched [CTX] across all five lenses

Replace the AUTH-204 example trio with a coherent five-render set built from the shared source `[CTX]` (top of this plan), so the examples demonstrate routing differences from one input.

**Files:**
- Modify: `plugins/bitacora/skills/session-status/examples/self.txt`
- Modify: `plugins/bitacora/skills/session-status/examples/eng.txt`
- Modify: `plugins/bitacora/skills/session-status/examples/pm.txt`
- Create: `plugins/bitacora/skills/session-status/examples/ops.txt`
- Create: `plugins/bitacora/skills/session-status/examples/exec.txt`
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` (the `See examples/...` pointer line ~line 120)

- [ ] **Step 1: Overwrite `self.txt`**

```
CHURN-42 "Churn model v2 rollout" — In Progress
Left off:   On staging behind flag churn_v2; soak in progress (confidence: medium)
Next:
- 48h staging soak, then promote churn_v2 to prod once DATA-77 lands
Decisions:
- Promote behind a feature flag, not a hard cutover [blast-radius]
- Registry-alias rollback pattern for model services [precedent]
Risk:
- Drift PSI could exceed threshold under May traffic; mitigated by soak + watch-list
```

- [ ] **Step 2: Overwrite `eng.txt`**

```
CHURN-42 "Churn model v2 rollout" — In Progress
https://acme.atlassian.net/browse/CHURN-42

Impact:     model-serving, infra
Done recently:
- Retrained churn model on Q2 cohort, deployed v2 to staging
- Added an offline eval gate to CI on the held-out set
Decisions:
- Promote behind a feature flag, not a hard cutover [blast-radius]
- Registry-alias rollback pattern for model services [precedent]
Model/Eval:
- churn v2: AUC 0.82 → 0.87; no regression on the fairness slice suite
- inference $ ≈ +0.4¢/call vs v1; rollback = pin alias churn:prod to v1
Artifacts:
- run mlflow#441 (https://mlflow.example.internal/runs/441)
- PR #812 (https://github.com/example/ml/pull/812)
Dependencies:
- Needs DATA-77 feature backfill before prod promote
Next:
- 48h staging soak, then promote to prod once DATA-77 lands
Risk / blockers / open questions:
- Drift PSI could exceed threshold under May traffic; mitigated by soak + watch-list
```

- [ ] **Step 3: Overwrite `pm.txt`**

```
CHURN-42 "Churn model v2 rollout"
https://acme.atlassian.net/browse/CHURN-42

Status:        On track, in progress — new model is on staging, finishing validation. (confidence: medium)
Progress:      Retrained the churn model; it predicts better and passed the fairness checks.
What's next:   Watch it on staging for two days, then turn it on in production.
Risks / needs: Needs a data backfill (DATA-77) before go-live. Watching for prediction drift under May traffic.
```

- [ ] **Step 4: Create `ops.txt`**

```
CHURN-42 "Churn model v2 rollout" — In Progress
https://acme.atlassian.net/browse/CHURN-42

Impact:      model-serving, infra
Deploy/Ops:
- On staging behind flag churn_v2; rollback = flip the flag off
- infra $: +1 GPU node on the serving pool during the soak
Watch:
- p95 inference latency, null-feature rate
Model rollback: pin registry alias churn:prod back to v1
Next:
- 48h staging soak, then promote churn_v2 to prod once DATA-77 lands
Risk / blockers:
- Drift PSI could exceed threshold under May traffic; mitigated by soak + watch-list
```

- [ ] **Step 5: Create `exec.txt`**

```
CHURN-42 "Churn model v2 rollout"
https://acme.atlassian.net/browse/CHURN-42

Status:          On track, at low risk — improved model in final validation. (confidence: medium)
Business impact: Better churn prediction; fairness checks pass, so no compliance exposure.
Cost:            ~+0.4¢ per prediction, plus one extra GPU node during the trial period.
Risks / needs:   Go-live waits on a data dependency (DATA-77); monitoring prediction drift as a precaution.
Next milestone:  Two-day production-readiness trial, then switch on for all users.
```

- [ ] **Step 6: Update the `See examples/...` pointer line in SKILL.md**

Find:

```
See `examples/self.txt`, `examples/eng.txt`, `examples/pm.txt` — the same `[CTX]` rendered
in all three modes.
```

Replace with:

```
See `examples/self.txt`, `examples/eng.txt`, `examples/ops.txt`, `examples/pm.txt`,
`examples/exec.txt` — the same enriched `[CTX]` (CHURN-42) rendered in all five lenses.
```

- [ ] **Step 7: Faithfulness check (no invention)**

Read all five example files and the shared source `[CTX]` at the top of this plan. Confirm every fact in every render traces to a line in the source — no numbers, links, flags, or claims that are not in the source. Confirm `exec.txt` and `pm.txt` contain no PR/commit hashes, file paths, or flag names (stripped), while `eng.txt`/`ops.txt` keep the links.

Run: `ls plugins/bitacora/skills/session-status/examples/` → expect `self.txt eng.txt ops.txt pm.txt exec.txt`.

- [ ] **Step 8: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/skills/session-status/examples/
git commit -m "docs(status): five-lens golden renders from one enriched [CTX]"
```

---

### Task 6: Advertise the two new flags on the command surfaces

**Files:**
- Modify: `plugins/bitacora/commands/status.md`
- Modify: `plugins/bitacora/alias/bit-status.md`
- Modify: `plugins/bitacora/commands/help.md`
- Modify: `plugins/bitacora/alias/bit-help.md`

- [ ] **Step 1: Update `commands/status.md`** — both the frontmatter `description` and the body's flag sentence.

In the frontmatter, find `(--for-pm/--for-eng/--for-self)` and replace with `(--for-self/--for-eng/--for-ops/--for-pm/--for-exec)`.

In the body, find:

```
`--for-pm`, `--for-eng`, or `--for-self` flag selects the audience mode
(default: self). Add `--copy-as-slack` to re-render the summary as Slack
```

Replace with:

```
`--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, or `--for-exec` flag selects the
audience lens (default: self). Add `--copy-as-slack` to re-render the summary as Slack
```

- [ ] **Step 2: Update `alias/bit-status.md`** — apply the EXACT same two replacements as Step 1 (the alias body is identical to the command body).

In the frontmatter, find `Audience-tailored summary of a ticket's latest [CTX].` — leave it (it does not enumerate flags).

In the body, find:

```
`--for-pm`, `--for-eng`, or `--for-self` flag selects the audience mode
(default: self). Add `--copy-as-slack` to re-render the summary as Slack
```

Replace with:

```
`--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, or `--for-exec` flag selects the
audience lens (default: self). Add `--copy-as-slack` to re-render the summary as Slack
```

- [ ] **Step 3: Update the help reference block in `commands/help.md`.**

Find the two status lines inside the fenced block:

```
  /bitacora:status [KEY]        Summarize a ticket's latest [CTX] for an
                                audience (--for-pm/--for-eng/--for-self).
```

Replace with:

```
  /bitacora:status [KEY]        Summarize a ticket's latest [CTX] for an
                                audience — 5 lenses (self/eng/ops/pm/exec).
```

- [ ] **Step 4: Apply the IDENTICAL change to `alias/bit-help.md`** (its fenced block must stay byte-for-byte in sync with `commands/help.md` — that sync is called out in the HTML comment at the top of both files). Make the exact same two-line replacement as Step 3.

- [ ] **Step 5: Verify the two help blocks are still identical**

Run: `diff <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md)`
Expected: no output (the fenced reference blocks match exactly).

Run: `grep -n "self/eng/ops/pm/exec" plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md`
Expected: one match in each file.

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md
git commit -m "docs(status): advertise --for-ops/--for-exec on command, alias, and help surfaces"
```

---

## Final verification

- [ ] **Wiring grep** — every place that enumerates the lenses now includes ops and exec:

Run:
```bash
grep -rn "for-ops\|for-exec" plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md
grep -rn "self/eng/ops/pm/exec" plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md
```
Expected: matches in the skill (parse, templates, Slack), both status command files, and both help files.

- [ ] **Five render templates present:**

Run: `grep -nE "^### --for-(self|eng|ops|pm|exec)" plugins/bitacora/skills/session-status/SKILL.md`
Expected: exactly five headings.

- [ ] **Help blocks in sync** (re-run the Task 6 Step 5 `diff` — no output).

- [ ] **Examples present:** `ls plugins/bitacora/skills/session-status/examples/` → `self.txt eng.txt ops.txt pm.txt exec.txt`.

## Manual acceptance (post-merge, live session — maps to spec A4–A6)

Uses the Phase 1 test tickets (TESTING-16…20, each one authoritative `[CTX]`):

- **A4:** `/bitacora:status TESTING-16 --for-ops` → `Deploy/Ops:` leads (env, rollback, watch-list); implementation prose de-emphasized.
- **A5:** `/bitacora:status TESTING-18 --for-exec` → business/risk/cost/confidence lead; PR/commit hashes and flag names stripped; ticket link kept.
- **A6:** `/bitacora:status TESTING-19 --for-eng` (a UI ticket with no `Model/Eval:`) → renders cleanly; the absent section is simply omitted (graceful degradation).
- **Cross-check:** `/bitacora:status TESTING-20 --for-exec` → the `Dependencies:` edge to TESTING-19 surfaces as an ask, not a raw key dump.

## Out of scope (this plan)

- `status` epic auto-aggregation → Phase 3 plan.
- Flag-free audience inference (status still takes an explicit lens flag).
- Any change to the Phase 1 capture vocabulary or the validator.
- A `--for-<role>` alias set that resolves to a lens (possible later nicety; the role→lens table covers discovery for now).
