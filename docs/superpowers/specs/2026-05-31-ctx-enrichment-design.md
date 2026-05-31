# Design — `[CTX]` Enrichment for a Multi-Role Org

**Date:** 2026-05-31
**Status:** Approved design, ready for implementation planning
**Scope:** Enrich the `[CTX]` comment so a diverse org (frontend, backend, full-stack,
data science, MLOps, AI staff, staff engineers, tech leads, devops, infra, product,
technical managers, CTO, CRAIO) extracts role-relevant signal from the same shared
corpus — without adding interface surface or write-time friction.

## Summary

Today a `[CTX]` is captured as one flat outcome stream (`Done / Decisions / Next /
Blockers / Open questions`) and tailored only on the **read** side by
`/bitacora:status` (`--for-self / --for-eng / --for-pm`). The read side can only
reshape what capture recorded — it cannot surface an ETA, a rollback plan, an eval
delta, or a cost number the handoff never wrote down. **The lever for richer content
is the capture vocabulary, not more render modes.**

This design adds richness as an **optional, typed, agent-populated layer** on top of
the untouched required core, routes it per audience through a fixed lens enum, and lets
`/bitacora:status` aggregate an epic transparently. The guiding principle:

> The required core stays sacred; richness lives in an optional, typed,
> agent-populated layer; render lenses route it per audience; `status` aggregates it
> for leadership — all behind the existing interface.

**Net interface delta across the whole design: two new lens flags (`--for-ops`,
`--for-exec`) on one existing command.** Everything else — the enriched capture
vocabulary, the agent-inferred population, and epic auto-aggregation — runs backstage
and is invisible to the user, who simply approves a richer draft at the handoff gate
that already exists.

There is **no new command and no new alias.** An earlier draft proposed a standalone
`/bitacora:rollup`; it was dropped in favor of folding aggregation into `status`,
because the only thing a portfolio view changes is the *scope of the target*, which
`status` can infer transparently (see Layer 3).

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Required core unchanged** (`[CTX] Status update` + `Status:` + `Next:`) | Preserves the D2 adoption thesis from the original CTX design ("lowest friction maximizes adoption"). Every existing comment stays valid; old and enriched comments coexist. |
| D2 | **Richness is optional + agent-populated, not a human-filled template** | A fill-in template reintroduces exactly the friction D1 protects. The authoring agent already knows what it did (files touched, tools run, PRs, commands) and populates the new sections from that evidence; the human only approves at the existing gate. |
| D3 | **Tight named set + inline tags**, not a section per signal | ~5 named optional sections plus inline decision tags and a folded cost line keeps the comment scannable. The long tail rides inline tags rather than proliferating headings. |
| D4 | **Fixed 5-lens enum** (`self / eng / pm / exec / ops`), not per-role modes | 14 roles map onto 5 lenses. A finite, maintainable render surface; per-role modes would mean 14 overlapping specs. |
| D5 | **No standalone rollup command — fold aggregation into `status`** | Keeps the interface minimal and does the hard work backstage. A portfolio view only changes the target's scope; `status` infers epic-vs-story from the Jira issue type and fans out internally. |
| D6 | **Validator needs no rule change** | It is presence-based (Header + `Status:` + `Next:` + hygiene). Enriched bodies classify as `compliant` unchanged. Only new golden fixtures are added. |
| D7 | **Phased build: capture → lenses → aggregation** | Render and aggregation both depend on the capture layer carrying the richer signal. Each phase ships independently and is useful on its own. |

## Layer 1 — Capture vocabulary (Phase 1, the foundation)

Touches `skills/jira-comment-format/SKILL.md` (the format spec) and
`skills/session-handoff/SKILL.md` (the population mechanism).

### Required core — unchanged

`[CTX] Status update` header + `Status:` + `Next:`. A minimal CTX with none of the
additions below is still fully compliant.

### Status confidence cue (optional)

`Status:` may carry an optional parenthetical health signal:

```
Status: In Progress (confidence: high)
```

`confidence` ∈ `{high, medium, low}`. Optional; omitted when not assessed. Primary
readers: `pm` / `exec` lenses scanning for delivery health.

### Five new optional sections

Appear only when non-empty; populated by the agent from session evidence (never
invented). Each follows the existing *Write mechanics* (blank line before/after every
label and bullet list).

| Section | Carries | Primary readers |
|---|---|---|
| `Artifacts:` | typed links — PR · design (Figma) · run (mlflow/wandb) · dashboard · runbook · doc | everyone |
| `Deploy/Ops:` | env · feature flag · rollback plan · watch-list · infra cost (`$`) | devops, infra |
| `Model/Eval:` | model/prompt version · eval-suite delta · safety/guardrail note · inference cost (`$`) · model rollback | MLOps, AI staff |
| `Dependencies:` | cross-team / cross-surface / cross-ticket blocked-on (distinct from `Blockers:`) | tech leads, PM, CTO |
| `Risk:` | latent risk — could bite later (distinct from `Blockers:` = hard stop now) | staff, CTO, PM |

