# Pluggable tracker backends for Bitácora (GitHub Issues, GitLab-ready)

**Issue:** #117 — Add a GitHub Issues tracker backend (multi-tracker support beyond Jira)
**Date:** 2026-06-23
**Status:** Design approved; ready for implementation plan

## Problem

Bitácora is Jira-only by construction. Every read skill (`next`, `resume`,
`status`, `digest`) and write skill (`handoff`, `improve`) assumes an Atlassian
site, Jira issues, and `[CTX]` comments on Jira tickets. In a repo whose tracker
is GitHub Issues (no Jira project at all — e.g. the `vatios` project), `next` at
best surfaces an unrelated Jira backlog and at worst has nothing meaningful to
read.

This design introduces a **pluggable tracker backend** so the skills can target
Jira *or* GitHub Issues (with GitLab as a near-mechanical follow-up), selected
per-repo.

## Goals / non-goals

**Goals**
- Per-repo selection of `jira | github | gitlab`, zero-config in the common case.
- One logical `[CTX]` format across all backends; backend-specific *render* only.
- Minimal disturbance to the battle-tested Jira (MCP) path.
- Testable, deterministic backend wiring consistent with the existing `*.sh` +
  `test-*.sh` culture.
- GitHub shipped and validated first; GitLab enabled by the same seam.

**Non-goals (YAGNI)**
- Linear or other trackers.
- Bidirectional Jira↔GitHub sync.
- Perfect epic-rollup parity across trackers (graceful degradation instead).

## Decisions (settled in brainstorming)

1. **Resolution = hybrid (infer + explicit override).** Infer from the git
   remote host; an explicit `tracker:` in config always wins.
2. **Abstraction = hybrid (shell adapter for CLI backends, MCP inline for
   Jira).** Skills branch once on tracker *family* (`mcp` vs `cli`). The `cli`
   path calls one uniform, tested adapter script over `gh`/`glab`; the `mcp`
   path is today's Jira code, essentially untouched.
3. **Sequencing = GitHub first, GitLab-ready seam.** Build the abstraction for N
   backends; ship+validate GitHub against `vatios`; GitLab follows as a second
   adapter column in a separate PR.
4. **Capability table lives in a `tracker-adapter` SKILL doc** (consistent with
   the existing `jira-comment-format` SKILL the skills already consult). Config
   files hold only `tracker:` and the existing Jira maps.
5. **Epic-rollup degrades gracefully and says so** — GitHub rolls up via
   sub-issues if present, else milestone; output honestly labels the basis
   rather than faking Jira-epic parity.

## Architecture

```
                ┌──────────────────────────────────────────┐
   skill  ──▶   │ resolve-tracker.sh  → jira | github | gitlab
                └──────────────────────────────────────────┘
                              │ branch once on family
            ┌─────────────────┴───────────────────┐
        family = mcp                          family = cli
            │                                      │
   Atlassian MCP (today's                bitacora-tracker.sh <verb>
   Jira code, untouched)                 ├── github → gh …
                                         └── gitlab → glab …
                                              emits normalized JSON
```

### Component 1 — `resolve-tracker.sh`

New sibling to `resolve-project-scope.sh`, reusing that script's remote-slug
normalizer.

- **Input:** `--dir`, `--repo-config`, `--home-config` (same conventions as
  `resolve-project-scope.sh`).
- **Resolution order:**
  1. Explicit `tracker:` in `<repo>/.bitacora.yml`, else `~/.claude/bitacora.yml`.
  2. Inferred from the normalized git remote: `github.com/*` → `github`;
     `gitlab.com/*` and recognized self-managed GitLab hosts → `gitlab`;
     anything else → `jira`.
- **Output / exit codes:**
  - `0` stdout = `github | gitlab | jira`.
  - `2` usage error.
  - `4` not a git repo / no remote *and* no explicit `tracker:` — stderr explains
    how to set one.
- Paired `test-resolve-tracker.sh` covering: explicit override beats inference;
  each host inference; self-managed GitLab via explicit config; no-remote
  fallback to explicit or error.

### Component 2 — `bitacora-tracker.sh <verb>` (CLI adapter)

Thin, uniform verbs over `gh`/`glab`, dispatched on `$TRACKER`. Jira never
enters this script.

| Verb | GitHub (`gh`) | GitLab (`glab`) |
|---|---|---|
| `list-mine` | `gh issue list --assignee @me --state open --json number,title,labels,updatedAt,milestone` | `glab issue list --assignee=@me` |
| `view <id>` | `gh issue view <id> --json number,title,body,labels,state,milestone` | `glab issue view <id>` |
| `comments <id>` | `gh issue view <id> --json comments` | `glab issue note list <id>` |
| `comment <id> --body-file <f>` | `gh issue comment <id> --body-file <f>` | `glab issue note create <id> --message …` |
| `edit-body <id> --body-file <f>` | `gh issue edit <id> --body-file <f>` | `glab issue update <id> --description …` |
| `whoami` | `gh api user -q .login` | `glab api user` |
| `doctor` | verify `gh` installed + authed | verify `glab` installed + authed |

- **Normalized JSON output.** Every verb emits the same schema regardless of
  backend, so consuming skills read one shape (e.g. comments →
  `[{author, createdAt, body}]`). GitLab field differences are mapped inside the
  adapter, not in the skills.
