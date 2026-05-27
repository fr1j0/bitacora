# Bitácora Phase 1 — `/handoff` + `[CTX]` Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Bitácora Phase 1 — a multi-ticket-aware `/bitacora:handoff` command and the cross-cutting `[CTX]` Jira-comment format — composing on top of Remember and the Atlassian Rovo MCP.

**Architecture:** A Claude Code plugin (`bitacora`) whose handoff *workflow* lives in a `handoff` skill (thin `commands/handoff.md` trigger invokes it, and an opt-in `/bit:` alias reuses the same skill). The `[CTX]` format — write rules, strict/lenient read-compliance rules, and golden examples — lives in a separate `jira-comment-format` skill that is the single source of truth. Local session scratch is delegated to the installed `remember` skill (which writes one consolidated note to `.remember/remember.md`); Jira `[CTX]` comments are written via the Atlassian Rovo MCP. A small `validate-ctx.sh` script pins the compliance rule and is the one automated test.

**Tech Stack:** Markdown command/skill files + JSON manifests (Claude Code plugin format), Bash (git reconstruction + `validate-ctx.sh`), Atlassian Rovo MCP (`getAccessibleAtlassianResources`, `getJiraIssue`, `addCommentToJiraIssue`), the `remember` plugin skill, `jq` for manifest validation.

**Branch:** `phase-1-handoff` (already created; the spec is committed there).

---

## Conventions verified against the installed environment

- **Command namespace = plugin name.** `plugin.json` `"name": "bitacora"` → commands invoke as `/bitacora:handoff`. Subdirectories under `commands/` do **not** namespace. (Verified via claude-code-guide + docs.)
- **Arguments** reach a command through the `$ARGUMENTS` token (the whole raw string; not `$1`/`$2`). Jira keys are parsed from it.
- **Skill frontmatter** uses `name`, `description`, optional `allowed-tools` (observed in the installed `remember` skill).
- **Remember** writes one consolidated handoff note to `{project_root}/.remember/remember.md`, overwriting (read-first if it exists). This matches "one consolidated scratch per session."
- **Atlassian Rovo MCP** exposes `getAccessibleAtlassianResources` (→ `cloudId`), `getJiraIssue` (issue + comments via expansion — used for both validation and the continuity-read), and `addCommentToJiraIssue` (write). These resolve the spec's open items; the continuity-read uses `getJiraIssue`, not a separate comments tool.
- **Author/license:** the repo `LICENSE` is MIT-style with copyright "Bitácora contributors" → manifests use `"name": "Bitácora contributors"` and `"license": "MIT"`.

## File structure

```
.claude-plugin/
└── marketplace.json                                   # CREATE — marketplace entry (Task 1)
plugins/bitacora/
├── .claude-plugin/plugin.json                         # CREATE — plugin manifest, name "bitacora" (Task 1)
├── README.md                                          # CREATE — plugin readme + /bit: alias how-to (Task 7)
├── commands/handoff.md                                # CREATE — thin trigger → handoff skill (Task 6)
├── skills/
│   ├── handoff/SKILL.md                               # CREATE — the handoff workflow (Task 5)
│   └── jira-comment-format/
│       ├── SKILL.md                                   # CREATE — [CTX] format source of truth (Task 4)
│       └── examples/
│           ├── compliant.txt                          # CREATE — golden fixture (Task 2)
│           ├── malformed.txt                          # CREATE — golden fixture (Task 2)
│           └── non-ctx.txt                            # CREATE — golden fixture (Task 2)
├── scripts/
│   ├── validate-ctx.sh                                # CREATE — compliance validator (Task 3)
│   └── test-validate-ctx.sh                           # CREATE — fixture test (Task 3)
└── alias/bit-handoff.md                               # CREATE — copy-paste /bit: alias (Task 7)
docs/
├── JIRA_AGENT_COMMENT_FORMAT.md                       # CREATE — human-facing canonical spec (Task 8)
└── superpowers/
    ├── specs/2026-05-27-handoff-ctx-format-design.md  # MODIFY — addendum (Task 9)
    └── checklists/MANUAL-ACCEPTANCE.md                # CREATE — A1–A10 dogfooding checklist (Task 10)
PLUGIN_BRIEF.md                                        # MODIFY — claude-mem → Remember reality (Task 9)
```

