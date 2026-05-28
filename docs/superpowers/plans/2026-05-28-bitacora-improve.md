# `/bitacora:improve` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `/bitacora:improve` per the spec at `docs/superpowers/specs/2026-05-28-bitacora-improve-design.md` — a read-corpus / clarify / type-aware-rewrite / snapshot-then-write workflow for sharpening Jira tickets.

**Architecture:** Skill-only, main-thread, mirroring the four shipped siblings (`handoff` / `resume` / `status` / `next`). A thin `commands/improve.md` delegates to a `skills/session-improve/SKILL.md` that runs the full workflow. An opt-in `alias/bit-improve.md` is auto-sync'd by the existing `SessionStart` hook. Two rendered example fixtures (Story + Bug) ship under `skills/session-improve/examples/`. The only shell-testable surface is one new fixture asserting that `[ARCHIVE]`-prefixed comments are classified `not-in-format` by `scripts/validate-ctx.sh` (so strict `[CTX]` readers skip them). Help block + READMEs are updated in lockstep; PLUGIN_BRIEF.md's "dropped" tombstone is unmarked.

**Tech Stack:** Bash (validator + tests), Markdown (skills, commands, aliases, docs). No new dependencies. Branch already exists: `feat/bitacora-improve` (spec committed at `99275d5`).

---

## File Structure

**New files**
- `plugins/bitacora/commands/improve.md` — thin trigger; delegates to `bitacora:session-improve`, passes `$ARGUMENTS`.
- `plugins/bitacora/alias/bit-improve.md` — `/bit:improve` alias; same body as the command, different `description:` framing.
- `plugins/bitacora/skills/session-improve/SKILL.md` — the 10-step workflow.
- `plugins/bitacora/skills/session-improve/examples/draft-story.txt` — rendered Story-type rewrite fixture.
- `plugins/bitacora/skills/session-improve/examples/draft-bug.txt` — rendered Bug-type rewrite fixture.
- `plugins/bitacora/skills/jira-comment-format/examples/archive.txt` — new test fixture: an `[ARCHIVE]`-prefixed comment that must classify `not-in-format`.

**Edited files**
- `plugins/bitacora/scripts/test-validate-ctx.sh` — add one `check ... archive.txt not-in-format 2` line.
- `plugins/bitacora/commands/help.md` and `plugins/bitacora/alias/bit-help.md` — add `/bitacora:improve` row to the fenced help block (kept byte-identical between the two files); add `/bit:improve` to the alias line.
- `plugins/bitacora/README.md` — new row in the command table; add `/bit:improve` to the alias list.
- `README.md` (root) — new row in the command table.
- `PLUGIN_BRIEF.md` — replace the "Phase 2 dropped" tombstone for `/improve-ticket` with a revival note pointing at PR #28's drop and this revival spec.