### Two lightweight single-line fields

- `Impact: api, model-serving` — a controlled-vocab list of surfaces touched, so a
  reader self-selects relevance without reading the whole comment. Vocabulary (initial):
  `api · schema · ui · data-pipeline · model-serving · infra · config · docs`.
- **Cost is folded**, not its own section: an infra `$` line inside `Deploy/Ops:` and
  an inference/training `$` line inside `Model/Eval:`. Keeps the catalog tight (D3).

### Inline decision tags

`Decisions:` bullets may carry trailing tags so senior readers scan the org-shaping
ones without reading every local choice:

```
Decisions:
- Adopt PKCE over implicit flow for all SPAs [precedent]
- Shipped with N+1 query on the dashboard list, ticketed AT-512 [debt]
- Migrated the shared auth middleware [blast-radius]
```

Tags (initial): `[precedent]` · `[debt]` · `[blast-radius]`.

### The mechanism — agent-inferred population (in `session-handoff` §2)

Handoff's per-ticket draft step gains a **work-type → section** detection map. The
agent inspects what it actually did this session and populates the matching optional
sections. Illustrative cues:

| Detected signal | Populates |
|---|---|
| `*.tf` · `Dockerfile` · k8s manifests · `helm/` · CI config | `Deploy/Ops:` + `Impact: infra` |
| `migrations/` · schema files | `Impact: schema` + contract note in `Decisions:` |
| `*.ipynb` · mlflow/wandb refs · model files · eval scripts | `Model/Eval:` + `Impact: model-serving` |
| component/route files · Figma links | `Artifacts:` design link + `Impact: ui` |
| API spec / route files | `Impact: api` + contract delta |
| cross-ticket keys mentioned | `Dependencies:` |

**Guardrail:** populate **only from real session evidence** — the same "no invention"
rule the status skill already enforces. When uncertain, omit the section; the existing
handoff confirm gate catches any over-reach before anything is written.

## Layer 2 — Render lenses (Phase 2, in `session-status`)

A fixed 5-lens enum. The 14 roles map onto 5 lenses:

| Lens | Flag | Roles | Leads with / strips |
|---|---|---|---|
| `self` | `--for-self` (default) | you | terse recall (unchanged) |
| `eng` | `--for-eng` | FE, BE, full-stack, staff, AI staff, tech lead | contract · `Artifacts:` · `Model/Eval:` · `Decisions:`+tags |
| `ops` | `--for-ops` *(new)* | devops, infra, MLOps | `Deploy/Ops:` · rollback · watch-list · `Impact:` |
| `pm` | `--for-pm` | product, technical managers | plain language; `Risk:`/`Dependencies:` as asks; confidence |
| `exec` | `--for-exec` *(new)* | CTO, CRAIO | business/revenue/cost/risk + confidence; strips implementation detail |

Routing rules per lens decide which new sections lead, which are stripped. Lenses
**degrade gracefully** when a section is absent (a story with no `Model/Eval:` renders
fine under `eng`). The skill documents a **role → lens** table so users know which flag
to pass. `self` and `eng` continue to keep PR/commit links; `pm` and `exec` strip
internal references but keep the ticket link, exactly as today.

`status.default_mode` config gains `ops` and `exec` as valid values.

## Layer 3 — `status` learns to aggregate (Phase 3, no new surface)

`/bitacora:status` infers scope from the resolved target instead of exposing a new
command:

- Target resolves to a **story / bug / subtask** → single-ticket summary (today's
  behavior, unchanged).
- Target resolves to an **epic** → `status` detects the Jira issue type, fans out
  across the epic's children behind the scenes, strict-reads each child's latest
  `[CTX]`, and renders an **aggregate** in the same lens the user passed.

Aggregate signals (rendered per lens, like single-ticket sections):

- **Risk concentration** — children carrying `Risk:` / `Blockers:`, surfaced first.
- **Dependency graph** — `Dependencies:` edges across the epic (who is blocked on whom).
- **Confidence distribution** — spread of the `Status: (confidence: …)` cues.
- **Cost rollup** — sum of `Deploy/Ops:` / `Model/Eval:` `$` lines, for AI/infra work.

The aggregation logic is **internal machinery the `session-status` skill calls** — not
exposed surface. No new command, no `/bit:` alias, no new mental model: the user learns
one verb (`status`), and "is this one ticket or fifty, fetch them all, strict-read
each, aggregate" happens backstage.