**Settings resolution (resolves a spec open item):** the skills use the documented defaults inline (`project_key_pattern: "[A-Z][A-Z0-9]+-\d+"`, `status_extraction: strict`, `requirements_reading: lenient`, `show_excluded_count: true`, `session_ticket_tracking.source: reconstruct`). For overrides, a skill reads an optional YAML file if present, checking `${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is normal and silent.

---

### Task 1: Plugin manifests

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/bitacora/.claude-plugin/plugin.json`

- [ ] **Step 1: Confirm the working branch**

Run: `git branch --show-current`
Expected: `phase-1-handoff`. If not, run `git checkout phase-1-handoff`.

- [ ] **Step 2: Create the marketplace manifest**

Create `.claude-plugin/marketplace.json`:

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "bitacora",
  "description": "Bitácora — Jira-aware workflow layer for Claude Code. Every bit of context, logged.",
  "owner": {
    "name": "Bitácora contributors"
  },
  "plugins": [
    {
      "name": "bitacora",
      "description": "Clean session handoffs and the [CTX] Jira-comment-format discipline. Layers on Superpowers, Remember, and the Atlassian Rovo MCP.",
      "version": "0.1.0",
      "source": "./plugins/bitacora",
      "author": {
        "name": "Bitácora contributors"
      },
      "license": "MIT",
      "keywords": ["jira", "workflow", "handoff", "context", "memory"]
    }
  ]
}
```

- [ ] **Step 3: Create the plugin manifest**

Create `plugins/bitacora/.claude-plugin/plugin.json`:

```json
{
  "name": "bitacora",
  "description": "Jira-aware workflow layer for Claude Code: clean session handoffs and the [CTX] comment-format discipline.",
  "version": "0.1.0",
  "author": {
    "name": "Bitácora contributors"
  },
  "license": "MIT",
  "keywords": ["jira", "workflow", "handoff", "context", "memory"]
}
```

- [ ] **Step 4: Validate both manifests are well-formed JSON with the expected name**

Run:
```bash
jq -e '.name == "bitacora" and (.plugins | length) == 1 and .plugins[0].source == "./plugins/bitacora"' .claude-plugin/marketplace.json \
  && jq -e '.name == "bitacora" and .version == "0.1.0"' plugins/bitacora/.claude-plugin/plugin.json
```
Expected: prints `true` then `true`, exit 0. (A syntax error makes `jq` exit non-zero.)

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/bitacora/.claude-plugin/plugin.json
git commit -m "feat: add bitacora plugin + marketplace manifests"
```

---

### Task 2: Golden `[CTX]` fixtures

These three files are simultaneously the skill's documentation examples and the validator's test fixtures (one home, per the spec).

**Files:**
- Create: `plugins/bitacora/skills/jira-comment-format/examples/compliant.txt`
- Create: `plugins/bitacora/skills/jira-comment-format/examples/malformed.txt`
- Create: `plugins/bitacora/skills/jira-comment-format/examples/non-ctx.txt`

- [ ] **Step 1: Create the compliant fixture**

Create `plugins/bitacora/skills/jira-comment-format/examples/compliant.txt`:

```
[CTX] Status update — 2026-05-27

Status: In Progress
Done:
  - OAuth provider client implemented and tested
Decisions:
  - PKCE flow over implicit — more secure for SPAs
Next:
  - Token refresh implementation
Blockers:
  None
```

- [ ] **Step 2: Create the malformed fixture (`[CTX]` header present, `Next:` missing)**

Create `plugins/bitacora/skills/jira-comment-format/examples/malformed.txt`:

```
[CTX] Status update — 2026-05-27

Status: In Progress
Done:
  - OAuth provider client implemented and tested
```

- [ ] **Step 3: Create the non-`[CTX]` fixture (mentions `[CTX]` mid-sentence)**

Create `plugins/bitacora/skills/jira-comment-format/examples/non-ctx.txt`:

