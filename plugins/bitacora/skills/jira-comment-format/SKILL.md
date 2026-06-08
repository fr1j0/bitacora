---
name: jira-comment-format
description: The [CTX] Jira-comment format — how to WRITE compliant agent comments and how to READ them under strict/lenient compliance. Use whenever drafting a Jira comment or extracting state from ticket comments (handoff, status, ranking).
allowed-tools: Read
---

This skill is the single source of truth for the `[CTX]` comment format. The
human-facing companion `docs/JIRA_AGENT_COMMENT_FORMAT.md` defers to this file.

## Canonical `[CTX]` status update

Required = the header line + a `Status:` line + a `Next:` line.
`Done`/`Decisions`/`Blockers`/`Open questions` are optional and appear only when
non-empty. Order below is recommended; compliance is order-independent.

```
[CTX] Status update                    ← REQUIRED: header line

Status: <state>                        ← REQUIRED

Done:                                  ← optional — omit if empty
- <bullet>

Decisions:                             ← optional — bullet + rationale
- <bullet>

Next:                                  ← REQUIRED
- <bullet>

Blockers:                              ← optional
- <bullet>

Open questions:                        ← optional — team/PM-facing only
- <bullet>
```

A **blank line separates every block** (the `Status:` line, each section label, and
each bullet list). This is not cosmetic — see *Write mechanics* below.

See `examples/compliant.txt` for a full compliant example.

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
- `Risk:` — a latent risk that could bite later (what could go wrong, plus any mitigation).
  Distinct from `Blockers:` (a hard stop now).

One single-line field:

- `Impact: <surfaces>` — a comma-separated list of surfaces touched, from the convention
  vocabulary `api · schema · ui · data-pipeline · model-serving · infra · config · docs`,
  so a reader self-selects relevance. Convention only — the validator does not enforce the
  vocabulary.

Cost is not a section of its own: write it as a `$` line **folded into** `Deploy/Ops:`
(infra) or `Model/Eval:` (inference/training).

Two elements you already write can also take an optional enrichment:

The `Status:` line may carry an optional confidence cue —
`Status: In Progress (confidence: high)`, with `confidence ∈ {high, medium, low}`. Omit it
when not assessed.

`Decisions:` bullets may carry trailing inline tags so senior readers scan the org-shaping
choices without reading every local one: `[precedent]` (sets a pattern others should
follow), `[debt]` (incurs tech debt, ideally ticketed), `[blast-radius]` (touches
widely-shared code). Convention only; the validator does not enforce them.

See `examples/compliant-enriched.txt` for a body exercising several of these.

**No date in the header.** Every Jira comment already carries an authoritative
`created` timestamp (returned by the API, shown in the UI next to the author) — a
hand-typed date just duplicates it and can drift or be wrong. Read the date from
comment metadata, not the body. (If you ever excerpt a `[CTX]` *outside* Jira where
that metadata is lost, add the date then — but never in the comment itself.) The
validator checks only the `[CTX]` prefix and the presence of `Status:`/`Next:` lines.

## Write rules (hard)

- Outcome-oriented, not process. *What changed and why*, not *how I figured it out*.
- No verbose play-by-play; no code diffs (link the PR instead); no mid-task
  speculation (that belongs in local Remember scratch).
- One comment per logical update, not one per turn.
- **Open questions placement:** team/PM-facing questions go in the `Open questions:`
  section of the `[CTX]` comment; next-session-only questions go to Remember scratch.
- **URLs must be wrapped, never bare.** Jira's ADF renderer does **not** auto-linkify
  text. A bare `https://...` will display as plain text and won't click through. Write
  every URL as either a markdown link `[label](https://...)` (preferred — readable label)
  or an autolink `<https://...>` (label = URL). If you build ADF directly, attach a
  `link` mark to the URL text node. See `examples/malformed-bare-url.txt`.
- **Identifiers get backticks.** Wrap file paths, branch names, commit SHAs, symbol
  names, config keys, and slash commands in inline code (`` `splitPortfolioName` ``,
  `` `features/client-portfolios/portfolio-utils.ts` ``, `` `/bitacora:improve` ``).
  They render as `code` marks in ADF and stand out from prose, making the comment
  scannable. Bare-text identifiers blend into surrounding text and slow the reader.
