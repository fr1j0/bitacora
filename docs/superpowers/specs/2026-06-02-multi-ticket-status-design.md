# Design — Multi-Ticket `/status` (Cross-Ticket Reads via Lenses)

**Date:** 2026-06-02
**Status:** Approved design, ready for implementation planning
**Scope:** Extend `/bitacora:status` from single-ticket / epic-rollup synthesis to an
arbitrary **multi-ticket scope**, and add an orthogonal family of **query lenses** that
decide *what* to surface across that scope. Cashes in the read side of the
shared-memory thesis: once a corpus of `[CTX]` comments exists, the high-value reads are
cross-cutting (what's blocked, what moved, what debt is parked) — not one ticket at a
time.

## Summary

Today `/bitacora:status` reads one ticket (or one epic, fanning out to its children) and
reshapes the result through an **audience** lens (`--for-self / --for-eng / --for-ops /
--for-pm / --for-exec`). It cannot answer questions that span an *arbitrary* set of
tickets — "what of mine is stuck", "what moved since yesterday" — because it has no way
to name a set that isn't a single epic, and no lens that filters *content* rather than
*altitude*.

This design adds two things behind the existing command:

1. **A third read mode — multi-ticket scope.** Beyond a single key and an epic, `/status`
   accepts a scope selector (`--mine`, `--sprint`, `--board <b>`, `--jql "<q>"`, or 2+
   explicit keys) that resolves to a concrete key list via JQL.
2. **A second, orthogonal lens family — query lenses.** Where audience lenses decide
   *altitude*, query lenses decide *what to pull out*: `--blocked`, `--standup` (Phase A)
   and `--debt`, `--risk`, `--deps` (Phase B). Default query lens = the existing
   portfolio aggregate.

The three knobs compose: **scope × query lens × audience.** `/status --sprint --debt
--for-exec` = "the debt ledger across my sprint, for a VP." `/status --mine --blocked` =
"what of mine is stuck." `/status --standup --since 1d` = standup prep.

**Backward-compatible by construction:** bare `/status KEY` and `/status EPIC` are
untouched. The new behavior activates only on a scope flag or 2+ keys. No new command, no
new alias — continuing the precedent set in the CTX-enrichment design (D5: "fold
aggregation into `status`, don't add a rollup command").

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Extend `/status`; no new command or alias** | Continues CTX-enrichment D5. A portfolio/triage view only changes the *scope of the target* and the *pivot on its content* — both things `status` can infer/accept. A new command would split a single mental model ("ask Jira where things stand") across two verbs. |
| D2 | **Two orthogonal lens families** (audience × query), not one merged enum | Audience = altitude (*how to render*); query = content pivot (*what to surface*). Merging them (e.g. a `--blocked-for-exec` lens) would be a combinatorial explosion. Keeping them orthogonal means `5 audience × 6 query` compose for free. |
| D3 | **Scope resolves to a key list via JQL, then reuses the corpus-read path** | The epic rollup already proved fan-out → strict-read each child → aggregate. A scope selector is just a different *way to name the set*; everything downstream is shared. No new read machinery. |
| D4 | **Strict `[CTX]`-only reads; honest exclusion + no-context buckets** | Consistent with `next`/`status`/JQL (format skill: "cross-ticket JQL = strict"). Surface excluded (non-`[CTX]`/malformed) counts and a separate **no-context (N)** bucket; never silently drop a ticket from the set. |
| D5 | **Capped fan-out with explicit "N of M" disclosure** | A board scope can be hundreds of tickets. Default cap ~25, surfaced as *"showing N of M — narrow with `--jql`."* No silent truncation (matches the project's no-silent-caps principle). |
| D6 | **Read-only; posting a digest is a non-goal this iteration** | Keeps parity with current `status`. Posting a `[STATUS]` comment back to Jira is deliberately deferred — it introduces a write path, audience-of-record questions, and a new sibling prefix; revisit only if demand appears. |
| D7 | **Phased: scope + aggregate + `--blocked` + `--standup` first** | "All three consumers via lenses" is a large surface. Phase A (the two highest-frequency lenses) already serves IC triage, lead glance, and ceremony prep minimally. The lead-oversight depth (`--debt`/`--risk`/`--deps`) follows in Phase B once the scope+pipeline is proven. |
| D8 | **Factor the multi-ticket pipeline into its own skill section** | `session-status/SKILL.md` is already the largest skill (341 lines). The single-ticket path must stay readable; the multi-ticket pipeline lands as a distinct, clearly-bounded section (split to a referenced doc if it outgrows the file). |

## Architecture — a four-layer pipeline

Each layer has one purpose, a defined input/output, and is independently testable.

```
  scope arg ──▶ [1] Scope resolution ──▶ key list
                                           │
                                           ▼
                          [2] Corpus read (strict [CTX], per key)
                                           │  structured fields + exclusion tallies
                                           ▼
                          [3] Query lens (pivot the corpus)
                                           │  aggregate | blocked | standup | …
                                           ▼
                          [4] Render (audience altitude, existing --for-*)
```

### Layer 1 — Scope resolution

Turns the scope argument into a concrete list of ticket keys. Touches
`skills/session-status/SKILL.md`; JQL templates table is the single source.

| Scope arg | Resolves to (JQL) | Notes |
|---|---|---|
| `KEY` (single, non-epic) | `[KEY]` | **Existing** single-ticket path — unchanged. |
| `EPIC-KEY` | children via parent/epic-link | **Existing** rollup path — unchanged. |
| `--mine` | `assignee = currentUser() AND statusCategory != Done` | Default IC scope. |
| `--sprint` | `… AND sprint IN openSprints()` | Spans the user's open sprints; needs no board (the `--board` row does). |
| `--board <id\|name>` | board's active sprint / backlog | **Phase B**; needs board resolution. |
| `--jql "<q>"` | passthrough | Power-user escape hatch. |
| `KEY-1 KEY-2 …` (2+) | that explicit set | Triggers multi-ticket mode without a flag. |

Activation rule: multi-ticket mode engages iff a scope flag is present **or** 2+ keys are
passed. Otherwise the existing single-ticket / single-epic behavior runs verbatim.

Fan-out is capped (default ~25; overridable). When `M > cap`, read the first `cap`
(ordered by most-recently-updated) and emit *"showing N of M — narrow with `--jql`."*

### Layer 2 — Corpus read

For each resolved key, strict-read the **latest** `[CTX]` and extract the structured
fields already defined by the format skill: `Status` (+ `confidence`), `Done`,
`Decisions` (+ `[debt]`/`[precedent]`/`[blast-radius]` tags), `Next`, `Blockers`,
`Dependencies`, `Risk`, `Impact`, `Deploy/Ops`, `Model/Eval`, `Artifacts`. Capture each
`[CTX]`'s `created` timestamp from comment metadata (needed by `--standup` and staleness
sorts).

- Prefer `searchJiraIssuesUsingJql` to batch-fetch issues (with comments where the API
  allows); fall back to per-ticket `getJiraIssue`.
- Tally **excluded** comments (non-`[CTX]` / malformed, counted separately) per the
  existing read-side discipline.
- A ticket in scope with **no `[CTX]` at all** goes into a **no-context (N)** bucket —
  surfaced explicitly, never omitted, so the reader knows coverage is partial.

### Layer 3 — Query lens (the pivot)

Default (no query flag) = the **portfolio aggregate**, reusing the epic-rollup renderer
(health, confidence distribution, risk concentration, dependency graph, cost roll-up) now
over an arbitrary set instead of an epic's children.

**Phase A lenses:**

- **`--blocked`** — filter to tickets carrying `Blockers:` or `Dependencies:`. Sort by
  staleness (newest `[CTX]` `created`, oldest-first). For each: what/who is waited on, how
  long. Answers "what's stuck."
- **`--standup [--since <when>]`** — time-windowed. `<when>` ∈ `1d` / `2d` /
  `last-working-day` (default `last-working-day`). Surface tickets whose latest `[CTX]`
  falls inside the window: what *moved*, the current `Next:`, and anything newly flagged in
  `Risk:`/`Blockers:`. Answers "what changed and what do I say."

**Phase B lenses:**

- **`--debt`** — every `[debt]`-tagged `Decisions:` bullet across the set → one ledger
  (ticket · decision · linked follow-up if present).
- **`--risk`** — every `Risk:` section → a register; flag concentration (same surface /
  same dependency recurring).
- **`--deps`** — cross-ticket `Dependencies:` → an intra-set graph plus edges pointing
  outside the set.

### Layer 4 — Render (audience)

The existing `--for-*` altitude applied to the lens output. Default audience for
multi-ticket mode = `--for-self` (IC triage is the most frequent caller). Document that
`--debt`/`--risk`/`--deps` read most naturally at `--for-eng` or `--for-exec`; the user
can always override. (The single-epic path keeps its existing `exec` default.)

## Phasing

- **Phase A (ship first):** Layer 1 (`--mine`, `--sprint`, `--jql`, explicit keys) +
  Layer 2 (shared corpus read) + Layer 3 default aggregate + `--blocked` + `--standup` +
  Layer 4 (existing render). Serves all three consumers minimally.
- **Phase B:** `--debt`, `--risk`, `--deps`; `--board` resolution; optional
  `.bitacora.yml` keys `default_board` / `default_jql`.

## Configuration

No required new config for Phase A. Phase B adds optional keys (same override files —
`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is normal):

```yaml
status_multi:
  fanout_cap: 25              # max tickets read per multi-ticket invocation
  default_board: ""           # Phase B — board for --board / --sprint resolution
  default_jql: ""             # Phase B — a saved scope for bare multi-ticket calls
```

`project_key_pattern` and the compliance modes are unchanged, inherited from the
`jira-comment-format` skill.

## Testing

- **Golden fixtures** under `skills/session-status/examples/` — a set of mock `[CTX]`
  bodies across N tickets with expected output for: the default aggregate, `--blocked`,
  and `--standup` (incl. the `--since` window boundary and the no-context bucket).
- **`MANUAL-ACCEPTANCE.md`** entries: run each Phase A lens against a real multi-ticket
  scope; verify exclusion counts and the "N of M" cap disclosure render honestly.
- The deterministic parse/classify is already covered by `validate-ctx.sh`; no validator
  rule change (presence-based, enriched bodies already classify `compliant`).

## Out of scope (this iteration)

- Posting a digest back to Jira as a `[STATUS]` comment (D6).
- A new command or `/bit:` alias (D1).
- `--board` resolution and saved-scope config (deferred to Phase B).
- Non-`[CTX]` (lenient) reads — multi-ticket synthesis is strict-only (D4).
- Velocity / ETA forecasting across the set — out of Bitácora's scope entirely (see the
  dropped forecasting idea); this lens family reports *recorded* state, it does not
  predict.

## Open questions to settle during planning

- **Default audience by lens?** Should `--debt`/`--risk` auto-default to `--for-eng`/`exec`
  rather than `--for-self`, given who typically asks? Leaning: keep one default (`self`),
  document the natural pairings, don't special-case.
- **`--standup` "moved" definition.** Window on the latest `[CTX]` `created` only, or also
  count Jira `status` field transitions in the window? Leaning: `[CTX]`-only for v1
  (consistent with strict discipline); revisit if it misses real movement.
- **Batch-read fidelity.** Confirm `searchJiraIssuesUsingJql` can return comment bodies in
  one call; if not, the per-ticket fallback sets the practical fan-out cap.