```
Thanks for this! As we noted in yesterday's [CTX] update, the token
refresh still needs the concurrent-refresh edge case handled. I'll
pair with Sarah on it tomorrow morning.
```

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/examples/
git commit -m "test: add golden [CTX] fixtures (compliant, malformed, non-ctx)"
```

---

### Task 3: `validate-ctx.sh` compliance validator (TDD)

The validator classifies a comment into exactly `compliant` / `malformed` / `not-in-format` and is the one automated test of the compliance rule. **It enforces: trimmed text starts with `[CTX]` (startswith, not substring), and `compliant` requires both a `Status:` line and a `Next:` line.** The header date is a documented convention but is intentionally **not** machine-enforced in v1 (keeps three clean classes matching the three fixtures).

**Files:**
- Create: `plugins/bitacora/scripts/test-validate-ctx.sh`
- Create: `plugins/bitacora/scripts/validate-ctx.sh`

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-validate-ctx.sh`:

```bash
#!/usr/bin/env bash
# Asserts validate-ctx.sh classifies the three golden fixtures correctly.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$DIR/validate-ctx.sh"
FIXTURES="$DIR/../skills/jira-comment-format/examples"

fail=0
check() {
  # NOTE: the script uses `set -uo pipefail` (no `-e`), so a non-zero exit from
  # the validator does not abort — do NOT add `set -e` here; in bash it leaks out
  # of the function and aborts the later pipeline assertion.
  local file="$1" expected_word="$2" expected_code="$3" out code
  out="$("$VALIDATOR" "$file")"
  code=$?
  if [[ "$out" == "$expected_word" && "$code" == "$expected_code" ]]; then
    echo "PASS: $(basename "$file") → $out ($code)"
  else
    echo "FAIL: $(basename "$file") → got '$out' ($code), expected '$expected_word' ($expected_code)"
    fail=1
  fi
}

check "$FIXTURES/compliant.txt" compliant     0
check "$FIXTURES/malformed.txt" malformed     1
check "$FIXTURES/non-ctx.txt"   not-in-format 2

# startswith, not substring: a comment mentioning [CTX] mid-line is NOT compliant
printf 'see the [CTX] note\nStatus: x\nNext: y\n' | "$VALIDATOR" >/tmp/bita_ss.out 2>&1; ss_code=$?
if [[ "$(cat /tmp/bita_ss.out)" == "not-in-format" && "$ss_code" == "2" ]]; then
  echo "PASS: mid-line [CTX] mention → not-in-format (2)"
else
  echo "FAIL: mid-line [CTX] mention → got '$(cat /tmp/bita_ss.out)' ($ss_code)"
  fail=1
fi

exit $fail
```

- [ ] **Step 2: Make the test executable and run it to verify it fails**

Run:
```bash
chmod +x plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-validate-ctx.sh
```
Expected: FAIL — the validator does not exist yet (errors like `validate-ctx.sh: No such file or directory`), exit non-zero.

- [ ] **Step 3: Write the validator**

Create `plugins/bitacora/scripts/validate-ctx.sh`:

```bash
#!/usr/bin/env bash
# validate-ctx.sh — classify a Jira comment against the [CTX] format spec.
#
# Usage:  validate-ctx.sh [FILE]    (reads stdin if FILE is omitted)
# Output: one of  compliant | malformed | not-in-format   (stdout)
# Exit:   0 compliant | 1 malformed | 2 not-in-format
#
# Rule (v1):
#   - Trimmed text MUST START WITH "[CTX]" (startswith, NOT substring) else not-in-format.
#   - compliant requires a "Status:" line AND a "Next:" line.
#   - Starts with "[CTX]" but missing Status/Next → malformed.
# NOTE: the header date is a documented convention, NOT machine-enforced in v1.
set -euo pipefail

input="$(cat "${1:-/dev/stdin}")"

# Strip leading whitespace (including newlines) for the startswith check.
trimmed="${input#"${input%%[![:space:]]*}"}"

# Quoted "[CTX]" makes the brackets literal in the case glob.
case "$trimmed" in
  '[CTX]'*) : ;;                       # starts with [CTX] — continue checks
  *) echo "not-in-format"; exit 2 ;;
esac

has_status=false
has_next=false
while IFS= read -r line; do
  case "$line" in
    "Status:"*) has_status=true ;;
    "Next:"*)   has_next=true ;;
  esac
done <<< "$input"

if $has_status && $has_next; then
  echo "compliant"; exit 0
else
  echo "malformed"; exit 1
fi
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run:
```bash
chmod +x plugins/bitacora/scripts/validate-ctx.sh
plugins/bitacora/scripts/test-validate-ctx.sh
```
Expected: four `PASS:` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/scripts/validate-ctx.sh plugins/bitacora/scripts/test-validate-ctx.sh
git commit -m "feat: add validate-ctx.sh compliance validator + passing fixture test"
```

