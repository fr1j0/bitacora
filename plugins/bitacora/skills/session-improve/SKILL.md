---
name: session-improve
description: Sharpen a Jira ticket — read the ticket plus its [CTX] trail, free-form comments, local Remember scratch, and git/PR history for the key; produce a type-aware structured rewrite (Story / Bug / Epic / Subtask) that makes confident engineering choices and labels them as Assumptions; show a diff; on accept, post a snapshot [ARCHIVE] comment then edit the description (and optionally the title) in place. Use when the user runs /bitacora:improve or /bit:improve.
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

- **Ticket 404 on read:** hard stop; name the cause. (Edit permission cannot be
  preflighted here — `getJiraIssue` is a read call. A 403 on `editJiraIssue` in
  step 8 is treated as a write failure per the failure-mode table in that step,
  not as a hard stop at read time.)

## 4. Ask scope (title / description / both)

Now that the current title is in hand, ask the user:

```
Title: "<current title>"
Improve title, description, or both? [d]escription / [t]itle / [b]oth
```

Default on bare enter: `description`. All three choices are valid — title-only
rewrites still benefit from corpus grounding. The chosen scope decides which fields
get archived in step 8 and which get edited.

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

## 6. Draft the rewrite (type-aware sections)

Read `issuetype.name` from the API response captured in step 3. Pick a section
template:

| Type | Sections (in order) |
|------|---------------------|
| **Story** *(default — also `Task`, `Improvement`, unknown / custom)* | Acceptance criteria · Technical notes · Assumptions · Out of scope · Open questions |
| **Bug** | Steps to reproduce · Expected · Actual · Environment · Notes |
| **Epic** | Goal · Scope outline · Success criteria · Assumptions · Risks · Out of scope |
| **Spike** | Question · Approach · Timebox · Out of scope · Recommendation *(left empty until the spike concludes)* |
| **Subtask** | Acceptance criteria · Technical notes · Assumptions *(lighter shape)* |

Compose the new description from the chosen template, populating each section from
the corpus. **Make confident product-engineering choices** wherever the corpus is
silent — do not interrogate the user. Surface those choices in the rewrite itself:

- **Assumptions** — implementation-level decisions the rewrite made (UI pattern,
  retry-counter scope, error-class taxonomy, etc.). An engineer picking up the
  ticket can re-decide; the assumption gives them the starting point and the
  reasoning. Bug templates absorb this material into `Notes`; Spike templates
  absorb it into `Approach`.
- **Open questions** — items that genuinely require a non-engineer stakeholder (PM,
  designer, security, legal) to weigh in. Reserved for *"we cannot ship without
  someone-outside-engineering answering this."* Most rewrites have none.

**Empty sections are omitted**, not left as placeholders. The new title (if scope
includes title) is a single line, ≤ 80 chars, imperative for Story/Task/Improvement,
declarative for Bug ("X does Y when Z"), scoped for Epic.

Never invent facts not grounded in the corpus or in standard product-engineering
judgment. If a section can't be populated, omit it; do not write filler.

## 7. Confirm

Show the user a unified diff of the description (old → new) **only if scope includes
description**, and the proposed title beside its current value **only if scope
includes title**. Print:

```
MCP write pending:
  - 1 [ARCHIVE] snapshot comment
  - N field edit(s) — <description | title | description + title>

Accept? (y/N)
```

`N` (or anything other than `y`) aborts without any Jira write. Default is no on bare
enter — improve writes by default would defeat the safety pattern.

**Iteration model.** On cancel, the user adds a free-form comment to the ticket with
their corrections (or edits an existing one) and reruns `/bitacora:improve`. The
ticket itself is the feedback channel; there is no pre-write Q&A.

## 8. Write (strict order, no silent retry)

On `y`:

**8.1 Archive comment** via `addCommentToJiraIssue`. Body:

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

**8.2 Description edit** via `editJiraIssue` *(only if scope includes description)*.

**8.3 Title edit** via `editJiraIssue` *(only if scope includes title)*.

### Failure modes during writes

- **8.1 (archive) fails:** abort. No field edits. Report the error verbatim. Rerun is
  safe.
- **8.1 succeeds, 8.2 fails:** archive is up; no field changes. Report:
  *"Snapshot posted, description edit failed — fields unchanged. The snapshot comment
  is benign as a standalone."* Rerun is safe.
- **8.1 + 8.2 succeed, 8.3 fails (or 8.1 succeeds and 8.3 fails when scope is
  title-only):** **partial state.** Report exactly which fields landed and which did
  not, name `<original title>` verbatim so the user can recover it, and suggest
  rerunning with **title** as the scope.

Never retry silently. Never roll back the archive comment — it remains a useful
artifact even on partial failure.

## 9. Print outcome and stop

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

- **Atlassian MCP absent / auth fails / site unresolvable / ticket 404 on read:**
  **hard stop.** Name the cause; do not pretend a local-only fallback. (Edit-permission
  failures surface at *write* time, in step 8 — see "Failure modes during writes"
  there.)
- **Empty description + zero comments + zero Remember hits + zero git hits:** decline
  with a clear message — there is nothing to ground a rewrite on. Suggest the user
  post a free-form comment describing the goal, then retry.
- **Issue type is unknown / custom:** fall back to the Story shape; print the chosen
  shape and the source type in the confirm step so the user can see the assumption.
- **Any write failure:** see "Failure modes during writes" above; never retry
  silently.
- Strict draft-then-accept-then-write: **no Jira write before the user types `y`.**

## Configuration

Reuses `project_key_pattern` and `jira_cloud_id` from the
`bitacora:jira-comment-format` / handoff config
(`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is
normal). Adds one optional key:

```yaml
improve:
  remember_paths:             # extra paths to scan for the ticket key (cwd is always scanned)
    - ~/.claude/projects
```
