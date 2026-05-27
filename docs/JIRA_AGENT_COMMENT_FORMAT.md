# The `[CTX]` Jira Agent Comment Format

> **Source of truth:** the literal format and rules are defined operationally in the
> `bitacora` plugin's `jira-comment-format` skill
> (`plugins/bitacora/skills/jira-comment-format/SKILL.md`). This document explains the
> *why* and the team-convention pitch; if the two ever disagree, the skill wins.

## Why a format at all

When agents write Jira comments in a strict, parseable structure, Jira stops being an
ad-hoc dumping ground and becomes a shared external memory layer any teammate's agent can
read to bootstrap context. The format is the highest-leverage single intervention in
Bitácora: adoption compounds.

## The format

Every agent-written comment starts with `[CTX]`. The common variant is the status update.
Required = the header line + a `Status:` line + a `Next:` line; everything
else is optional and appears only when non-empty.

```
[CTX] Status update

Status: In Progress

Done:

- OAuth provider client implemented and tested

Decisions:

- PKCE flow over implicit — more secure for SPAs

Next:

- Token refresh implementation

Blockers:

- None
```

- **Outcome-oriented**, not process. *What changed and why*, not *how I figured it out*.
- No code diffs (link the PR). No mid-task speculation (that's local scratch).
- **No date in the header** — the comment's own `created` timestamp is authoritative;
  read it from metadata, don't hand-type it into the body.
- Put a **blank line before/after every section label and bullet list** — otherwise the
  markdown→ADF conversion absorbs labels like `Decisions:`/`Next:` into the preceding bullet.
- Team/PM-facing open questions go in an `Open questions:` section; next-session-only
  questions stay in local scratch.

## How agents read it

State-extraction operations (status synthesis, ranking, resume) read **strictly**: a
comment counts only if it *starts with* `[CTX]` (not merely mentions it) and has the
required sections. Two failure classes are surfaced separately so the feedback is
actionable:

- **not in `[CTX]` format** — a free-form human comment. Remediation: learn the format.
- **malformed `[CTX]`** — started right but missing `Status`/`Next`. Remediation: fix the
  one comment.

Excluded comments are always counted, never silently dropped:

> `Note: 4 comments excluded (3 not in [CTX] format, 1 malformed). Run with --include-all to see them.`

Requirements-understanding operations (sharpening a ticket, onboarding, decision
archaeology) read **leniently** — human discussion is exactly what's wanted there.

## The adoption incentive

Strict reading is a forcing function, not just efficiency: comments that don't follow the
format are excluded from state extraction, so people who want their updates to count adopt
the format. Write-side and read-side move together — agents writing via
`/bitacora:handoff` always emit compliant `[CTX]`, and readers skip non-compliant. Corpus
quality compounds.