---

### Task 4: `jira-comment-format` skill (source of truth)

**Files:**
- Create: `plugins/bitacora/skills/jira-comment-format/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `plugins/bitacora/skills/jira-comment-format/SKILL.md`:

````markdown
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
    count **separately** as "malformed". See `examples/malformed.txt`.
- **Never silently drop.** Surface counts, e.g.:
  `Note: 4 comments excluded (3 not in [CTX] format, 1 malformed). Run with --include-all to see them.`

The script `../../scripts/validate-ctx.sh` encodes this exact rule and can classify
any single comment (`compliant` / `malformed` / `not-in-format`).

## Strict vs lenient by operation

| Operation | Mode | Phase |
|-----------|------|-------|
| `/status`, `/what-next`, cross-ticket JQL | strict | 3 / 5 / later |
| `/improve-ticket` source read, onboarding, decision archaeology | lenient | 2+ |
| `/bitacora:handoff` continuity read (read latest `[CTX]` to thread `Status`/`Next`, avoid restating `Done`) | lenient | 1 |

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
````

- [ ] **Step 2: Verify frontmatter and example references resolve**

Run:
```bash
head -5 plugins/bitacora/skills/jira-comment-format/SKILL.md | grep -q "^name: jira-comment-format" \
  && grep -q "examples/compliant.txt" plugins/bitacora/skills/jira-comment-format/SKILL.md \
  && test -f plugins/bitacora/skills/jira-comment-format/examples/non-ctx.txt \
  && echo OK
```
Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/SKILL.md
git commit -m "feat: add jira-comment-format skill (the [CTX] source of truth)"
```

---

### Task 5: `handoff` skill (the workflow)

**Files:**
- Create: `plugins/bitacora/skills/handoff/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `plugins/bitacora/skills/handoff/SKILL.md`:

````markdown
---
name: handoff
description: Run the Bitácora session handoff — reconstruct the Jira tickets touched this session, draft a [CTX] status comment for each (confirm before writing), write them via the Atlassian MCP, and save one consolidated local scratch via Remember. Use when the user runs /bitacora:handoff or /bit:handoff.
---

Wrap up the current session cleanly. You are in the live session — use what you
actually did this session. Follow the `bitacora:jira-comment-format` skill for the
`[CTX]` format and the outcome-vs-scratch split.

Optional explicit ticket set: any Jira-style keys the invoking command passed
through (parse them with `project_key_pattern`). If present, they force the
touched-ticket set and you skip reconstruction.

## 1. Gather the tickets touched this session (reconstruct — no hook/state)

Build a list of `(ticket → attributed-branch)` pairs from:

- **Explicit keys** passed by the command (force the set if any).
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Branches visited this session:** `git reflog --date=iso | grep -i checkout` —
  extract key matches from branch names.
- **Session transcript:** ticket keys you read/wrote via the Atlassian MCP or that were
  mentioned (match `project_key_pattern`).

**Attribution:** each touched ticket → the branch whose name encodes its key; otherwise
→ the branch active when it was mentioned (best-effort, by transcript order), labelled
"current/mentioned". Multiple tickets mapping to one branch are all shown as separate
touched tickets — never force a pick.

**v1 is lenient: show everything touched and let the user filter at the gate.** Do not
auto-discard "incidental" touches (that is a Phase 1.5 refinement).

If zero tickets are detected, go **local-only** (adaptive): skip all Jira steps, no nag.

## 2. Draft a `[CTX]` per ticket

Partition the session's work by ticket. For each, gather outcomes / decisions +
rationale / next / blockers / team-PM-facing open questions, and draft a `[CTX]` status
comment per the `jira-comment-format` skill (`Header + Status + Next` required; optional
sections only when non-empty). Outcome-oriented; no play-by-play, no code diffs (link the
PR), no speculation.

**Optional continuity-read (lenient):** before drafting, you may read the latest `[CTX]`
on the ticket via `getJiraIssue` (request the comments) to thread `Status`/`Next` and
avoid restating `Done`. Fall back gracefully if there is no prior `[CTX]` or the read
fails.

## 3. Prepare ONE consolidated local scratch

Across all tickets, collect the session-level scratch: dead ends, fragile-code warnings,
not-for-public notes, and next-session-you-only questions. This is one capture for the
whole session, not per-ticket.

## 4. Confirm gate (multi-ticket)

Show all drafts and the scratch summary, then offer the choices:

```
/bitacora:handoff — N tickets touched this session