**Access note (intended behavior, not a surprise):** aggregating an epic reads across
**teammates'** `[CTX]` trails — the first Bitácora read whose normal use spans other
people's tickets. This is ordinary Jira read permission, no new access model; the spec
records it as the point of a portfolio view.

## Backward compatibility

- **Storage = Jira comment body.** There is no separate datastore; a `[CTX]` is a Jira
  comment written via `addCommentToJiraIssue`. All additions are to that body and are
  purely additive. Pre-existing comments remain valid.
- **Validator unchanged** (D6) — enriched bodies still classify `compliant`.
- **Readers tolerate absent sections** — `status`, `resume`, and the new aggregation
  path treat every new section as optional; a minimal CTX reads exactly as before.
- **Remember scratch is untouched** — the per-ticket-Jira vs one-session-scratch split
  is unchanged.

## Phasing

| Phase | Deliverable | Depends on |
|---|---|---|
| 1 | Capture vocabulary (format sections, fields, tags) + agent-inferred population in handoff + enriched golden fixtures | — |
| 2 | Render lenses (`ops`, `exec`) + routing + role→lens table | Phase 1 corpus |
| 3 | `status` epic auto-aggregation | Phases 1–2 |

Each phase ships independently and is useful on its own. Phase 1 enriches what gets
written; Phase 2 routes it; Phase 3 scales it to portfolios.

## Files touched

```
plugins/bitacora/skills/jira-comment-format/SKILL.md        # +optional sections, fields, tags, confidence cue (P1)
plugins/bitacora/skills/jira-comment-format/examples/*.txt  # +enriched golden fixtures (P1)
plugins/bitacora/skills/session-handoff/SKILL.md            # +work-type → section detection map (P1)
plugins/bitacora/skills/session-status/SKILL.md             # +ops/exec lenses, routing, role→lens table (P2); +epic aggregation (P3)
docs/JIRA_AGENT_COMMENT_FORMAT.md                           # human-facing spec defers to the skill; sync the additions (P1)
plugins/bitacora/scripts/validate-ctx.sh                    # no rule change; add enriched fixtures to its fixture run (P1)
```

## Testing & acceptance

Prompt/skill plugins are validated by fixtures + manual acceptance scenarios (the
existing house strategy), not classical unit tests.

### Format-conformance fixtures (Phase 1)

- An **enriched compliant** CTX (several new sections + tags + confidence) → classified
  `compliant` by `validate-ctx.sh` (proves additions don't break presence-based
  validation).
- A **minimal** CTX (core only) → still `compliant` (proves backward compatibility).
- An enriched CTX with a **bare URL in an `Artifacts:` link** → `malformed` (proves the
  hygiene rule still fires inside new sections).

### Manual acceptance scenarios

| # | Scenario | Pass condition |
|---|----------|----------------|
| A1 | Handoff after an infra session (`*.tf` touched) | Draft auto-includes `Deploy/Ops:` (env, rollback, watch) + `Impact: infra`; human approves unchanged |
| A2 | Handoff after a model-training session (notebook + eval run) | Draft auto-includes `Model/Eval:` (version, eval delta, inference `$`) + `Impact: model-serving` |
| A3 | Handoff after a plain refactor with no special signal | No new sections emitted; output identical in spirit to today's minimal CTX |
| A4 | `status --for-ops` on an enriched ticket | `Deploy/Ops:` leads; implementation prose de-emphasized; rollback + watch-list present |
| A5 | `status --for-exec` on an enriched ticket | Business/risk/cost/confidence lead; PR/commit hashes stripped; ticket link kept |
| A6 | `status --for-eng` on a ticket with **no** `Model/Eval:` | Renders cleanly; absent section simply omitted (graceful degradation) |
| A7 | `status --for-exec` on an **epic** | Aggregates children: risk concentration, dependency graph, confidence spread, cost rollup — in exec framing |
| A8 | `status` on a **story** (post-change) | Single-ticket summary, unchanged from today (no accidental aggregation) |
| A9 | Agent has weak evidence for a section | Section omitted, not hallucinated; gate shows the conservative draft |

## Out of scope

- A standalone `/bitacora:rollup` command (folded into `status` per D5).
- Per-role render modes beyond the 5-lens enum (D4).
- Flag-free audience inference (status still takes an explicit lens flag; inferring the
  reader's role automatically is a possible later refinement, not this design).
- Changes to where `[CTX]` is stored (still Jira comments) or to the Remember scratch
  split.
- A machine-enforced controlled vocabulary for `Impact:` / tags — the initial lists are
  conventions the skill documents; the validator does not enforce them (consistent with
  how the format skill treats reference conventions today).
- Non-Jira backends.
```