- **Compact references over bare URLs.** When you mention a PR or a cross-ticket, link
  the short reference, not the full URL. Write ``PR [#7951](https://github.com/org/repo/pull/7951)``
  or ``[AT-4537](https://wgen4.atlassian.net/browse/AT-4537)``. The visible label stays
  the short token humans naturally read (`#7951`, `AT-4537`); the URL is hidden behind
  it. Same rationale as the URL bullet above, applied to references humans write as
  short tokens rather than full URLs. The validator does not enforce this — bare
  `#7951` or `AT-4537` tokens are too easy to false-positive on (commit messages,
  branch names) — but writers should follow the convention.
- **No tool-call XML in the body.** Substrings like `<parameter name=`, `</commentBody>`,
  `<invoke name=` are agent-tool-call sentinels — they indicate the authoring agent
  serialized part of its own MCP call into the comment. Never appears in a legitimate
  `[CTX]`. See `examples/malformed-tool-leak.txt`.

## Write mechanics (rendering-safe)

`addCommentToJiraIssue` converts `commentBody` (when `contentFormat: markdown`, the
default) to ADF. Markdown's **lazy continuation** merges adjacent non-blank lines into
one block, which silently corrupts a `[CTX]`:

- a label placed directly after a bullet (`...moved to In Progress` ⏎ `Decisions:`) gets
  **absorbed into that bullet** as a soft line-break — the label disappears as a heading;
- two label/value lines with no blank line (`Status: In Progress` ⏎ `Done:`) **merge into
  one paragraph**.

So the hard rule: **put a blank line before and after every section label and every
bullet list.** Each label is its own paragraph; each list is its own block. Bullets are
top-level (`- x`), not indented. Verify by reading the comment back with
`responseContentFormat: adf` — every label must be a standalone `paragraph` node and each
group of bullets a separate `bulletList`, with no `\n` inside a list item's text.

For guaranteed fidelity (no converter in the loop), build the body as ADF directly and
pass `contentFormat: adf`; markdown-with-blank-lines is the lighter default and renders
correctly.

## Audience lenses

`/bitacora:status` and `/bitacora:digest` both render `[CTX]` through five audience lenses;
pass the flag for the reader's role. This table is the single source of truth for lens
**altitude** (what each lens leads with and strips); each command supplies its own render
templates (single-ticket in `bitacora:session-status`, aggregate in `bitacora:session-digest`).

| Lens | Flag | Roles it serves | Leads with / strips |
|------|------|-----------------|---------------------|
| self | `--for-self` | you | terse recall — latest Status + Next |
| eng  | `--for-eng`  | frontend, backend, full-stack, staff, AI staff, tech lead | contract, `Artifacts:`, `Model/Eval:`, `Decisions:`+tags; keeps PR/commit links |
| ops  | `--for-ops`  | devops, infra, MLOps | `Deploy/Ops:`, rollback, watch-list, `Impact:`; keeps links |
| pm   | `--for-pm`   | product, technical managers | plain language; confidence; `Risk:`/`Dependencies:` as asks; strips PR/commit hashes, keeps ticket link |
| exec | `--for-exec` | CTO, CRAIO | business/risk/cost + confidence; strips implementation detail, keeps ticket link |

A lens **degrades gracefully**: if the `[CTX]` lacks a section the lens would lead with, omit
it silently (a UI ticket under `--for-ops` simply has no `Deploy/Ops:` to show).

## Read-side compliance

- **Prefix match, with optional preamble.** A comment is treated as `[CTX]` if its
  first *non-preamble* line starts with `[CTX]`. Preamble = zero or more leading lines
  that are blank or whose trimmed content begins with `_`, `*`, or `(` (italic-markdown
  or parenthesized housekeeping notes — e.g. `_(Replaces malformed comment 58307.)_`).
  A short note above the header is established practice; the structural check skips
  past it but hygiene rules still scan the full body. A comment that mentions `[CTX]`
  mid-sentence (e.g. `"as we noted in yesterday's [CTX]..."`) is *non-`[CTX]`* — never
  an attempt at compliance. See `examples/non-ctx.txt` and
  `examples/compliant-with-preamble.txt`.
- **Compliant** = `[CTX]` header (after any preamble) + a `Status:` line + a `Next:`
  line. Optional sections never affect compliance.
- **Two failure classes, surfaced separately:**
  - *non-`[CTX]`* (free-form human comment) → skip, count as "not in format".
  - *malformed `[CTX]`* (starts with `[CTX]` but missing `Status`/`Next`) → skip,
    count **separately** as "malformed". See `examples/malformed.txt` (which shows the
    `Next:`-absent case; the `Status:`-absent case is symmetric).
- **Never silently drop.** Surface counts, e.g.:
  `Note: 4 comments excluded (3 not in [CTX] format, 1 malformed). Run with --include-all to see them.`

The script `../../scripts/validate-ctx.sh` (i.e. `plugins/bitacora/scripts/validate-ctx.sh`
from the repo root) encodes these rules and can classify any single comment
(`compliant` / `malformed` / `not-in-format`). It also catches the *Write rules* hygiene
classes — bare URLs and tool-arg-leak sentinels — as `malformed`, with a one-line reason
on stderr. **Handoff pipes every drafted body through it before writing.**

## Strict vs lenient by operation

| Operation | Mode | Phase |
|-----------|------|-------|
| `/bitacora:resume`, `/bitacora:status`, `/bitacora:next`, cross-ticket JQL | strict | 3 / 5 / later |
| `/bitacora:improve` source read, onboarding, decision archaeology | lenient | 2+ |
| `/bitacora:handoff` continuity read (read latest `[CTX]` to thread `Status`/`Next`, avoid restating `Done`) | lenient | 1 |

- **strict** = count a comment only if it is *compliant* (starts with `[CTX]` and has
  `Status:` + `Next:`); skip non-`[CTX]` and malformed comments, tallying them separately.
- **lenient** = read every comment regardless of prefix or sections — human discussion is
  exactly what's wanted there; do not skip non-compliant comments.

Phase 1 ships and exercises the **write** path. The strict-read machinery is defined
here for later consumers; the only read Phase 1 performs is handoff's lenient
continuity-read, which falls back gracefully when there is no prior `[CTX]`.

## Sibling prefixes (out-of-format)

Bitácora reserves the `[CTX]` prefix for state-extraction reads. Other prefixes are
written by specific commands for distinct purposes; `validate-ctx.sh` classifies them
as `not-in-format` (exit 2) and strict readers (`/bitacora:resume`,
`/bitacora:status`, `/bitacora:next`) skip them — intentionally, because they are
not state updates.

| Prefix | Written by | Purpose |
|--------|------------|---------|
| `[ARCHIVE]` | `/bitacora:improve` | Pre-edit snapshot of the ticket's description and/or title, posted **before** the field rewrite so the original is reversible by copy-paste. |

`[ARCHIVE]` is the only sibling prefix in v1. A future command adding a new sibling
prefix should land here with the same row shape: prefix, writer command, purpose. The
validator's prefix check is intentional: anything that doesn't start with `[CTX]` is
classified `not-in-format` and skipped by strict readers, no further machinery
required.

See `examples/archive.txt` for a rendered `[ARCHIVE]` body.

## Format version & compatibility

**Current version: `v1`** (implicit). A compliant comment's trimmed body starts with the
literal `[CTX]` prefix and carries the required `Status:` and `Next:` fields. Bare `[CTX]`
always means v1 — no per-comment version token is written.

**What readers can rely on within v1:**

- The **required shape** (`[CTX]` prefix + `Status:` / `Next:`) will not change incompatibly.
- **Optional sections are additive** — new ones (e.g. `Model/Eval:`, `Related:`) may land in
  minor releases; strict readers ignore sections they don't recognize, so adding one never
  breaks an older reader.

**Breaking the required shape is a format major bump to `v2`**, which will (1) be called out
under a "Format" heading in the CHANGELOG, and (2) be written with an explicit **`[CTX v2]`**
prefix. Readers detect version by prefix: `[CTX]` → v1, `[CTX vN]` → vN. Because `[CTX v2]`
does not match the literal `[CTX]` prefix (the character after `CTX` is a space, not `]`), a
v1 reader safely skips a v2 comment rather than mis-parsing it.

## Configuration

Defaults (used inline unless overridden):

```yaml
comment_compliance:
  status_extraction: strict          # /bitacora:status, /bitacora:next, JQL
  requirements_reading: lenient      # /bitacora:improve, onboarding
  show_excluded_count: true
  partial_match: false               # strict prefix only
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"   # top-level; shared by detection + JQL. DEFAULT only.
staleness_grace: 2d                          # top-level; drift tolerance (<N>h | <N>d) before a ticket's latest [CTX] is "behind" its `updated`. Used by /resume + /status.
```

`project_key_pattern` is user-overridable; common alternates: lowercase keys
(`proj-1234`), alphanumeric suffixes (`PROJ-1234A`), longer/compound prefixes.

**Overrides:** if present, read `${CLAUDE_PROJECT_DIR}/.bitacora.yml`, else
`~/.claude/bitacora.yml`. Absence is normal — fall back to the defaults above silently.

`/bitacora:digest` reads its own `digest.*` keys, each **falling back to the legacy
`status.*` key** of the same name (then the built-in default) so existing configs keep working:

```yaml
digest:
  epic_type: Epic            # issue type that triggers epic rollup (was status.epic_type)
  epic_children_cap: 50      # max children read per epic (was status.epic_children_cap)
  epic_default_mode: exec    # lens for an epic target with no --for-* (was status.epic_default_mode)
  multi_fanout_cap: 25       # max tickets read per scope (was status.multi_fanout_cap)
  default_mode: self         # lens for a scope read with no --for-* (was the multi default)
```

Resolution per key: `digest.<key>` → legacy `status.<key>` → built-in default.
`status.ctx_lookback` and `status.default_mode` remain single-ticket-only.