[1] PROJ-1234  (branch feature/PROJ-1234-oauth)        → [CTX] drafted
[2] PROJ-5678  (branch fix/PROJ-5678-flaky-test)       → [CTX] drafted
[3] PROJ-9999  (mentioned while on feature/PROJ-1234)  → [CTX] drafted
+ 1 consolidated local scratch capture (via Remember)

Approve all · Review individually · Skip specific ("skip 3") · Cancel
```

- **Approve all** → write everything.
- **Review individually** → step through each draft; edit / approve / skip per ticket.
- **Skip specific** → drop those, write the rest.
- **Cancel** → write nothing; offer to keep editing.

Never write to Jira before this gate.

## 5. Write — LOCAL FIRST

1. **Save the consolidated scratch via Remember:** invoke the `remember:remember` skill,
   passing the scratch content prepared in step 3. If it fails, warn, **print the scratch
   to screen** for manual save, and ask whether to still attempt the Jira writes.
2. **Resolve the Atlassian site:** `getAccessibleAtlassianResources` → `cloudId`. If
   multiple sites, ask which (or use a `jira_cloud_id` override if configured).
3. **Write each approved ticket's `[CTX]`** via `addCommentToJiraIssue`. **Per-ticket
   failures are isolated** — one ticket's 404 / permission error does not abort the
   others.

## 6. Report

Print a per-ticket ✓/✗ table (comment links for successes, reasons for failures) + the
scratch result, offer retry for any failed tickets (the scratch is already safe), and
note it's safe to `/clear`.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** treat exactly like the
  no-ticket path — skip the Jira half gracefully, complete the local scratch, report the
  reason. **No retry loop.**
- **Ticket 404 / no write permission:** surface for that ticket, keep its draft, offer
  retry with a different key or skip; other tickets unaffected.
- **Empty/trivial session:** say "nothing substantive to hand off" and write nothing
  unless the user insists.
- **Remember unavailable:** warn, print the scratch for manual save, still offer the Jira
  writes.
- Re-running in one session writes a new `[CTX]` per ticket (one per logical update is
  fine); the continuity-read avoids restating `Done`.

Configuration (`project_key_pattern`, compliance modes, `session_ticket_tracking`)
follows the `jira-comment-format` skill's Configuration section.
````

- [ ] **Step 2: Verify frontmatter and key workflow anchors are present**

Run:
```bash
head -5 plugins/bitacora/skills/handoff/SKILL.md | grep -q "^name: handoff" \
  && grep -q "remember:remember" plugins/bitacora/skills/handoff/SKILL.md \
  && grep -q "addCommentToJiraIssue" plugins/bitacora/skills/handoff/SKILL.md \
  && grep -q "LOCAL FIRST" plugins/bitacora/skills/handoff/SKILL.md \
  && echo OK
```
Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/handoff/SKILL.md
git commit -m "feat: add handoff skill (multi-ticket reconstruct, local-first write)"
```

---

### Task 6: `handoff` command (thin trigger)

**Files:**
- Create: `plugins/bitacora/commands/handoff.md`

- [ ] **Step 1: Write the command**

Create `plugins/bitacora/commands/handoff.md`:

