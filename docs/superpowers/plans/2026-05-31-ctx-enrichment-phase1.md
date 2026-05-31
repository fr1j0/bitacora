# CTX Enrichment — Phase 1 (Capture Vocabulary) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, agent-populated enrichment vocabulary to the `[CTX]` comment so a diverse org extracts role-relevant signal — without changing the required core or the write-time interface.

**Architecture:** The required core (`[CTX] Status update` + `Status:` + `Next:`) is untouched. Five optional sections, two single-line fields, a confidence cue, and inline decision tags are documented in the `jira-comment-format` skill and auto-populated by the `session-handoff` skill from session evidence. The presence-based `validate-ctx.sh` needs no rule change; golden fixtures lock that enriched bodies stay `compliant` and that hygiene rules still fire inside the new sections.

**Tech Stack:** Markdown skill files (prompt-driven plugin), Bash (`validate-ctx.sh` + its fixture-oracle test harness `test-validate-ctx.sh`). No application code.

**Scope:** Phase 1 only. Phase 2 (render lenses) and Phase 3 (`status` epic aggregation) from `docs/superpowers/specs/2026-05-31-ctx-enrichment-design.md` get their own plans after this lands.

---

### Task 1: Lock enriched + backward-compat + hygiene fixtures (the oracle)

These fixtures are the regression oracle: they pin that the presence-based validator (a) accepts an enriched body, (b) still accepts a bare-core body, and (c) still flags a bare URL inside a *new* section. Add each assertion first (red: file missing → validator exit 3 → harness FAIL), then create the fixture (green).

**Files:**
- Modify: `plugins/bitacora/scripts/test-validate-ctx.sh` (add three `check` lines after line 29, the `archive.txt` check)
- Create: `plugins/bitacora/skills/jira-comment-format/examples/compliant-enriched.txt`
- Create: `plugins/bitacora/skills/jira-comment-format/examples/compliant-core-only.txt`
- Create: `plugins/bitacora/skills/jira-comment-format/examples/malformed-artifacts-bare-url.txt`

- [ ] **Step 1: Add the three failing assertions**

In `plugins/bitacora/scripts/test-validate-ctx.sh`, immediately after the line:

```bash
check "$FIXTURES/archive.txt"                         not-in-format 2
```

add:

```bash
check "$FIXTURES/compliant-enriched.txt"              compliant     0
check "$FIXTURES/compliant-core-only.txt"             compliant     0
check "$FIXTURES/malformed-artifacts-bare-url.txt"    malformed     1
```

- [ ] **Step 2: Run the harness to verify the new checks fail**