- **`doctor` precondition.** Skills call `doctor` first (or the adapter
  self-checks) and fail with an actionable message ("`gh` not authenticated —
  run `gh auth login`") rather than a raw CLI error.
- Paired `test-bitacora-tracker.sh` exercising verb dispatch and JSON
  normalization with stubbed `gh`/`glab` (PATH-shimmed fakes, matching the
  existing test harness style).

### Component 3 — `tracker-adapter` SKILL (capability table)

A new SKILL doc (sibling to `jira-comment-format`) the skills consult to reason
about *semantic* differences the verb layer can't paper over.

| Capability | jira | github | gitlab |
|---|---|---|---|
| family | mcp | cli | cli |
| corpus = comments | ✓ | ✓ | ✓ |
| single editable body | description (ADF) | body (md) | description (md) |
| native issue types | ✓ | types (beta) / labels | labels |
| epic / rollup basis | epic→child link | sub-issues, else milestone | native epics |
| renderer autolinks bare URLs | ✗ (ADF) | ✓ (GFM) | ✓ (GFM) |
| identity token | accountId | `@me` / login | `@me` / username |
| scope unit | project key (map) | current repo (owner/repo) | current project |

### Component 4 — `[CTX]` format: one logical spec, per-backend render

The logical structure is unchanged and `jira-comment-format` remains the single
source of truth: `[CTX]` header + `Status:` + `Next:` + the optional enrichment
sections. The literal `[CTX]` marker is retained on every backend — it is the
corpus selector the read skills grep for. `validate-ctx.sh` is format-only and
**carries over untouched**.

A thin **render note** is added per backend family:

- **Jira (ADF):** today's rules unchanged — wrap every URL
  (`[label](url)`/`<url>`), backtick identifiers (ADF code marks). Bare URLs do
  not autolink.
- **GitHub/GitLab (GFM):** the URL-wrapping *requirement* relaxes (GFM autolinks
  bare URLs), though compact `[#123](url)` references stay *preferred* for
  readability; backticks still apply (GFM code spans). The GFM render is strictly
  simpler than Jira's — it removes constraints, adds none.

The render note lives in `jira-comment-format` (the format's single source of
truth); the `tracker-adapter` SKILL points to it so writers pick the right
render by family.

## Per-skill impact

| Skill | Change |
|---|---|
| `next` | `cli` path: `list-mine` scoped to the current repo; ranking/categorization is backend-blind. Jira project-map branch runs only on `mcp`. **Dissolves the original scoping bug** — on cli the scope *is* the repo. |
| `resume` / `status` | Fetch via `comments <id>`, grep `[CTX]`, synthesize. Logic unchanged; only the fetch verb differs by family. |
| `digest` | Multi-issue read is uniform. **Epic-rollup is the one lossy spot:** GitHub rolls up by sub-issues if present, else milestone; GitLab by native epic. Output labels the basis honestly. |
| `handoff` | Draft `[CTX]` (GFM render on cli), write via `comment`. Collision/staleness checks read `comments` the same way. |
| `improve` | `[ARCHIVE]` snapshot → `comment`; rewrite → `edit-body`. **Simpler than Jira** (single markdown body, no ADF). Type-awareness maps from labels / native type, falls back to generic. |
| `help` | Document tracker selection and the `gh`/`glab` prerequisite. |

## Configuration

`.bitacora.yml` (repo) / `~/.claude/bitacora.yml` (home) gain one optional field:

```yaml
tracker: github        # jira | github | gitlab — optional; omit to infer from remote
```

Everything else (the Jira `next.remote_project_map`) is unchanged and remains
Jira-only.

## Testing strategy

- Unit: `test-resolve-tracker.sh`, `test-bitacora-tracker.sh` with PATH-shimmed
  fake `gh`/`glab`, mirroring the existing fixture-driven harnesses.
- Format: existing `test-validate-ctx.sh` continues to cover the logical format
  unchanged; add GFM-render fixtures (bare-URL allowed) to confirm the relaxed
  rule does not regress validation.
- Manual acceptance: run all six read/write skills against the real `vatios`
  GitHub repo; confirm `next` is repo-scoped, a round-trip `handoff`→`resume`
  preserves `[CTX]`, and `improve` edits the issue body + snapshots an
  `[ARCHIVE]` comment.

## Sequencing

1. **PR 1 (this effort):** `resolve-tracker.sh`, `bitacora-tracker.sh` (github
   column), `tracker-adapter` SKILL, render note, and the six skills' `cli`
   branch — GitHub only. Validate on `vatios`.
2. **PR 2 (follow-up):** fill the GitLab column in the adapter + capability
   table; add `glab` test shims. No skill changes expected beyond what PR 1
   already routes by family.

## Risks

- **`gh`/`glab` as a hard dependency.** Mitigated by `doctor` precondition with
  actionable failure text.
- **GitLab self-managed host inference.** Cannot enumerate every host; explicit
  `tracker: gitlab` is the escape hatch (documented).
- **Epic-rollup expectations.** Honest labeling of the rollup basis avoids
  implying Jira-grade parity.
- **MCP path regression.** Mitigated by leaving the `mcp` family code paths
  essentially untouched — the new code is additive on the `cli` branch.