```markdown
---
description: Wrap up a session — reconstruct the Jira tickets touched, draft a [CTX] status comment for each (confirm before writing), and save consolidated local scratch via Remember.
---

Use the `bitacora:handoff` skill to run the session handoff workflow.

Any Jira-style ticket keys in the arguments below force the touched-ticket set;
otherwise reconstruct the touched tickets from git history and the session.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Verify frontmatter and `$ARGUMENTS` token**

Run:
```bash
head -3 plugins/bitacora/commands/handoff.md | grep -q "^description:" \
  && grep -q 'bitacora:handoff' plugins/bitacora/commands/handoff.md \
  && grep -q '\$ARGUMENTS' plugins/bitacora/commands/handoff.md \
  && echo OK
```
Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/commands/handoff.md
git commit -m "feat: add /bitacora:handoff command (thin trigger to handoff skill)"
```

---

### Task 7: `bit:` alias file + plugin README

**Files:**
- Create: `plugins/bitacora/alias/bit-handoff.md`
- Create: `plugins/bitacora/README.md`

- [ ] **Step 1: Create the opt-in `bit:` alias file**

Create `plugins/bitacora/alias/bit-handoff.md` (this is NOT auto-loaded; the user copies
it to their personal commands dir to get the `/bit:` namespace):

```markdown
---
description: (alias of /bitacora:handoff) Wrap up a session via Bitácora.
---

Use the `bitacora:handoff` skill to run the session handoff workflow.

Any Jira-style ticket keys in the arguments below force the touched-ticket set;
otherwise reconstruct the touched tickets from git history and the session.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Create the plugin README**

Create `plugins/bitacora/README.md`:

````markdown
# Bitácora (plugin)

Jira-aware workflow layer for Claude Code. **Phase 1:** `/bitacora:handoff` and the
`[CTX]` comment-format discipline. Every bit of context, logged.

## Requirements

- **Remember** plugin (local session memory) — handoff delegates the local scratch to it.
- **Atlassian Rovo MCP** configured with read/write to your Jira — for `[CTX]` comments.

## Commands

| Command | What it does |
|---------|--------------|
| `/bitacora:handoff [KEYS...]` | Reconstruct the Jira tickets touched this session, draft a `[CTX]` status comment for each (confirm before writing), and save one consolidated local scratch via Remember. Pass ticket keys to force the set. |

## Optional: the shorter `/bit:` alias

Command namespace equals the plugin name, so commands are `/bitacora:…` by default.
For a shorter `/bit:handoff`, copy the bundled alias into your personal commands dir
(one-time, per machine):

```bash
mkdir -p ~/.claude/commands/bit
cp "$(dirname "$(find ~/.claude/plugins -path '*bitacora/alias/bit-handoff.md' | head -1)")/bit-handoff.md" \
   ~/.claude/commands/bit/handoff.md
```

Then `/bit:handoff` and `/bitacora:handoff` both run the same workflow.

## The `[CTX]` format

See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](../../docs/JIRA_AGENT_COMMENT_FORMAT.md). The
operational source of truth is the `jira-comment-format` skill; `scripts/validate-ctx.sh`
classifies any comment as `compliant` / `malformed` / `not-in-format`.

## Safety

Draft → show → confirm → write, always. No auto-update, no telemetry. Local scratch is
written first so Jira-write failures never lose mid-task detail.
````

- [ ] **Step 3: Verify both files**

Run:
```bash
grep -q 'bitacora:handoff' plugins/bitacora/alias/bit-handoff.md \
  && grep -q '\$ARGUMENTS' plugins/bitacora/alias/bit-handoff.md \
  && grep -q '/bit:handoff' plugins/bitacora/README.md \
  && echo OK
```
Expected: prints `OK`.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/alias/bit-handoff.md plugins/bitacora/README.md
git commit -m "feat: add opt-in /bit: alias + plugin README"
```

---

### Task 8: `docs/JIRA_AGENT_COMMENT_FORMAT.md` (human-facing canonical spec)

The top-level `README.md` already links to this path. It carries the rationale and the
team-adoption pitch, and defers to the skill for the literal format.

**Files:**
- Create: `docs/JIRA_AGENT_COMMENT_FORMAT.md`

- [ ] **Step 1: Write the document**

Create `docs/JIRA_AGENT_COMMENT_FORMAT.md`:

````markdown
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
Required = the header line (with a date) + a `Status:` line + a `Next:` line; everything
else is optional and appears only when non-empty.

