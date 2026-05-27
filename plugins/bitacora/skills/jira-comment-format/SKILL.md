---
name: jira-comment-format
description: The [CTX] Jira-comment format — how to WRITE compliant agent comments and how to READ them under strict/lenient compliance. Use whenever drafting a Jira comment or extracting state from ticket comments (handoff, status, ranking).
allowed-tools: Read
---

This skill is the single source of truth for the `[CTX]` comment format. The
human-facing companion `docs/JIRA_AGENT_COMMENT_FORMAT.md` defers to this file.

## Canonical `[CTX]` status update

Required = the header line (with a date) + a `Status:` line + a `Next:` line.
`Done`/`Decisions`/`Blockers`/`Open questions` are optional and appear only when
non-empty. Order below is recommended; compliance is order-independent.

```
[CTX] Status update — <YYYY-MM-DD>     ← REQUIRED: header line w/ date

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

See `examples/compliant.txt` for a full compliant example.

The header **date** is a write-side convention — always include it — but it is *not* machine-enforced: the validator checks only the `[CTX]` prefix and the presence of
`Status:` and `Next:` lines.

## Write rules (hard)

- Outcome-oriented, not process. *What changed and why*, not *how I figured it out*.
- No verbose play-by-play; no code diffs (link the PR instead); no mid-task
  speculation (that belongs in local Remember scratch).
- One comment per logical update, not one per turn.
- **Open questions placement:** team/PM-facing questions go in the `Open questions:`
  section of the `[CTX]` comment; next-session-only questions go to Remember scratch.

## Read-side compliance

- **Strict prefix match.** Use `trimmed_text.startswith("[CTX]")`, NOT substring
  containment. A comment that mentions `[CTX]` mid-sentence (e.g. `"as we noted in
  yesterday's [CTX]..."`) is *non-`[CTX]`* — never an attempt at compliance. See
  `examples/non-ctx.txt`.
- **Compliant** = starts with `[CTX]` header + has a `Status:` line + a `Next:` line.
  Optional sections never affect compliance.
- **Two failure classes, surfaced separately:**
  - *non-`[CTX]`* (free-form human comment) → skip, count as "not in format".
  - *malformed `[CTX]`* (starts with `[CTX]` but missing `Status`/`Next`) → skip,
    count **separately** as "malformed". See `examples/malformed.txt` (which shows the
    `Next:`-absent case; the `Status:`-absent case is symmetric).
- **Never silently drop.** Surface counts, e.g.:
  `Note: 4 comments excluded (3 not in [CTX] format, 1 malformed). Run with --include-all to see them.`

The script `../../scripts/validate-ctx.sh` (i.e. `plugins/bitacora/scripts/validate-ctx.sh`
from the repo root) encodes this exact rule and can classify any single comment
(`compliant` / `malformed` / `not-in-format`).

## Strict vs lenient by operation

| Operation | Mode | Phase |
|-----------|------|-------|
| `/status`, `/what-next`, cross-ticket JQL | strict | 3 / 5 / later |
| `/improve-ticket` source read, onboarding, decision archaeology | lenient | 2+ |
| `/bitacora:handoff` continuity read (read latest `[CTX]` to thread `Status`/`Next`, avoid restating `Done`) | lenient | 1 |

- **strict** = count a comment only if it is *compliant* (starts with `[CTX]` and has
  `Status:` + `Next:`); skip non-`[CTX]` and malformed comments, tallying them separately.
- **lenient** = read every comment regardless of prefix or sections — human discussion is
  exactly what's wanted there; do not skip non-compliant comments.

Phase 1 ships and exercises the **write** path. The strict-read machinery is defined
here for later consumers; the only read Phase 1 performs is handoff's lenient
continuity-read, which falls back gracefully when there is no prior `[CTX]`.

## Configuration

Defaults (used inline unless overridden):

```yaml
comment_compliance:
  status_extraction: strict          # /status, /what-next, JQL
  requirements_reading: lenient      # /improve-ticket, onboarding
  show_excluded_count: true
  partial_match: false               # strict prefix only
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"   # top-level; shared by detection + JQL. DEFAULT only.
```

`project_key_pattern` is user-overridable; common alternates: lowercase keys
(`proj-1234`), alphanumeric suffixes (`PROJ-1234A`), longer/compound prefixes.

**Overrides:** if present, read `${CLAUDE_PROJECT_DIR}/.bitacora.yml`, else
`~/.claude/bitacora.yml`. Absence is normal — fall back to the defaults above silently.
