# `/bitacora:improve` — Ticket Description Improver

Sharpen a vague or technically weak Jira ticket by rewriting its description (and
optionally its title) in place, grounded in a corpus the in-ticket Jira AI cannot see:
the `[CTX]` handoff trail, free-form discussion, local Remember scratch, and the git/PR
history that references the ticket key. The PM's original text is preserved by snapshot
to a Jira comment before any field edit, so every rewrite is reversible by copy-paste.

## Problem

PM-authored tickets are often vague — they capture intent but skip acceptance criteria,
technical scope, and ambiguity surfacing. Jira ships an AI feature for in-ticket prose
rewriting, but it sees only the ticket. By the time a ticket reaches a Bitácora user,
there is usually a richer corpus around it that Jira's AI cannot reach: prior `[CTX]`
status comments from past sessions, free-form discussion threads, local mid-task scratch
in Remember, and the actual commits and PRs that branch from the ticket key. A rewrite
grounded in that corpus is sharper than one grounded in the ticket field alone.

This command was originally planned, then dropped (PR #28) because the value-add was framed
as "local-codebase-grounded technical notes" — too thin against Jira's native feature. The
revival reframes the value: the corpus advantage is the differentiator, not the codebase
hook alone.

## Goal

`/bitacora:improve` (alias `/bit:improve`): resolve a target ticket, read the corpus
around it, ask up to 3 grounded clarifying questions, produce a type-aware structured
rewrite (Story / Bug / Epic / Subtask), show a diff, and on confirm post a snapshot
comment then write the new fields. Title rewrite is opt-in per invocation; description
rewrite is the default.

## Prerequisites

- **Atlassian Rovo MCP** with **read + write (edit)** access to Jira
  (`getJiraIssue`, `addCommentToJiraIssue`, `editJiraIssue`). MCP absent / auth fails /
  site unresolvable / no edit permission on the ticket is a **hard stop**.
- **Remember** is optional and additive; absence is normal.
- **`gh` CLI + a git repo** are optional and additive; absence is normal.

## Non-goals (YAGNI)

- No epic-level rewrites that walk linked tickets beyond one hop (no spider through
  parent/child/blocker chains). Linked-ticket reads were proposed and dropped during
  brainstorming.
- No `--no-clarify` / one-pass mode. The clarify loop is non-optional in v1; users who
  want to draft without it can always type `skip` to all questions.
- No two-phase `draft` + `--apply` split. One command, one flow.
- No subagent. The skill runs in the main thread, consistent with the four shipped
  siblings (`handoff` / `resume` / `status` / `next`).
- No backup of the new description back to a comment after writing (the archive comment
  captures the *pre*-state; the new state lives in the field).
- No automatic ticket-type inference beyond reading `issuetype.name` from the API.

## Design

Skill-only, mirroring the shipped siblings: a thin command delegates to `session-improve`
which runs the full read–clarify–draft–confirm–write workflow in the main thread.

### New files

- `plugins/bitacora/commands/improve.md` — thin trigger; delegates to `session-improve`,
  passing `$ARGUMENTS` (ticket key, optional).
- `plugins/bitacora/skills/session-improve/SKILL.md` — the workflow (below).
- `plugins/bitacora/skills/session-improve/examples/draft-story.txt` — a rendered Story
  draft fixture for documentation / review.
- `plugins/bitacora/skills/session-improve/examples/draft-bug.txt` — same, for Bug.
- `plugins/bitacora/alias/bit-improve.md` — opt-in `/bit:improve` alias
  (auto-synced into `~/.claude/commands/bit/` by the existing SessionStart hook).

### Edited files (on ship)

- `plugins/bitacora/commands/help.md` and `alias/bit-help.md` — add `/bitacora:improve`
  row to the help block (Shipped); add `/bit:improve` to the alias line.
- `plugins/bitacora/README.md` — add `/bitacora:improve` to the command table; add
  `/bit:improve` to the alias list.
- `README.md` (root) — add `/bitacora:improve` to the command table.
- `PLUGIN_BRIEF.md` — unmark the "Phase 2 dropped" tombstone for `/improve-ticket` to
  reflect the revival.

### Workflow (`session-improve` skill)

#### 1. Resolve the target ticket

- **Ticket key:** any `project_key_pattern` match in `$ARGUMENTS` forces the target.
  Otherwise resolve as in resume/status (current branch → `git reflog` recent checkouts
  with a disambiguation prompt → ask once).

#### 2. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. Multiple sites use `jira_cloud_id` if
configured, else ask. MCP/auth/site failure is a **hard stop**.

#### 3. Read the ticket

`getJiraIssue` for the resolved key, **requesting comments**. Capture
`description`, `summary` (title), `issuetype.name`, `status`, and all comments. Read
**lenient** (`[CTX]` and free-form both) per `bitacora:jira-comment-format`. 404 / no
edit permission on the ticket is a **hard stop** (see Error / edge behavior).

#### 4. Ask scope (title / description / both)

Now that the current title is in hand, ask the user *"Title: '<current title>' —
Improve title, description, or both?"* with **description** as the default. All three
choices are valid — title-only rewrites still benefit from corpus grounding. Choosing
title without description means step 7 writes the archive + a title edit only; choosing
description (default) means archive + description edit only.

#### 5. Assemble the rest of the corpus (graceful degradation)

Two more best-effort reads; either failing only suppresses that input.

1. **Remember scratch** — grep for the ticket key across
   `~/.claude/projects/<sanitized-cwd>/memory/` and any `.remember/` directory in the
   current working tree. Print "N scratch hits" or "0 scratch hits"; never block.
2. **Git/PR history** — `git log --all --grep=<KEY>` for commit subjects/bodies, plus
   `gh pr list --search <KEY> --state all` for open + merged PRs. Cap at the latest ~10
   of each. Skip silently when outside a repo or when `gh` is absent.

#### 6. Ask clarifying questions (capped at 3)

After corpus read, surface **up to `improve.clarify_max` (default 3)** specific
ambiguities **grounded in the source text** — never invent a question with no anchor in
the corpus. Example shape: *"'should work on mobile' — responsive web, PWA, or native?
The repo has all three."*

User answers inline, or types `skip` to proceed without. Unresolved items land in the
**Open questions** section of the rewrite. Hard cap at 3 — more than that and the ticket
should probably be split, not rewritten. If the agent has fewer than 3 grounded
questions, ask fewer; never pad to hit the cap.

#### 7. Draft the rewrite (type-aware sections)

Read `issuetype.name` from the API; pick a section template:

| Type | Sections (in order) |
|------|---------------------|
| **Story** *(default — also `Task`, `Improvement`, unknown)* | Acceptance criteria · Technical notes · Out of scope · Open questions |
| **Bug** | Steps to reproduce · Expected · Actual · Environment · Notes |
| **Epic** | Goal · Scope · Constituent stories · Risks · Out of scope |
| **Subtask** | Acceptance criteria · Technical notes *(lighter shape; just these two)* |

Compose the new description from the chosen template, populating each section from the
corpus + user's clarifications. Empty sections are **omitted**, not left as
placeholders. The new title (if scope includes title) is a single line, ≤ 80 chars,
imperative if the type is Story/Task/Improvement, declarative for Bug, scoped for Epic.

#### 8. Confirm

Show the user a unified diff of `description` (old → new) if the scope includes
description, and the proposed title beside its current value if the scope includes title.
Print "MCP write pending: 1 archive comment + N field edits." User confirms `y/n`. `n`
aborts without any write.

#### 9. Write (strict order; never retry silently)

On `y`:

1. **Archive comment first** via `addCommentToJiraIssue`. Body:

   ```
   [ARCHIVE] Pre-improve snapshot — <ISO 8601 UTC timestamp>

   Posted by /bitacora:improve before rewriting the fields. The block(s)
   below are the verbatim pre-edit content; safe to scroll past.

   ---

   Title (pre-edit):

   > <original title>

   Description (pre-edit):

   > <original description verbatim, each line prefixed with "> ">
   ```

   The `[ARCHIVE]` prefix is **not** `[CTX]` — `bitacora:jira-comment-format`'s strict
   readers classify it as `not-in-format` and skip it, exactly as intended. (Free-form
   comments are already ignored by state-extraction readers.)

   Include each block (title, description) only if the corresponding field is in scope
   for this invocation. The archive comment always captures the *pre*-state of every
   field about to be overwritten, no more, no less.

2. **Description edit** via `editJiraIssue` *(only if scope includes description)*.
3. **Title edit** via `editJiraIssue` *(only if scope includes title)*.

#### 10. Print outcome and stop

Print: ticket URL, list of writes performed (archive comment URL if surfaced by the API,
"description updated", "title updated"). No clipboard, no chained command.

### Failure modes during writes

Refers to the three write sub-steps in step 9 above: 9.1 archive, 9.2 description,
9.3 title.

- **9.1 (archive) fails:** abort. No field edits. Report the error verbatim. The user
  can rerun safely.
- **9.1 succeeds, 9.2 (description) fails:** archive is up; no field changes. Report:
  *"Snapshot posted, description edit failed — fields unchanged. The snapshot comment
  is benign as a standalone."* Rerun is safe; the next archive captures the
  still-unchanged original.
- **9.1 + 9.2 succeed, 9.3 (title) fails:** **partial state.** Report: *"Description
  updated and snapshot posted; **title edit failed** — title is still
  `<original title>`. The snapshot comment has the pre-state of both."* Suggest the
  user retry by rerunning the command and choosing **title** as the scope.

Never retry silently. Never roll back the archive comment (it remains a useful artifact
even if the subsequent edits failed).

### Example draft (Story)

See `examples/draft-story.txt`. Abbreviated shape:

```
PROJ-1234 — Make the export pipeline faster

(unchanged title shown if scope is description-only;
 proposed new title shown side-by-side if scope includes title)

--- description (proposed) ---

Acceptance criteria

- p95 export latency drops below 4s for tenants up to 50k rows
- No regression in the 10k-row baseline (currently ~1.8s)
- ...

Technical notes

- The `export_jobs` worker currently does a per-row write; batching
  would help (Sarah's caching idea, flagged in comment trail)
- ...

Out of scope

- ...

Open questions

- (3) Slack thread mentions "we may also need CSV" — confirm scope.
```

### Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable / 404 / no edit permission
  on the ticket:** **hard stop.** Name the cause; do not pretend a local-only fallback
  (there is nothing to improve without write access).
- **Empty description + zero comments + zero Remember hits + zero git hits:** decline
  with a clear message — there is nothing to ground a rewrite on. Suggest the user at
  least post a free-form comment describing the goal, then retry.
- **Issue type is unknown / custom:** fall back to the Story shape; print the chosen
  shape and the source type in the confirm step so the user can see the assumption.
- **User answers `skip` to all clarify questions:** fine; unresolved items land in Open
  questions.
- **Any write failure:** see the "Failure modes during writes" section above; never
  retry silently.
- Strict draft-then-confirm-then-write: **no Jira write before the user types `y`.**

### Configuration

Reuses `project_key_pattern` and `jira_cloud_id` from the
`bitacora:jira-comment-format` / handoff config (`${CLAUDE_PROJECT_DIR}/.bitacora.yml`
then `~/.claude/bitacora.yml`; absence is normal). Adds two optional keys:

```yaml
improve:
  clarify_max: 3              # cap on clarifying questions
  remember_paths:             # extra paths to scan for the ticket key (cwd is always scanned)
    - ~/.claude/projects
```

## Decisions

- **Edit fields in place, snapshot to comment first** — the user's explicit choice over
  the "post-comment-only" or "preserve original inside the new description" alternatives.
  The snapshot comment makes every rewrite reversible by copy-paste without polluting the
  new description.
- **Description-default, title opt-in per invocation** — title is a strictly named field
  with stricter cosmetic constraints; force the user to opt in rather than surprise them.
- **Corpus: ticket + Remember + git/PR; no linked-ticket walk** — the three picked
  during brainstorming are the ones Jira AI can't see (the differentiator) plus the
  irreducible base; linked-ticket walks were rejected as noisy for stories.
- **Clarify-questions-first, no `--no-clarify` knob** — forces the agent to surface
  ambiguities before writing prose around them; `skip` is the escape hatch.
- **Type-aware sections (Story / Bug / Epic / Subtask)** — better fit per type than a
  fixed shape; unknown types degrade to Story. No `.bitacora.yml` per-type override in
  v1.
- **Skill-only, main thread** — consistent with the four shipped siblings; the prior
  PLUGIN_BRIEF.md sketch's `agents/ticket-improver.md` is not built.
- **Archive comment uses an `[ARCHIVE]` prefix, not `[CTX]`** — strict `[CTX]` readers
  classify `[ARCHIVE]` as `not-in-format` and skip it, which is exactly the desired
  behavior (it's a snapshot, not a state update).
- **Write order is archive → description → title, with no silent retry** — partial-state
  semantics are explicit and reversible; the archive comment always lands first so the
  pre-state is captured even if a later step fails.

## Testing / verification

- The skill is workflow prose; no shell logic to unit-test. Ship two rendered example
  fixtures (`examples/draft-story.txt`, `examples/draft-bug.txt`) for documentation /
  review.
- **Live acceptance test:** invoke `/bitacora:improve` on a real PM-authored ticket with
  a non-trivial `[CTX]` trail. Confirm:
  - Clarify questions cite the source text (no inventions).
  - The diff in the confirm step is unified and readable.
  - Archive comment lands before the field edits.
  - `[ARCHIVE]` comment is classified `not-in-format` by `scripts/validate-ctx.sh` (so it
    is correctly skipped by strict `[CTX]` readers like `/bitacora:resume` and
    `/bitacora:status`).
  - The rewrite is **demonstrably better than Jira's native Atlassian Intelligence /
    Rovo improve-description** on the same ticket — soft quality bar, eyeballed.
- **Unit-testable adjuncts:**
  - `scripts/test-validate-ctx.sh` gains a fixture for an `[ARCHIVE]` comment, asserting
    `not-in-format` classification (exit code 2).
  - Optional: a fixture-driven test that the chosen section template matches the
    `issuetype.name` (Story → AC/Tech/OOS/OQ, etc.) — only if it can be written without
    mocking the Jira MCP.
