# Design — Parked-debt rollup in the digest aggregate (re-scope of #85)

**Date:** 2026-06-09
**Status:** Approved design, ready for implementation planning
**Closes:** #85 (`/digest` Phase B)
**Touches:** `plugins/bitacora/skills/session-digest/SKILL.md`, its `examples/`, `plugins/bitacora/scripts/test-digest-fixtures.sh`, `MANUAL-ACCEPTANCE.md`

## Summary

Issue #85 was written as a five-feature Phase B (`--debt`, `--risk`, `--deps`,
`--board`, saved-scope config). Audited against the surface that **already ships** in
`session-digest`, four of the five are convenience over existing capability, not a missing
signal:

- The default **aggregate already renders** a *Risk concentration* section and a
  *Dependency graph* — so `--risk` / `--deps` would only be deeper views of signals
  already on screen, not net-new information.
- `--board` is marginal over the existing `--jql` scope selector (a board is a saved JQL);
  board→active-sprint resolution is the only thing JQL can't trivially express, and it
  doesn't justify a flag.
- The saved-scope config (`digest.default_board` / `digest.default_jql`) is pure
  convenience, and `default_board` is dead without `--board`.

The **one genuine gap** is *parked debt*: `[debt]`-tagged `Decisions:` bullets live in the
`[CTX]` corpus but nothing aggregates them across a scope. This design closes that gap with
**zero new interface** — a *Parked debt* section folded into the aggregate the digest
already prints — and closes #85's other four features as won't-do.

Guiding constraint (user): *keep the command signature as simple as possible; add a flag
only when needed, never for convenience.* This design adds no flag, no scope selector, and
no config key.

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **No new flag — debt becomes an aggregate section, not a `--debt` lens** | The aggregate is the thing readers already see; a section surfaces the signal with zero interface cost. A dedicated lens is only justified if the ledger swamps the digest — unproven, so YAGNI. Revisit (promote to `--debt`) only if dogfooding shows the ledger is too large to live inline. |
| D2 | **Computed in the shared §5 aggregate signals → appears in epic-rollup *and* multi-ticket scope for free** | §5 already states the computation is identical whether the source is an epic's children or a resolved scope set. Adding the signal there means both paths get it with one change and stay consistent. |
| D3 | **`--risk` / `--deps` closed as already-covered; add one in-place deepening to Risk concentration** | The Dependency-graph signal already renders intra-set edges + cross-set bullets — exactly what `--deps` promised; no change. Risk concentration lists risk-bearing tickets but does **not** flag *recurrence* — the one thing `--risk` would have added. Add a recurrence-flag clause in place. |
| D4 | **`--board` and saved-scope config dropped as won't-do** | Marginal over `--jql`; matches how this project has retired marginal-value ideas (commit-anchor, forecasting, native links). |
| D5 | **No new data is read — pivot on fields already in hand** | The corpus read (§4/§5) already captures `[debt]`/`[precedent]`/`[blast-radius]` tags. The debt ledger is a render-time pivot on existing structured fields, not a new fetch. |
| D6 | **Read-only, strict `[CTX]` only, same coverage discipline** | Unchanged from the rest of the digest. No write path, no lenient reads. |

## What changes

### 1. New aggregate signal (§5)

Add one bullet alongside the existing Risk-concentration / Dependency-graph / Cost-rollup
signals:

> **Parked debt** — every `[debt]`-tagged `Decisions:` bullet across the reporting tickets
> → one ledger line each: `KEY · the deferred decision · linked follow-up if the bullet
> names one`. Empty if none. Same **no-invention** rule — only `[debt]` tags that actually
> exist; never synthesize a debt item.

### 2. In-place deepening of Risk concentration (§5)

Append to the existing Risk-concentration bullet:

> …**when the same surface or dependency recurs across 2+ tickets, flag it as
> *concentrated*** (name the recurring surface once, list the tickets). Recurrence is
> evidence-based — only flag a surface the bullets actually share; never infer a theme.

The Dependency-graph signal is unchanged (already covers the `--deps` intent).

### 3. Render slot (§6)

Debt is an oversight signal. It renders in the two oversight lenses plus self, and is
omitted where it's noise. Empty ledger ⇒ section omitted entirely, like *Top risks* today.

| Lens | Debt rendering |
|---|---|
| `--for-exec` | `Debt:` line — business framing (parked tradeoffs carried forward) |
| `--for-eng` | `Parked debt:` line — technical, with the linked follow-up |
| `--for-self` | folded into the terse tail (your own parked debt) |
| `--for-pm` / `--for-ops` | omitted (not their altitude) |

The recurrence-flagged risk lines render wherever the existing risk section already renders
(`Top risks:` in exec, `Open risks / blockers:` in eng, etc.) — the flag is a phrasing
addition, not a new slot.

The default cross-ticket digest inherits the *Aggregate render* template, so it needs no
separate render rule — it gets both changes via §6's shared template.

### 4. Slack render (§6 Slack block)

The `examples/multi-aggregate-slack.txt` render carries the new `Debt:` / `Parked debt:`
line under the same single-asterisk emphasis convention as the other inline labels. No new
Slack-specific rule beyond keeping the section present.

## Testing

- **Fixtures.** Add a `[debt]`-tagged `Decisions:` bullet (and a recurring-surface risk) to
  the shared fixture scenario so the section has content. Extend the committed renders:
  `examples/multi-aggregate.txt`, `examples/multi-aggregate-slack.txt`,
  `examples/epic-exec.txt`, `examples/epic-eng.txt` — each shows the debt ledger; the
  `--for-eng` / `--for-exec` renders show the recurrence flag.
- **`scripts/test-digest-fixtures.sh`** (fixture-contract lint, CI-wired). Add assertions:
  the aggregate fixtures surface the debt ledger line(s) for the expected tickets; the
  recurrence flag appears on the shared-surface risk; and a *negative* check that a no-debt
  scenario omits the section (degrade-gracefully). Deterministic, no LLM, no Jira.
- **`MANUAL-ACCEPTANCE.md`.** One new item: run the default aggregate over a real
  multi-ticket scope (and one epic) that carries parked debt; confirm the ledger is honest
  (only real `[debt]` tags, correct follow-up links) and the concentration flag fires only
  on a genuinely shared surface.

## Out of scope (this iteration / closed from #85)

- **`--debt` as a dedicated lens** — deferred behind D1; promote only if the inline section
  proves too small to hold a real sprint's ledger.
- **`--risk` / `--deps` flags** — closed; covered by the existing aggregate sections plus
  the recurrence deepening (D3).
- **`--board <id|name>`** — dropped (D4); `--jql` covers scope naming.
- **Saved-scope config** (`digest.default_board` / `digest.default_jql`) — dropped (D4).
- **Posting the digest back to Jira / velocity-ETA forecasting** — unchanged non-goals from
  the parent multi-ticket design.

## Open questions

None blocking. Settle during planning if they arise:

- **Debt line ordering.** Most-recent `[CTX]` first, or grouped by ticket? Leaning:
  group by ticket (matches `By ticket:` ordering already in the aggregate).