Run: `bash plugins/bitacora/scripts/test-validate-ctx.sh`
Expected: the three new lines report `FAIL: ... → got '' (3)` (files don't exist yet); all pre-existing checks still `PASS`. Overall exit non-zero.

- [ ] **Step 3: Create `compliant-enriched.txt`**

```
[CTX] Status update

Status: In Progress (confidence: high)

Impact: model-serving, infra

Done:

- Retrained churn model and deployed to staging

Decisions:

- Promote behind a feature flag, not a hard cutover [blast-radius]

Model/Eval:

- churn v2: AUC 0.82 → 0.87; precision@0.5 0.71 → 0.79
- inference $ ≈ +0.4¢/call vs v1
- model rollback = pin registry alias `churn:prod` back to v1

Deploy/Ops:

- On staging behind flag `churn_v2`; rollback = flip the flag off
- Watch: p95 inference latency, null-feature rate

Artifacts:

- run [mlflow#441](https://mlflow.acme.internal/runs/441)
- PR [#812](https://github.com/acme/ml/pull/812)

Dependencies:

- Needs DATA-77 feature backfill before prod

Next:

- 48h staging soak, then promote `churn_v2` to prod
```

- [ ] **Step 4: Create `compliant-core-only.txt`** (backward-compat: required core only, no optional sections)

```
[CTX] Status update

Status: In Progress

Next:

- Finish the token refresh wiring
```

- [ ] **Step 5: Create `malformed-artifacts-bare-url.txt`** (hygiene must still fire inside a new section)

```
[CTX] Status update

Status: In Progress

Artifacts:

- run https://mlflow.acme.internal/runs/441

Next:

- Promote to prod
```

- [ ] **Step 6: Run the harness to verify all checks pass**

Run: `bash plugins/bitacora/scripts/test-validate-ctx.sh`
Expected: every line `PASS`, including the three new ones (`compliant-enriched.txt → compliant (0)`, `compliant-core-only.txt → compliant (0)`, `malformed-artifacts-bare-url.txt → malformed (1)`). Overall exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/bitacora/scripts/test-validate-ctx.sh plugins/bitacora/skills/jira-comment-format/examples/compliant-enriched.txt plugins/bitacora/skills/jira-comment-format/examples/compliant-core-only.txt plugins/bitacora/skills/jira-comment-format/examples/malformed-artifacts-bare-url.txt
git commit -m "test(ctx): golden fixtures for enriched, core-only, and bare-url-in-Artifacts"
```

---

### Task 2: Document the optional enrichment vocabulary in the format skill

**Files:**
- Modify: `plugins/bitacora/skills/jira-comment-format/SKILL.md` (insert a new section after line 40, the `See examples/compliant.txt` line, before `## Write rules (hard)`)

- [ ] **Step 1: Insert the `Optional enrichment sections` section**

After the line `See \`examples/compliant.txt\` for a full compliant example.` and its trailing blank line, insert:

```markdown
## Optional enrichment sections

Beyond `Done`/`Decisions`/`Blockers`/`Open questions`, these optional sections carry
role-specific signal. Each appears **only when the session actually produced it** and
obeys the same blank-line *Write mechanics* below. The handoff agent populates them from
session evidence (see `bitacora:session-handoff`) — never hand-fill, never invent. None
of them affect compliance: `Header + Status: + Next:` remain the only required elements.

- `Artifacts:` — typed links, one per bullet: PR · design (Figma) · run (mlflow/wandb) ·
  dashboard · runbook · doc. URLs wrapped per the URL rule below.
- `Deploy/Ops:` — deployment/operational state: environment, feature flag, rollback plan,
  watch-list (what to monitor), and an infra cost (`$`) line when relevant.
- `Model/Eval:` — ML/AI state: model or prompt version, eval-suite delta, a safety/guardrail
  note, inference or training cost (`$`), and model rollback (distinct from app rollback).
- `Dependencies:` — cross-team / cross-surface / cross-ticket items this work is blocked on
  or that depend on it. Distinct from `Blockers:` (a hard stop you own right now).
- `Risk:` — a latent risk that could bite later. Distinct from `Blockers:` (blocking now).

Two single-line fields:

- `Impact: <surfaces>` — a comma-separated list of surfaces touched, from the convention
  vocabulary `api · schema · ui · data-pipeline · model-serving · infra · config · docs`,
  so a reader self-selects relevance. Convention only — the validator does not enforce the
  vocabulary.
- The cost `$` line is **folded into** `Deploy/Ops:` / `Model/Eval:`, never its own section.

The `Status:` line may carry an optional confidence cue —
`Status: In Progress (confidence: high)`, with `confidence ∈ {high, medium, low}`. Omit it
when not assessed.

`Decisions:` bullets may carry trailing inline tags so senior readers scan the org-shaping
choices without reading every local one: `[precedent]` (sets a pattern others should
follow), `[debt]` (incurs tech debt, ideally ticketed), `[blast-radius]` (touches
widely-shared code). Convention only; the validator does not enforce them.

See `examples/compliant-enriched.txt` for a body exercising several of these.
```

- [ ] **Step 2: Verify the enriched example still validates (no prose/fixture drift)**

Run: `plugins/bitacora/scripts/validate-ctx.sh plugins/bitacora/skills/jira-comment-format/examples/compliant-enriched.txt`
Expected: prints `compliant`, exit 0. (Confirms the documented format and the golden fixture agree.)

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/SKILL.md
git commit -m "docs(ctx): document optional enrichment sections, fields, tags, confidence cue"
```

---

### Task 3: Add work-type auto-population to the handoff skill

**Files:**
- Modify: `plugins/bitacora/skills/session-handoff/SKILL.md` (insert into `## 2. Draft a [CTX] per ticket`, after the first paragraph that ends `...no play-by-play, no code diffs (link the PR), no speculation.` — i.e. after line 46, before the `**Optional continuity-read (lenient):**` paragraph)

- [ ] **Step 1: Insert the work-type enrichment block**

After the paragraph ending `...not a re-summary of the session.` and before the `**Optional continuity-read (lenient):**` paragraph, insert:

```markdown
**Work-type enrichment (auto-populate the optional sections).** While drafting, detect what
the session actually did and populate the matching optional sections from the
`bitacora:jira-comment-format` skill — **from real evidence only, never invented.** Cues:

| Detected signal | Populate |
|---|---|
| `*.tf`, `Dockerfile`, k8s / `helm/` manifests, or CI config touched | `Deploy/Ops:` + `Impact: infra` |
| `migrations/` or schema files touched | `Impact: schema` + a contract note in `Decisions:` |
| `*.ipynb`, mlflow/wandb references, model files, or eval scripts | `Model/Eval:` + `Impact: model-serving` |
| component/route files touched or Figma links present | `Artifacts:` design link + `Impact: ui` |
| API spec / route files touched | `Impact: api` + a contract delta in `Decisions:` |
| other ticket keys mentioned this session | `Dependencies:` |

When the evidence is weak or ambiguous, **omit the section rather than guess** — the confirm
gate (step 4) shows the conservative draft and the user can add detail. Add the `Status:`
confidence cue and the `[precedent]` / `[debt]` / `[blast-radius]` decision tags when warranted.
```

- [ ] **Step 2: Verify the insertion reads correctly in context**

Run: `sed -n '39,60p' plugins/bitacora/skills/session-handoff/SKILL.md`
Expected: the new `**Work-type enrichment...**` block appears between the per-ticket drafting paragraph and the `**Optional continuity-read (lenient):**` paragraph, with a blank line on each side and the table intact.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-handoff/SKILL.md
git commit -m "feat(handoff): auto-populate enrichment sections from work-type evidence"
```

---

### Task 4: Sync the human-facing format doc

The doc defers to the skill (`Source of truth` banner at the top) but should mention the additions so readers of the doc aren't surprised.

**Files:**
- Modify: `docs/JIRA_AGENT_COMMENT_FORMAT.md` (insert a subsection after `## The format` section — after line 50, the `Team/PM-facing open questions...` bullet — before `## How agents read it`)

- [ ] **Step 1: Insert the enrichment subsection**

After the bullet ending `next-session-only questions stay in local scratch.` and before `## How agents read it`, insert:

```markdown
### Optional enrichment sections

Beyond `Done`/`Decisions`/`Blockers`/`Open questions`, a `[CTX]` may carry optional
role-specific sections — `Artifacts:` (typed links), `Deploy/Ops:` (env, flag, rollback,
watch-list), `Model/Eval:` (model/prompt version, eval delta, safety, cost, model
rollback), `Dependencies:` (cross-team/ticket), and `Risk:` (latent risk, distinct from a
current `Blockers:`) — plus an `Impact:` surface line, an optional `Status:` confidence cue,
and inline `Decisions:` tags (`[precedent]`/`[debt]`/`[blast-radius]`). These are populated
automatically by `/bitacora:handoff` from what the session did; they are **optional and never
affect compliance**. The literal catalog and rules live in the skill (source of truth above).
```

- [ ] **Step 2: Verify the doc still reads coherently**

Run: `sed -n '50,62p' docs/JIRA_AGENT_COMMENT_FORMAT.md`
Expected: the new `### Optional enrichment sections` subsection sits between the format bullets and `## How agents read it`.

- [ ] **Step 3: Commit**

```bash
git add docs/JIRA_AGENT_COMMENT_FORMAT.md
git commit -m "docs(ctx): mention optional enrichment sections in the human-facing format doc"
```

---

## Final verification

- [ ] **Run the full validator test harness**

Run: `bash plugins/bitacora/scripts/test-validate-ctx.sh`
Expected: every check `PASS`, overall exit 0.

- [ ] **Confirm backward compatibility of the original golden fixtures**

Run: `for f in compliant compliant-with-preamble malformed non-ctx; do echo "$f:"; plugins/bitacora/scripts/validate-ctx.sh plugins/bitacora/skills/jira-comment-format/examples/$f.txt; done`
Expected: `compliant → compliant`, `compliant-with-preamble → compliant`, `malformed → malformed`, `non-ctx → not-in-format`. (Proves the additions did not regress existing classifications.)

## Manual acceptance (post-merge, exercised in a live session)

These cannot be scripted (they exercise the model's drafting), but verify them before declaring Phase 1 done — they map to A1–A3 and A9 in the spec:

- **A1:** `/bitacora:handoff` after a session that touched `*.tf` → draft auto-includes `Deploy/Ops:` (env, rollback, watch) + `Impact: infra`.
- **A2:** handoff after a notebook + eval-run session → draft auto-includes `Model/Eval:` (version, eval delta, inference `$`) + `Impact: model-serving`.
- **A3:** handoff after a plain refactor with no special signal → no new sections emitted; draft matches today's minimal CTX in spirit.
- **A9:** weak evidence for a section → section omitted, not hallucinated; gate shows the conservative draft.

## Out of scope (this plan)

- Render lenses `--for-ops` / `--for-exec` and per-lens routing → Phase 2 plan.
- `status` epic auto-aggregation → Phase 3 plan.
- Any change to `validate-ctx.sh` rules (none needed — D6).