```
[CTX] Status update — 2026-05-27

Status: In Progress
Done:
  - OAuth provider client implemented and tested
Decisions:
  - PKCE flow over implicit — more secure for SPAs
Next:
  - Token refresh implementation
Blockers:
  None
```

- **Outcome-oriented**, not process. *What changed and why*, not *how I figured it out*.
- No code diffs (link the PR). No mid-task speculation (that's local scratch).
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
````

- [ ] **Step 2: Verify the doc defers to the skill and shows the format**

Run:
```bash
grep -q "Source of truth" docs/JIRA_AGENT_COMMENT_FORMAT.md \
  && grep -q "\[CTX\] Status update" docs/JIRA_AGENT_COMMENT_FORMAT.md \
  && echo OK
```
Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add docs/JIRA_AGENT_COMMENT_FORMAT.md
git commit -m "docs: add canonical [CTX] format spec (defers to skill)"
```

---

### Task 9: Align existing docs (brief reality + spec addendum)

**Files:**
- Modify: `PLUGIN_BRIEF.md` (the "claude-mem (preferred) or Remember" line)
- Modify: `docs/superpowers/specs/2026-05-27-handoff-ctx-format-design.md` (addendum)

- [ ] **Step 1: Fix the brief's memory-tool reality**

In `PLUGIN_BRIEF.md`, find the table row:

```
| Local session memory | **claude-mem** (preferred) or **Remember** | Cross-session memory persistence with semantic retrieval. Handles handoff/resume across degrading sessions. |
```

Replace it with:

```
| Local session memory | **Remember** (installed/verified) | Cross-session memory persistence. Handles handoff/resume across degrading sessions. (claude-mem is not installed in this environment; Bitácora targets Remember.) |
```

- [ ] **Step 2: Append a decision addendum to the spec**

Append to the end of `docs/superpowers/specs/2026-05-27-handoff-ctx-format-design.md`:

```markdown

## Addendum — decisions made during planning (2026-05-27)

- **Plugin name `bitacora`** → canonical command `/bitacora:handoff` (command namespace
  equals plugin name). An **opt-in `/bit:` alias** is shipped as a copy-paste file
  (`plugins/bitacora/alias/bit-handoff.md`) the user drops into
  `~/.claude/commands/bit/handoff.md`; it invokes the same skill. No second plugin.
- **Handoff workflow lives in a `handoff` skill**, with `commands/handoff.md` a thin
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
```

- [ ] **Step 3: Verify the edits**

Run:
```bash
grep -q "Remember\*\* (installed/verified)" PLUGIN_BRIEF.md \
  && ! grep -q "claude-mem\*\* (preferred)" PLUGIN_BRIEF.md \
  && grep -q "Addendum — decisions made during planning" docs/superpowers/specs/2026-05-27-handoff-ctx-format-design.md \
  && echo OK
```
Expected: prints `OK`.

- [ ] **Step 4: Commit**

```bash
git add PLUGIN_BRIEF.md docs/superpowers/specs/2026-05-27-handoff-ctx-format-design.md
git commit -m "docs: align brief to Remember reality + record planning decisions in spec"
```

---

### Task 10: Final verification + manual acceptance checklist

**Files:**
- Create: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

- [ ] **Step 1: Re-run the automated validator test**

Run: `plugins/bitacora/scripts/test-validate-ctx.sh`
Expected: four `PASS:` lines, exit 0.

- [ ] **Step 2: Validate all JSON manifests and the file layout**

Run:
```bash
jq empty .claude-plugin/marketplace.json && jq empty plugins/bitacora/.claude-plugin/plugin.json \
  && for f in \
       plugins/bitacora/commands/handoff.md \
       plugins/bitacora/skills/handoff/SKILL.md \
       plugins/bitacora/skills/jira-comment-format/SKILL.md \
       plugins/bitacora/skills/jira-comment-format/examples/compliant.txt \
       plugins/bitacora/skills/jira-comment-format/examples/malformed.txt \
       plugins/bitacora/skills/jira-comment-format/examples/non-ctx.txt \
       plugins/bitacora/scripts/validate-ctx.sh \
       plugins/bitacora/alias/bit-handoff.md \
       plugins/bitacora/README.md \
       docs/JIRA_AGENT_COMMENT_FORMAT.md ; do
     test -f "$f" || { echo "MISSING: $f"; exit 1; }; done \
  && echo "LAYOUT OK"
```
Expected: prints `LAYOUT OK`, exit 0.

- [ ] **Step 3: Lint the shell scripts if shellcheck is available**

Run: `command -v shellcheck >/dev/null && shellcheck plugins/bitacora/scripts/*.sh || echo "shellcheck not installed — skipping"`
Expected: either no shellcheck findings, or the skip message. (Fix any error-level findings.)

- [ ] **Step 4: Create the manual acceptance checklist for dogfooding**

These require a real Jira + live sessions, so they are run by hand during personal use,
not in CI.

Create `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`:

```markdown
# Bitácora Phase 1 — Manual Acceptance Checklist

Run during dogfooding. Requires the `remember` plugin, the Atlassian Rovo MCP, and a real
Jira project. Install locally first: `/plugin marketplace add <path-to-this-repo>` then
`/plugin install bitacora@bitacora`.

- [ ] **A1 — canonical:** On a ticket-named branch, do real work, run `/bitacora:handoff`,
      approve, exit, start a fresh session. → Remember resumes the scratch with a correct
      restatement; the ticket shows a clean `[CTX]` comment.
- [ ] **A2 — no ticket:** From a branch with no ticket key and no ticket mentions, run
      handoff. → Local-only consolidated scratch, no Jira nag.
- [ ] **A3 — explicit args:** `/bitacora:handoff PROJ-1 PROJ-2`. → Exactly that ticket set
      is used.
- [ ] **A4 — MCP unavailable:** Disconnect/deny the Atlassian MCP, run handoff. → Jira half
      skipped gracefully, local completes, reason reported, no retry loop.
- [ ] **A5 — bad ticket key:** Force a non-existent key. → Error surfaced for that ticket,
      others unaffected, no crash.
- [ ] **A6 — malformed prior `[CTX]`:** Put a malformed `[CTX]` on the ticket first. →
      Lenient continuity-read still produces a sensible draft.
- [ ] **A7 — cancel:** Cancel at the gate. → Nothing written.
- [ ] **A8 — Remember fails:** Simulate a Remember failure. → Scratch printed to screen,
      Jira writes still offered.
- [ ] **A9 — multi-ticket:** Work on PROJ-1 (branch A), switch to PROJ-2 (branch B), mention
      PROJ-3, run handoff. → All three reconstructed and attributed (1→A, 2→B,
      3→current/mentioned); a `[CTX]` drafted per ticket; one consolidated scratch.
- [ ] **A10 — skip + isolation:** Three tickets; "skip 3"; make [2] 404 on write. → [1]
      writes ✓, [2] reports ✗ with retry offer, [3] dropped; scratch writes ✓ regardless.
- [ ] **`/bit:` alias:** After copying the alias file, `/bit:handoff` runs the same flow.
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "test: add Phase 1 manual acceptance checklist (A1–A10 + alias)"
```

---

## Self-review (completed during planning)

**Spec coverage:** every spec section maps to a task — multi-ticket flow → Task 5/6;
`[CTX]` format + compliance + golden examples → Tasks 2/4; `validate-ctx.sh` → Task 3;
integration/error handling → Task 5 (skill body); testing (fixtures + script + A1–A10) →
Tasks 3/10; manifests/scaffolding → Task 1; skill-vs-doc boundary → Tasks 4/8;
delegate-to-Remember → Task 5; brief reality edit → Task 9. New since the spec: the
`bitacora` naming + opt-in `/bit:` alias + handoff-as-skill refinement, all recorded in
the Task 9 spec addendum.

**Placeholder scan:** no TBD/TODO; every file step contains complete content; every verify
step has an exact command and expected output.

**Type/name consistency:** skill names (`bitacora:handoff`, `bitacora:jira-comment-format`,
`remember:remember`), the MCP tools (`getAccessibleAtlassianResources`, `getJiraIssue`,
`addCommentToJiraIssue`), the validator's three output words (`compliant` / `malformed` /
`not-in-format`) and exit codes (0/1/2), and the `$ARGUMENTS` token are used identically
across the command, skills, validator, test, and verification steps.
