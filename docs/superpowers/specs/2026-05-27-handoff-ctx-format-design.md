# Phase 1 Design — `/handoff` + the `[CTX]` Comment Format

**Date:** 2026-05-27
**Status:** Approved design, ready for implementation planning
**Scope:** Bitácora Phase 1 only (per `PLUGIN_BRIEF.md` build order)

## Summary

Phase 1 delivers the foundation of Bitácora: the `/handoff` command and the
cross-cutting `[CTX]` Jira-comment format. `/handoff` is **multi-ticket aware** —
it reconstructs the set of tickets touched during the session, drafts a `[CTX]`
status comment for each, and at a single confirm gate writes the approved comments
plus **one consolidated** local session scratch persisted via the **Remember**
plugin. Everything composes on top of existing tools (Superpowers, Remember,
Atlassian Rovo MCP); Bitácora adds only the opinionated Jira-aware workflow layer.

The structural approach is **Approach A — thin command + shared skill**:

- `commands/handoff.md` is a prompt-only command that runs in the main session.
- The `[CTX]` format rules live in a reusable skill (`skills/jira-comment-format`),
  because later commands (`/status`, `/improve-ticket`, `/spike`) all consume the
  same spec.
- No subagent (handoff fundamentally needs the live session's context, which a
  fresh subagent can't see), no lifecycle hook (manual trigger only — auto-writing
  to Jira would violate the brief's draft→show→confirm→write rule), no
  `templates/` directory (delegating local capture to Remember removes the need
  for a handoff-file template in Phase 1).

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Delegate local capture to Remember** | Remember is installed and verified (`~/.claude/plugins/cache/claude-plugins-official/remember`); claude-mem is not present. Bitácora owns only the Jira `[CTX]` comment. No duplicated memory system, no Bitácora-owned state file, no own SessionStart hook. |
| D2 | **Required `[CTX]` sections: Header + `Status` + `Next`** | Lowest friction maximizes adoption, on which the whole shared-memory value depends. `Done`/`Decisions`/`Blockers`/`Open questions` are optional and appear only when non-empty. |
| D3 | **Adaptive Jira default** | If an active ticket is known, draft a `[CTX]` comment *and* save local scratch. If no ticket is detectable, do local-only with no Jira nag. Matches real flow: ticketed work gets logged, scratch work doesn't force a ticket. |
| D4 | **Approach A — thin command + shared skill, no subagent/hook/templates** | Smallest thing that works; puts the cross-cutting format where later phases reuse it; keeps handoff in the session where context lives. |
| D5 | **Local-first write order** | Remember scratch is the irreplaceable detail. If the Jira write fails afterward, the scratch is intact to retry from. If local failed after Jira succeeded, gritty mid-task detail would be lost. |
| D6 | **Malformed-`[CTX]` distinguished from non-`[CTX]`** | Remediation differs — "someone needs to learn the format" vs "this one comment needs a fix." Surfacing them separately is actionable; costs one extra counter. |
| D7 | **Full strict/lenient compliance table specified in the skill now** | The skill is the canonical cross-cutting spec; trimming it would leave Phase 1 structurally incomplete and force later phases to amend rather than consume. A Phase column labels what's exercised now vs forward-specified. |
| D8 | **Multi-ticket aware, reconstructed at handoff** | Real sessions touch multiple tickets across branch switches. `/handoff` reconstructs touched tickets from `git reflog` + session transcript + branch names at handoff time — no recorder hook, no Bitácora-owned state, preserving D1/D4. Attribution is best-effort (exact when the ticket is in a branch name); v1 shows everything and lets the user filter. Precise session-time attribution (recorder hook) and substantive-vs-incidental auto-classification are Phase 1.5. |

## File layout (Phase 1 deliverables)

```
.claude-plugin/
└── marketplace.json                         # marketplace entry
plugins/bitacora/
├── .claude-plugin/plugin.json               # plugin manifest
├── README.md                                # plugin-local readme
├── commands/handoff.md                      # the /handoff command (prompt-only)
├── skills/jira-comment-format/SKILL.md      # [CTX] format: write + read/compliance rules + golden examples
└── scripts/validate-ctx.sh                  # ~20-line spec-pinning validator (optional artifact, included)
docs/
└── JIRA_AGENT_COMMENT_FORMAT.md             # canonical human-facing spec + team-convention pitch
```

Plus a minor edit to `PLUGIN_BRIEF.md`: change "claude-mem (preferred) or Remember"
to reflect that **Remember is the installed/verified target** and claude-mem is not
present.

### Boundaries

- **Skill vs doc.** `SKILL.md` is the operational source of truth Claude loads —
  it holds the literal `[CTX]` formats and the write/read rules. `docs/JIRA_AGENT_COMMENT_FORMAT.md`
  is the human-facing canonical spec (README links to it; carries rationale and the
  team-adoption pitch). To avoid drift, the literal format templates live in **one**
  place — the skill — and the doc quotes them with a "source of truth: SKILL.md" note.
  **Drift risk:** the format appears in two files; the doc must defer to the skill.
- **No `agents/`, `hooks/`, or `templates/` in Phase 1.** They appear in later phases
  when earned.

## The `/handoff` flow

Runs entirely in the main session. **Multi-ticket aware** — sessions routinely touch
several tickets across branch switches.

1. **Gather touched tickets** as `(ticket → attributed-branch)` pairs (no hook; all
   reconstructed at handoff time):
   - Explicit args force a set — `/bit:handoff PROJ-1234 PROJ-5678`
   - Current branch parse — `project_key_pattern` match from `git branch --show-current`
   - **Branches visited this session** — `git reflog` checkout history
   - **Session transcript** — `project_key_pattern` mentions + Atlassian MCP reads/writes
   - **Attribution:** each touched ticket → the branch whose name encodes its key;
     otherwise → the branch active at mention time (best-effort, by transcript order) /
     "current".
   - **v1 is lenient — show everything touched, the user filters at the gate.**
     Substantive-vs-incidental auto-classification is Phase 1.5.
   - Zero tickets detected → **adaptive** local-only (no Jira nag).
2. **Per-ticket gather + draft.** Partition the session's work by ticket. For each, gather
   outcomes / decisions + rationale / next / blockers / team-PM-facing open questions, and
   draft a `[CTX]` comment per the skill format (`Header + Status + Next` required; optional
   sections only when non-empty). Outcome-oriented; no play-by-play, no code diffs (link the
   PR), no speculation.
3. **One consolidated local scratch** for the whole session (dead ends, fragile-code
   warnings, not-for-public scratch, next-session-you-only questions) — spanning all
   tickets, **not** per-ticket. This split between per-ticket Jira outcomes and one
   session-level scratch *is* the "two writes, don't collapse them" discipline at session
   scale.
4. **Multi-ticket confirm gate:**
   ```
   /bit:handoff — 3 tickets touched this session

   [1] PROJ-1234  (branch feature/PROJ-1234-oauth)        → [CTX] drafted
   [2] PROJ-5678  (branch fix/PROJ-5678-flaky-test)       → [CTX] drafted
   [3] PROJ-9999  (mentioned while on feature/PROJ-1234)  → [CTX] drafted
   + 1 consolidated local scratch capture (via Remember)

   Approve all · Review individually · Skip specific ("skip 3") · Cancel
   ```
   - **Approve all** → write everything.
   - **Review individually** → step through each draft; edit / approve / skip per ticket.
   - **Skip specific** → drop those, write the rest.
   - **Cancel** → nothing written.
5. **On confirm**, write **local-first** (see write sequence in Integration). Per-ticket
   failures are isolated.
6. **Report** a per-ticket result table (✓/✗ + comment link) plus the local-save
   confirmation, and note it's safe to `/clear`.

**Resume** is delegated entirely to Remember's existing `SessionStart` behavior;
Bitácora adds no hook in Phase 1. Implication: cross-machine/teammate resume in Phase 1
means manually reading the ticket's `[CTX]` comment; rich local resume is Remember's job.
A `/resume`-from-Jira read is a later phase.

### Open-questions placement

- Team/PM-facing → Jira `[CTX]`, optional `Open questions:` section (non-empty-only).
- Next-session-you only → Remember scratch.
- This "what goes where" rule lives in the skill so every command applies it identically.

## The `jira-comment-format` skill

The skill is the operational source of truth. It carries the canonical formats, the
write rules, the read/compliance rules, and golden examples that double as test fixtures.

### Canonical `[CTX]` status update

The only format Phase 1 *writes*. (The sharpen/spike variants are documented in the same
skill but exercised in later phases.)

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

Order shown is the recommended reading order; **compliance is order-independent** — it
checks for presence, not position.

### Write rules (hard)

- Outcome-oriented, not process. *What changed and why*, not *how I figured it out*.
- No verbose play-by-play; no code diffs (link the PR); no mid-task speculation (that's
  Remember scratch).
- One comment per logical update, not one per turn.

### Read-side compliance

- **Strict prefix match.** Implementation MUST use `trimmed_text.startswith("[CTX]")`,
  **not** substring containment. A comment that mentions `[CTX]` mid-sentence
  (`"as we noted in yesterday's [CTX]..."`) is *non-`[CTX]`* (free-form), never an
  attempt at compliance.
- **Compliant** = `[CTX]` header with a date + a `Status:` line + a `Next:` line.
  Optional sections never affect compliance.
- **Two failure classes, surfaced separately:**
  - *non-`[CTX]`* (free-form human comment) → skipped, counted as "not in format."
  - *malformed `[CTX]`* (starts with `[CTX]` but missing `Status`/`Next`) → skipped,
    counted **separately** as "malformed."
- **Skip behavior:** surface counts, never silently drop. Example:
  `Note: 4 comments excluded (3 not in [CTX] format, 1 malformed). Run with --include-all to see them.`

### Strict vs lenient by operation

Specified now as the cross-cutting spec; mostly exercised in later phases. The Phase
column labels current vs forward-specified.

| Operation | Mode | Phase |
|-----------|------|-------|
| `/status`, `/what-next`, cross-ticket JQL | strict | 3 / 5 / later |
| `/improve-ticket` source read, onboarding, decision archaeology | lenient | 2+ |
| **`/handoff` continuity read** (optional: read latest `[CTX]` to thread `Status`/`Next`, avoid restating `Done`) | **lenient** | **1** |

**Scope note:** Phase 1 ships and exercises the **write** path. The strict-read
machinery is defined and ready, but its first real consumer is `/status` in Phase 3.
The only read Phase 1 performs is `/handoff`'s optional lenient continuity-read, which
falls back gracefully if there's no prior `[CTX]`.

### Plugin compliance config

Lives in plugin settings; per-command override allowed.

```yaml
comment_compliance:
  status_extraction: strict          # /status, /what-next, JQL
  requirements_reading: lenient      # /improve-ticket, onboarding
  show_excluded_count: true
  partial_match: false               # strict prefix only
```

`project_key_pattern` is a **top-level** setting (not nested under `comment_compliance`),
because it is shared — ticket detection uses it for branch parse + transcript scan today,
and strict JQL queries will use it later:

```yaml
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"   # DEFAULT only — user-overridable
```

It is **user-configurable**; the baked value is only a default. Settings comments should
document common alternates so the override path is obvious:

- lowercase keys (`proj-1234`)
- alphanumeric suffixes (`PROJ-1234A`)
- longer/compound prefixes

### Session ticket tracking config

Separate block (handoff's multi-ticket gather is a gather/draft concern, not a
read-compliance one, so it does not belong under `comment_compliance`):

```yaml
session_ticket_tracking:
  enabled: true                 # multi-ticket handoff awareness
  source: reconstruct           # reconstruct | recorder  (recorder = Phase 1.5 hook)
  attribution: branch_name      # touched-ticket → branch mapping strategy
  # activity_threshold: <n>     # Phase 1.5 — substantive-vs-incidental auto-filter; v1 shows all
```

`source: reconstruct` is the only Phase 1 value. `recorder` (a passive hook + small owned
session log for exact attribution) and `activity_threshold` (auto-filtering incidental
touches) are forward-specified for Phase 1.5; v1 reconstructs and shows everything.

## Integration & error handling

### Atlassian MCP (Rovo) — capabilities → tools

| Need | Tool (confidence) |
|------|-------------------|
| Resolve site → `cloudId` | `getAccessibleAtlassianResources` (high) |
| Validate ticket; fetch summary/status for the gate | `getJiraIssue` (high) |
| Optional lenient continuity-read of prior `[CTX]` | issue-comments read — **exact tool name to verify against the installed Rovo MCP** |
| Write the `[CTX]` comment | `addCommentToJiraIssue` (high) |

**Pre-implementation step** (from the brief's "write against what's actually emitted"
rule): before finalizing `handoff.md`, confirm the comment-read tool name/signature
against the installed Rovo MCP. Multiple sites → ask, or use `jira_cloud_id` from
settings if set.

### Remember

Invoke the `remember:remember` skill with the scratch payload. Resume is Remember's
`SessionStart` job — Bitácora doesn't touch it.

### Confirm-gate write sequence (local-first, multi-ticket)

1. User approves at the gate (all / individually / skip-specific).
2. **Write the one consolidated scratch via Remember first.** Success → continue. Fail →
   warn, **print the scratch to screen** for manual save, ask whether to still attempt the
   Jira writes.
3. **Write each approved ticket's `[CTX]` via MCP.** Per-ticket failures are **isolated** —
   one ticket's 404 / permission error does not abort the others. Collect per-ticket
   results.
4. Final report: a per-ticket ✓/✗ table (with comment links for successes and reasons for
   failures) + the scratch result + "safe to `/clear`." Offer retry for any failed tickets;
   the scratch is already safe regardless.

### Edge-case matrix

| Situation | Behavior |
|-----------|----------|
| MCP absent / auth fail / site unresolvable | Skip Jira (= no-ticket path). Complete local. Report reason. **No retry loop.** |
| Ticket 404 / no write permission | Surface error, keep draft, offer retry w/ different key or skip Jira. No crash. |
| No ticket detectable | Adaptive local-only; gate covers local save; no Jira nag. |
| Empty/trivial session | "Nothing substantive to hand off" — write nothing. Offer override if user insists. |
| Remember unavailable | Warn; print scratch for manual save; still offer Jira write. |
| Decline at gate (Cancel) | Nothing written; offer to keep editing. |
| Skip specific tickets at gate | Drop the skipped drafts, write the rest + scratch. |
| One ticket fails mid-batch (404 / permission) | Isolated — other tickets and the scratch still write; report ✗ for that one, offer retry. |
| Multiple tickets map to one branch (two keys, or two tickets worked there) | Show all as separate touched tickets (lenient v1) — no forced pick. |
| Ticket touched but not in any branch name | Shown attributed to "current / mentioned"; user filters (lenient v1). |
| Edit at gate | Re-render, re-confirm before writing. |

Re-running `/handoff` in one session writes a new `[CTX]` per ticket (one-per-logical-update
is fine); the continuity-read avoids restating `Done`. No dedup needed for Phase 1.

## Testing & acceptance

Prompt/command plugins aren't classically unit-testable — runtime classification is the
*model's*, not code's. Strategy, in Superpowers' test-first spirit: **author fixtures +
acceptance scenarios before writing the command/skill prose, then iterate the prose until
they pass.**

### 1. Format-conformance fixtures

The three golden examples in the skill:

- compliant status update → classified *compliant*
- free-form human comment mentioning `[CTX]` mid-sentence → *not in format*
- `[CTX]` header, `Next:` missing → *malformed* (the real-world "forgot to update
  next-step before sending" case)

Assert correct classification **and** correct skip-count phrasing
(`3 not in [CTX] format, 1 malformed`).

### 2. `validate-ctx.sh` (included)

A ~20-line script encoding the exact rule (`startswith("[CTX]")` + presence of
`Status:`/`Next:`). It tests *the spec*, not the plugin's runtime behavior, but pins the
rule unambiguously and is CI-ready for later phases. Runs against the three golden
fixtures as ground-truth oracle.

### 3. Manual acceptance scenarios (the real validation)

| # | Scenario | Pass condition |
|---|----------|----------------|
| A1 | Brief's canonical: ticket-named branch → `/handoff` → approve → exit → fresh session | Remember resumes scratch, restatement correct; ticket has clean `[CTX]` |
| A2 | No detectable ticket | Local-only consolidated scratch, no Jira nag |
| A3 | Explicit args present (`/bit:handoff PROJ-1 PROJ-2`) | Forces exactly that ticket set |
| A4 | MCP unavailable | Graceful skip, local completes, reason reported |
| A5 | Bad ticket key | Error surfaced for that ticket, others unaffected, no crash |
| A6 | Prior `[CTX]` malformed on ticket | Lenient continuity-read still produces sensible draft |
| A7 | Cancel at gate | Nothing written |
| A8 | Remember write fails | Scratch printed, Jira writes still offered |
| A9 | **Multi-ticket**: work on PROJ-1 (branch A), switch to PROJ-2 (branch B), mention PROJ-3 → `/handoff` | All three reconstructed and attributed (1→A, 2→B, 3→current); per-ticket `[CTX]` drafted; one consolidated scratch |
| A10 | **Skip-specific + isolation**: 3 tickets, skip [3], and [2] 404s on write | [1] writes ✓, [2] reports ✗ with retry offer, [3] dropped; scratch writes ✓ regardless |

## Out of scope for Phase 1

- All other commands (`/improve-ticket`, `/status`, `/spike`, `/what-next`) — later phases.
- statusLine — Phase 6.
- A Bitácora-owned SessionStart hook / `/resume`-from-Jira — resume is Remember's job in Phase 1.
- Subagents, `templates/` directory, lifecycle hooks.
- GitHub Issues as a Jira alternative.
- Team distribution.

**Deferred to Phase 1.5:**

- Precise session-time branch attribution via a passive recorder hook + owned session log
  (`session_ticket_tracking.source: recorder`). v1 reconstructs at handoff, best-effort.
- Substantive-vs-incidental touched-ticket auto-classification (`activity_threshold`). v1
  shows everything and lets the user filter at the gate.

## Open items to confirm during implementation

- Exact Atlassian Rovo MCP tool name/signature for reading issue comments (continuity-read).
- `cloudId` resolution UX when multiple Atlassian sites are accessible (ask vs `jira_cloud_id` setting).
- Where plugin settings live and how `project_key_pattern` / `comment_compliance` are read
  by a prompt-based command (settings file location and read mechanism).

## Addendum — decisions made during planning (2026-05-27)

- **Plugin name `bitacora`** → canonical command `/bitacora:handoff` (command namespace
  equals plugin name). An **opt-in `/bit:` alias** is shipped as a copy-paste file
  (`plugins/bitacora/alias/bit-handoff.md`) the user drops into
  `~/.claude/commands/bit/handoff.md`; it invokes the same skill. No second plugin.
- **Handoff workflow lives in a `session-handoff` skill** (renamed from `handoff` to
  avoid colliding with the `handoff` command's qualified name `bitacora:handoff`), with
  `commands/handoff.md` a thin
  trigger. This refines the spec's "workflow in the command" to keep the command thin and
  let the `/bit:` alias reuse identical logic with zero duplication. Still Approach A (thin
  command + shared skills), still no subagent/hook.
- **Continuity-read uses `getJiraIssue`** (with comments), resolving the spec's open item
  about a separate comments-read tool.
- **Settings overrides** read from `${CLAUDE_PROJECT_DIR}/.bitacora.yml` then
  `~/.claude/bitacora.yml`; absent → documented defaults (resolves the settings-location
  open item).
- **`validate-ctx.sh` does not machine-enforce the header date** (documented convention
  only), keeping three clean classes that match the three golden fixtures.