**No-touch files** — explicitly out of scope to modify:
- `plugins/bitacora/scripts/validate-ctx.sh` — the validator logic is already correct (`[ARCHIVE]` is `not-in-format` because it doesn't start with `[CTX]`); we only add a regression-test fixture.
- `plugins/bitacora/skills/jira-comment-format/SKILL.md` — strict-skip behavior already covers `[ARCHIVE]` via the "anything not starting with `[CTX]` = `not-in-format`" rule.
- Any other shipped skill, command, or alias.

---

## Task 1: Add the `[ARCHIVE]` test fixture (TDD seed)

This is the only shell-testable change. Do it first so the validator-already-handles-it claim is locked in by a regression test before any other file gets touched.

**Files:**
- Create: `plugins/bitacora/skills/jira-comment-format/examples/archive.txt`
- Modify: `plugins/bitacora/scripts/test-validate-ctx.sh` (one new `check` line)

- [ ] **Step 1: Add the failing test assertion**

Open `plugins/bitacora/scripts/test-validate-ctx.sh`. Find the block of consecutive `check` calls (currently ends at the `check "$FIXTURES/non-ctx.txt" not-in-format 2` line). Insert a new `check` line immediately after it:

```bash
check "$FIXTURES/archive.txt"                         not-in-format 2
```

Match the column alignment of the surrounding lines (the `not-in-format` token aligns vertically across the block).

- [ ] **Step 2: Run the test and verify it fails**

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
```

Expected: the new line fails with `FAIL: archive.txt → got '' (...)` because the fixture file does not exist yet. Other lines still PASS. The script exits non-zero.

- [ ] **Step 3: Create the fixture**

Create `plugins/bitacora/skills/jira-comment-format/examples/archive.txt` with this body (verbatim, including the trailing newline):

```
[ARCHIVE] Pre-improve snapshot — 2026-05-28T14:23:11Z

Posted by /bitacora:improve before rewriting the fields. The block(s)
below are the verbatim pre-edit content; safe to scroll past.

---

Title (pre-edit):

> Make the export pipeline faster

Description (pre-edit):

> Users want this faster. Should work on mobile too.
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
```

Expected: every line PASSes, including the new `PASS: archive.txt → not-in-format (2)`. Script exits zero.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/examples/archive.txt \
        plugins/bitacora/scripts/test-validate-ctx.sh
git commit -m "test: assert [ARCHIVE]-prefixed comments classify as not-in-format"
```

---

## Task 2: Write the `session-improve` skill

**Files:**
- Create: `plugins/bitacora/skills/session-improve/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `plugins/bitacora/skills/session-improve/SKILL.md` with this content. The structure mirrors the existing sibling `plugins/bitacora/skills/session-next/SKILL.md` — read that file first as a stylistic template if you haven't.

```markdown
---
name: session-improve
description: Sharpen a Jira ticket — read the ticket plus its [CTX] trail, free-form comments, local Remember scratch, and git/PR history for the key; ask up to 3 grounded clarifying questions; produce a type-aware structured rewrite (Story / Bug / Epic / Subtask); show a diff; on confirm, post a snapshot [ARCHIVE] comment then edit the description (and optionally the title) in place. Use when the user runs /bitacora:improve or /bit:improve.
---

Sharpen a vague or technically weak Jira ticket by rewriting its description (and
optionally its title) in place, grounded in a corpus the in-ticket Jira AI cannot see:
the `[CTX]` handoff trail, free-form discussion, local Remember scratch, and the
git/PR history that references the ticket key. The PM's original text is preserved by
a snapshot Jira comment posted **before** any field edit, so every rewrite is
reversible by copy-paste.

Follow the **READ** rules in `bitacora:jira-comment-format` for state extraction from
`[CTX]` comments. For this command the read mode is **lenient** — free-form comments
are part of the corpus (they're often where the requirements actually live).

## 1. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order (identical to resume/status):

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct
  candidates surface, **list them and let the user pick**. Never guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 2. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the
`jira_cloud_id` override if configured, else ask. **If the MCP is absent, auth fails,
or the site can't be resolved, this is a hard stop** (see Error behavior) — improve
cannot do its job without Jira read + write access.

## 3. Read the ticket

`getJiraIssue` for the resolved key, **requesting comments**. Capture `description`,
`summary` (title), `issuetype.name`, `status`, and **all comments** (lenient — `[CTX]`
and free-form both, per `bitacora:jira-comment-format`).

- **404 / no edit permission on the ticket:** hard stop; name the cause. Improve writes
  to the ticket; read-only access is not enough.

## 4. Ask scope (title / description / both)

Now that the current title is in hand, ask the user:

```
Title: "<current title>"
Improve title, description, or both? [d]escription / [t]itle / [b]oth
```

Default on bare enter: `description`. All three choices are valid — title-only
rewrites still benefit from corpus grounding. The chosen scope decides which fields
get archived in step 9 and which get edited.

## 5. Assemble the rest of the corpus (graceful degradation)

Two more best-effort reads. Either failing only suppresses that input; neither blocks.

- **Remember scratch.** Grep for the ticket key across:
  - `~/.claude/projects/<sanitized-cwd>/memory/` (the standard auto-memory path)
  - any `.remember/` directory in the current working tree
  - any additional paths listed in `improve.remember_paths`

  Capture matching lines with file path + line number for grounding. Print "N scratch
  hits" or "0 scratch hits"; never block.

- **Git/PR history.** Best-effort:
  - `git log --all --grep=<KEY> --oneline | head -n 10` for commits.
  - `gh pr list --search <KEY> --state all --limit 10 --json number,title,state,url` if
    `gh` is on PATH and the repo has a GitHub remote.

  Outside a repo, or no `gh`, or no GitHub remote: skip silently.

## 6. Ask clarifying questions (capped at 3)

After the corpus is in hand, surface **up to `improve.clarify_max` (default 3)**
specific ambiguities **grounded in the source text** — never invent a question with no
anchor in the corpus. Example shape:

> "'should work on mobile' — responsive web, PWA, or native? The repo has all three.
> (anchor: ticket description, sentence 2)"

User answers inline, or types `skip` to proceed without. Unresolved items land in the
**Open questions** section of the rewrite. Hard cap at 3 — more than that and the
ticket should probably be split, not rewritten. If fewer than 3 grounded questions
exist, ask fewer; never pad to hit the cap. If zero, skip this step entirely.

## 7. Draft the rewrite (type-aware sections)

Read `issuetype.name` from the API response captured in step 3. Pick a section
template:

| Type | Sections (in order) |
|------|---------------------|
| **Story** *(default — also `Task`, `Improvement`, unknown / custom)* | Acceptance criteria · Technical notes · Out of scope · Open questions |
| **Bug** | Steps to reproduce · Expected · Actual · Environment · Notes |
| **Epic** | Goal · Scope outline · Success criteria · Risks · Out of scope |
| **Spike** | Question · Approach · Timebox · Out of scope · Recommendation *(left empty until the spike concludes)* |
| **Subtask** | Acceptance criteria · Technical notes *(lighter shape — just these two)* |

Compose the new description from the chosen template, populating each section from
the corpus + the user's clarify answers. **Empty sections are omitted**, not left as
placeholders. The new title (if scope includes title) is a single line, ≤ 80 chars,
imperative for Story/Task/Improvement, declarative for Bug ("X does Y when Z"),
scoped for Epic.

Never invent facts not grounded in the corpus. If a section can't be populated, omit
it; do not write filler.

## 8. Confirm

Show the user a unified diff of the description (old → new) **only if scope includes
description**, and the proposed title beside its current value **only if scope
includes title**. Print:

```
MCP write pending:
  - 1 [ARCHIVE] snapshot comment
  - N field edit(s) — <description | title | description + title>

Confirm? (y/N)
```

`N` (or anything other than `y`) aborts without any Jira write. Default is no on bare
enter — improve writes by default would defeat the safety pattern.

## 9. Write (strict order, no silent retry)

On `y`:

**9.1 Archive comment** via `addCommentToJiraIssue`. Body:

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

Include each block (title, description) only if the corresponding field is in scope
for this invocation. The archive comment always captures the *pre*-state of every
field about to be overwritten — no more, no less.

**9.2 Description edit** via `editJiraIssue` *(only if scope includes description)*.

**9.3 Title edit** via `editJiraIssue` *(only if scope includes title)*.

### Failure modes during writes

- **9.1 (archive) fails:** abort. No field edits. Report the error verbatim. Rerun is
  safe.
- **9.1 succeeds, 9.2 fails:** archive is up; no field changes. Report:
  *"Snapshot posted, description edit failed — fields unchanged. The snapshot comment
  is benign as a standalone."* Rerun is safe.
- **9.1 + 9.2 succeed, 9.3 fails (or 9.1 succeeds and 9.3 fails when scope is
  title-only):** **partial state.** Report exactly which fields landed and which did
  not, name `<original title>` verbatim so the user can recover it, and suggest
  rerunning with **title** as the scope.

Never retry silently. Never roll back the archive comment — it remains a useful
artifact even on partial failure.

## 10. Print outcome and stop

Print:

```
Improved <KEY>:
  - https://<site>/browse/<KEY>
  - archive comment: <comment URL or "(posted)" if no URL surfaced>
  - description: updated   (if in scope)
  - title:       updated   (if in scope)
```

No clipboard, no chained command. Read-and-confirm-then-write is the discipline.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable / 404 / no edit permission
  on the ticket:** **hard stop.** Name the cause; do not pretend a local-only
  fallback.
- **Empty description + zero comments + zero Remember hits + zero git hits:** decline
  with a clear message — there is nothing to ground a rewrite on. Suggest the user
  post a free-form comment describing the goal, then retry.
- **Issue type is unknown / custom:** fall back to the Story shape; print the chosen
  shape and the source type in the confirm step so the user can see the assumption.
- **User answers `skip` to every clarify question:** fine; unresolved items land in
  the Open questions section.
- **Any write failure:** see "Failure modes during writes" above; never retry
  silently.
- Strict draft-then-confirm-then-write: **no Jira write before the user types `y`.**

## Configuration

Reuses `project_key_pattern` and `jira_cloud_id` from the
`bitacora:jira-comment-format` / handoff config
(`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is
normal). Adds two optional keys:

```yaml
improve:
  clarify_max: 3              # cap on clarifying questions
  remember_paths:             # extra paths to scan for the ticket key (cwd is always scanned)
    - ~/.claude/projects
```

See `examples/draft-story.txt` and `examples/draft-bug.txt` for rendered examples of
the two most common section templates.
```

- [ ] **Step 2: Sanity-check the file**

Run `wc -l plugins/bitacora/skills/session-improve/SKILL.md` — expect ~150-200 lines (workflow prose; no hard target).

Visually scan: every workflow step number 1-10 present in order, no TBD/TODO/placeholders, no references to undefined config keys beyond the two declared in the Configuration section.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-improve/SKILL.md
git commit -m "feat(improve): add session-improve skill"
```

---

## Task 3: Write the command and alias files

**Files:**
- Create: `plugins/bitacora/commands/improve.md`
- Create: `plugins/bitacora/alias/bit-improve.md`

These are thin delegators. The body is nearly identical between them — only the `description:` frontmatter differs (the alias variant prefixes "(alias of /bitacora:improve) "). Compare against `plugins/bitacora/commands/next.md` and `plugins/bitacora/alias/bit-next.md` as the template.

- [ ] **Step 1: Create the command file**

Create `plugins/bitacora/commands/improve.md`:

```markdown
---
description: Sharpen a Jira ticket — read the ticket plus its [CTX] trail, free-form comments, local Remember scratch, and git/PR history; ask up to 3 grounded clarifying questions; produce a type-aware structured rewrite; snapshot the pre-state to an [ARCHIVE] comment, then edit the description (and optionally the title) in place.
---

Use the `bitacora:session-improve` skill to run the ticket-improvement workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Create the alias file**

Create `plugins/bitacora/alias/bit-improve.md`:

```markdown
---
description: (alias of /bitacora:improve) Sharpen a Jira ticket — grounded structured rewrite, snapshot to [ARCHIVE] comment first.
---

Use the `bitacora:session-improve` skill to run the ticket-improvement workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts.

Arguments: $ARGUMENTS
```

- [ ] **Step 3: Verify both files exist and the bodies match**

```bash
diff \
  <(sed '1,/^---$/d; 1,/^---$/d' plugins/bitacora/commands/improve.md) \
  <(sed '1,/^---$/d; 1,/^---$/d' plugins/bitacora/alias/bit-improve.md)
```

Expected: no output (bodies identical past the frontmatter).

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/commands/improve.md plugins/bitacora/alias/bit-improve.md
git commit -m "feat(improve): add /bitacora:improve command + /bit:improve alias"
```

---

## Task 4: Write the rendered example fixtures

**Files:**
- Create: `plugins/bitacora/skills/session-improve/examples/draft-story.txt`
- Create: `plugins/bitacora/skills/session-improve/examples/draft-bug.txt`

These are *rendered output examples* — what the skill would print at the **confirm** step (step 8). They document the type-aware shape and double as review artifacts. Mirror the form factor of `plugins/bitacora/skills/session-next/examples/shortlist.txt` (rendered, monospace, no markdown chrome).

- [ ] **Step 1: Create `draft-story.txt`**

Create `plugins/bitacora/skills/session-improve/examples/draft-story.txt`:

```
Improving PROJ-1234 — "Make the export pipeline faster"  (Story, In Progress)
Corpus: 3 [CTX] comments · 5 free-form comments · 4 Remember hits · 2 commits · 1 PR

3 clarifying questions before rewriting:

1. "users want this faster" — do we have a target p95, or qualitative?
   (anchor: description, sentence 1)
2. "should work on mobile" — responsive web, PWA, or native? The repo has all three.
   (anchor: description, sentence 2)
3. Slack thread (linked in comment #3) mentions Sarah's caching idea — in scope or
   follow-up? (anchor: comment #3 from sarah@)

Answers (or "skip"): >  p95 4s · responsive web · caching follow-up

--- description (proposed) ---

Acceptance criteria

- p95 export latency drops below 4s for tenants up to 50k rows
- No regression in the 10k-row baseline (currently ~1.8s)
- Responsive-web only (PWA / native explicitly out of scope)

Technical notes

- The export_jobs worker currently does a per-row write; batching is the obvious lever
- Sarah's caching idea (comment #3) is parked as a follow-up, not part of this story
- See PR #781 (in progress) for the worker scaffolding

Out of scope

- Caching layer (follow-up ticket)
- PWA / native client work

Open questions

- (none — all clarifying questions resolved)

--- title (unchanged — scope is description-only) ---

MCP write pending:
  - 1 [ARCHIVE] snapshot comment
  - 1 field edit — description

Confirm? (y/N)
```

- [ ] **Step 2: Create `draft-bug.txt`**

Create `plugins/bitacora/skills/session-improve/examples/draft-bug.txt`:

```
Improving PROJ-9821 — "logout broken sometimes"  (Bug, To Do)
Corpus: 0 [CTX] comments · 4 free-form comments · 0 Remember hits · 0 commits · 0 PRs

2 clarifying questions before rewriting:

1. "broken sometimes" — what fraction of attempts, and any pattern (browser / region /
   tenant)? (anchor: description, sentence 1)
2. comment #2 mentions a 401 — is the bug that logout fails silently, or that it
   returns 401? (anchor: comment #2 from qa@)

Answers (or "skip"): > ~10% on Safari only · 401 in console, UI shows "logged out"

--- description (proposed) ---

Steps to reproduce

1. Log in on Safari (any version observed so far: 16, 17).
2. Click "Log out" in the user menu.
3. Observe the UI returns to the login screen.
4. Open DevTools → Network and inspect the /api/session/end request.

Expected

- /api/session/end returns 204.
- The session cookie is cleared.

Actual

- /api/session/end returns 401 (~10% of the time, Safari only).
- The UI shows the login screen as if logout succeeded.
- The session cookie persists in some cases — reloading the page restores the session.

Environment

- Safari 16 + 17 confirmed; Chrome / Firefox not reproducible.
- All tenants observed; no region pattern.

Notes

- Suspected timing race in the session-end handler; see comment #4 from oncall@.
- Reproduction script in comment #2 attachments.

--- title (proposed) ---
- (current)  "logout broken sometimes"
- (new)      "Logout returns 401 intermittently on Safari, leaving stale session cookie"

MCP write pending:
  - 1 [ARCHIVE] snapshot comment
  - 2 field edits — description + title

Confirm? (y/N)
```

- [ ] **Step 3: Verify the files exist and are non-empty**

```bash
ls -la plugins/bitacora/skills/session-improve/examples/
wc -l plugins/bitacora/skills/session-improve/examples/*.txt
```

Expected: both files present, each non-zero line count.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-improve/examples/draft-story.txt \
        plugins/bitacora/skills/session-improve/examples/draft-bug.txt
git commit -m "feat(improve): add Story + Bug rendered draft fixtures"
```

---

## Task 5: Update the help block (commands + alias, kept in lockstep)

**Files:**
- Modify: `plugins/bitacora/commands/help.md`
- Modify: `plugins/bitacora/alias/bit-help.md`

The fenced ` ``` ` block inside these two files **must remain byte-identical** (per the comment near the top of each file). Apply the same change to both.

- [ ] **Step 1: Update `commands/help.md`**

In `plugins/bitacora/commands/help.md`, find this line:

```
  /bitacora:next                Morning ticket picker — categorized
                                shortlist of your assigned tickets
                                grounded in [CTX] (read-only).
```

Insert a new entry directly below it (before the `/bitacora:help` line), with the **exact same column alignment** as the surrounding rows:

```
  /bitacora:improve             Sharpen a ticket — corpus-grounded
                                rewrite (Story/Bug/Epic-aware) with a
                                snapshot to [ARCHIVE] before the edit.
```

Then update the Alias line at the bottom of the fenced block — change:

```
  Alias: /bit:handoff, /bit:resume, /bit:status, /bit:next, /bit:help (opt-in — see plugin README)
```

to:

```
  Alias: /bit:handoff, /bit:resume, /bit:status, /bit:next, /bit:improve, /bit:help (opt-in — see plugin README)
```

- [ ] **Step 2: Apply the identical change to `alias/bit-help.md`**

Repeat the same two edits in `plugins/bitacora/alias/bit-help.md`.

- [ ] **Step 3: Verify the two fenced blocks are byte-identical**

```bash
diff \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md)
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md
git commit -m "feat(improve): add /bitacora:improve to the help reference"
```

---

## Task 6: Update the plugin and root READMEs

**Files:**
- Modify: `plugins/bitacora/README.md`
- Modify: `README.md` (root)

- [ ] **Step 1: Update the plugin README command table**

In `plugins/bitacora/README.md`, the command table currently has rows ending with the `/bitacora:next` row before the `/bitacora:help` row. Insert a new row for `/bitacora:improve` between `/bitacora:next` and `/bitacora:help`:

```markdown
| `/bitacora:improve` | Sharpen a ticket — read the ticket plus its `[CTX]` trail, free-form comments, local Remember scratch, and git/PR history; ask up to 3 grounded clarifying questions; produce a type-aware structured rewrite (Story / Bug / Epic / Subtask); snapshot the pre-state to an `[ARCHIVE]` comment, then edit the description (and optionally the title) in place. |
```

- [ ] **Step 2: Update the plugin README alias list**

In the same file, find the paragraph that begins:

```
This copies every bundled alias (the `bit-` prefix is stripped to form the
command name). Then `/bit:handoff`, `/bit:resume`, `/bit:status`, `/bit:next`,
and `/bit:help` run the same workflows as their `/bitacora:…` forms.
```

Change it to:

```
This copies every bundled alias (the `bit-` prefix is stripped to form the
command name). Then `/bit:handoff`, `/bit:resume`, `/bit:status`, `/bit:next`,
`/bit:improve`, and `/bit:help` run the same workflows as their `/bitacora:…` forms.
```

- [ ] **Step 3: Update the root README command table**

In `README.md` (root), the command table currently lists handoff / help / resume / status / next as Phase 1. Append a new row for `/bitacora:improve` (after `/bitacora:next` or anywhere alphabetical works — the existing rows are not strictly alphabetical, just match the help-block order):

```markdown
| `/bitacora:improve` | Sharpen a ticket — corpus-grounded structured rewrite (Story / Bug / Epic / Subtask aware) with a snapshot to an `[ARCHIVE]` Jira comment before any field edit. Read + write; description by default, title opt-in per invocation. |
```

- [ ] **Step 4: Verify the rendered tables look right**

```bash
grep -A 0 "^| \`/bitacora:" README.md
grep -A 0 "^| \`/bitacora:" plugins/bitacora/README.md
```

Expected: each grep shows a row per shipped command, including `/bitacora:improve`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/README.md README.md
git commit -m "docs(improve): add /bitacora:improve to the plugin + root READMEs"
```

---

## Task 7: Unmark the PLUGIN_BRIEF.md tombstone

**Files:**
- Modify: `PLUGIN_BRIEF.md`

The original /improve-ticket entry was marked "dropped (2026-05-27)" in PR #28. Revive it with a clear pointer to the new spec.

- [ ] **Step 1: Update the tombstone heading and note**

Find this block in `PLUGIN_BRIEF.md` (around the `### Phase 2 — \`/improve-ticket\`` section):

```markdown
### Phase 2 — `/improve-ticket` — **dropped (2026-05-27)**

> **Not building this.** A design spike (TESTING-10) reached "build with caveats," but
> Jira now ships a strong native improve-description feature (Atlassian Intelligence / Rovo)
> that covers prose rewriting, acceptance criteria, and ambiguity surfacing in-ticket. The
> only thing a Bitácora command added was local-codebase-grounded technical notes — too thin
> to justify duplicating a feature the vendor owns. Bitácora stays focused on the
> agent-session lifecycle (handoff / resume / status + `[CTX]`). Original sketch retained
> below for history.
```

Replace it with:

```markdown
### Phase 2 — `/improve-ticket` — **revived (2026-05-28)**

> **Building this.** Originally dropped on 2026-05-27 (PR #28) because the value-add was
> framed as "local-codebase-grounded technical notes," too thin against Jira's native
> Atlassian Intelligence / Rovo. The revival reframes the value: the corpus advantage —
> `[CTX]` trail + free-form comments + local Remember scratch + git/PR history for the
> ticket key — is what Jira's in-ticket AI cannot see, and is the real differentiator.
> See `docs/superpowers/specs/2026-05-28-bitacora-improve-design.md`. Original sketch
> retained below for history.
```

- [ ] **Step 2: Verify the edit landed cleanly**

```bash
grep -n "improve-ticket" PLUGIN_BRIEF.md | head -5
```

Expected: the heading line now says **revived (2026-05-28)**, not **dropped**.

- [ ] **Step 3: Commit**

```bash
git add PLUGIN_BRIEF.md
git commit -m "docs(improve): unmark PLUGIN_BRIEF.md tombstone — revival"
```

---

## Task 8: Final verification

**Files:** none modified — verification only.

- [ ] **Step 1: Run the validate-ctx test suite**

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
```

Expected: every line PASSes, including `PASS: archive.txt → not-in-format (2)`. Script exits zero.

- [ ] **Step 2: Run the alias-sync test suite**

```bash
plugins/bitacora/scripts/test-sync-bit-aliases.sh
```

Expected: every assertion PASSes, including the "later-added alias syncs automatically" case (which now picks up `bit-improve.md`).

- [ ] **Step 3: Verify the help fenced block is in sync**

```bash
diff \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md)
```

Expected: no output.

- [ ] **Step 4: Review the full diff against `main`**

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Expected: 7 commits (one per task 1-7) on `feat/bitacora-improve`, touching only the files listed at the top of this plan plus the spec (`docs/superpowers/specs/2026-05-28-bitacora-improve-design.md`, already on the branch).

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin feat/bitacora-improve
```

Then open the PR (will need the `skip-issue-check` label per precedent — there is no tracked issue):

```bash
gh pr create --title "feat: /bitacora:improve ticket improver (corpus-grounded rewrite)" \
             --label "skip-issue-check,enhancement" \
             --body "$(cat <<'EOF'
## Summary

Implements /bitacora:improve per docs/superpowers/specs/2026-05-28-bitacora-improve-design.md — reverses the PR #28 drop with a new value framing.

- Skill-only main-thread workflow mirroring handoff/resume/status/next.
- Corpus: ticket + all comments (lenient) + Remember scratch + git/PR history for the key.
- Up to 3 grounded clarifying questions before the rewrite (no padding to hit the cap).
- Type-aware sections (Story / Bug / Epic / Subtask); unknown types degrade to Story.
- Snapshot pre-state to [ARCHIVE]-prefixed Jira comment BEFORE any field edit; classifier ignores [ARCHIVE] as not-in-format.
- Description-default, title opt-in per invocation. Strict draft → confirm → write, no silent retry.

## Why skip-issue-check

No tracked issue (auto-mode classifier blocks gh issue create). Precedent: #40, #42, #43, #44.

## Test plan

- [x] scripts/test-validate-ctx.sh — new archive.txt fixture asserts not-in-format.
- [x] scripts/test-sync-bit-aliases.sh — picks up bit-improve.md automatically.
- [x] help.md / bit-help.md fenced blocks byte-identical.
- [ ] Live: invoke /bitacora:improve on a real PM-authored ticket; verify clarify Qs cite source, diff readable, archive comment lands before fields, [ARCHIVE] classifies not-in-format.
EOF
)"
```

- [ ] **Step 6: Wait for CI**

Use the same pattern as recent PRs (#42, #43, #44): poll until checks complete. Required checks are the issue-gate and validate-ctx; the latest run per name is what branch protection consults.

```bash
until gh pr view <PR#> --json statusCheckRollup --jq '[.statusCheckRollup[] | select(.status != "COMPLETED")] | length == 0' | grep -q true; do sleep 10; done
gh pr checks <PR#>
```

Stop here and report to the user. **Do not auto-merge** — the user has been confirming each merge explicitly this session.

---

## Notes for the implementer

- **Branch is already created** — `feat/bitacora-improve` (spec committed at `99275d5`). All tasks build on it.
- **Sibling templates** — `plugins/bitacora/skills/session-next/SKILL.md` is the closest analog for the skill prose style; `plugins/bitacora/commands/next.md` + `plugins/bitacora/alias/bit-next.md` are the templates for the thin command + alias.
- **The fenced help-block contract** — `commands/help.md` and `alias/bit-help.md` must keep the inner ` ``` ` block byte-identical; the comment at the top of each file is the contract.
- **No new permissions** — the spec calls for `addCommentToJiraIssue` (already used by handoff) and `editJiraIssue` (new, but read from `bitacora:jira-comment-format`'s already-declared MCP prereq). No settings.json edits required.
- **No subagent, no agents/ dir** — the prior PLUGIN_BRIEF.md sketch mentioned `agents/ticket-improver.md`; the v1 spec explicitly does not build it.
- **Memory update after merge** — the project memory at `~/.claude/projects/-Users-fernandocastillo-Projects-bitacora/memory/project_bitacora-no-ticket-authoring.md` says "/improve and /spike both dropped; don't rebuild." Update it after the PR merges to record the /improve revival (spike stays dropped).
