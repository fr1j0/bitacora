---
name: session-improve
description: Sharpen a ticket — read the ticket plus its [CTX] trail, free-form comments, local Remember scratch, and git/PR history for the key; produce a type-aware structured rewrite (Story / Bug / Epic / Subtask) that makes confident engineering choices and labels them as Assumptions; show a diff; on accept, post a snapshot [ARCHIVE] comment then edit the description (and optionally the title) in place. Use when the user runs /bitacora:improve or /bit:improve. Supports both Jira (MCP) and GitHub/GitLab Issues (cli family via bitacora-tracker.sh).
---

Sharpen a vague or technically weak ticket by rewriting its description (and
optionally its title) in place, grounded in a corpus the in-ticket AI cannot see:
the `[CTX]` handoff trail, free-form discussion, local Remember scratch, and the
git/PR history that references the ticket key. The original text is preserved by
a snapshot comment posted **before** any field edit, so every rewrite is
reversible by copy-paste.

Follow the **READ** rules in `bitacora:jira-comment-format` for state extraction from
`[CTX]` comments. For this command the read mode is **lenient** — free-form comments
are part of the corpus (they're often where the requirements actually live).

## 0. Resolve the tracker (first)

Before anything else, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tracker.sh"
```

This emits one of `github`, `gitlab`, or `jira`. Branch on the result:

- **jira** → continue to step 1 as today (MCP path, steps 1–9 below).
- **github / gitlab (cli family)** → execute the **cli branch** below to completion.
  It is self-contained — it carries its own confirm/write/outcome steps and stops on
  its own; do **not** continue into the Jira-path steps 1–9. See the `tracker-adapter`
  skill for the verb contract.

### cli branch (github / gitlab)

Run `doctor` first; exit 5 from the adapter is a hard stop — print the guidance
and stop:

```bash
TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" doctor
```

**Resolve the ticket id** first. Use the same priority order as step 1 (explicit arg →
current branch → reflog), but match a GitHub/GitLab issue number instead of a Jira
key.

**Read the issue.** The issue has a single markdown **body** (no ADF). Read it with:

```bash
TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" view <id>
```

The verb returns JSON `{number, title, body, labels, state, milestone, comments}`.
Capture `body`, `title`, `labels`, and `comments`.

**Derive issue type from labels.** Inspect `labels` for values such as `bug`,
`enhancement`, `story`, `epic`, `subtask`, `spike`, or tracker-native types. If no
recognisable type label is present, fall back to the Story shape and surface the
assumption in the confirm step.

**Assemble corpus.** Read `[CTX]` comments from the `comments` array (lenient per
`bitacora:jira-comment-format`). Grep Remember scratch and git/PR history exactly as
step 5 (Jira path) does — the corpus assembly is identical.

**Draft the rewrite.** Use the same type-aware section templates as step 6 (Jira
path). The output is plain **GitHub-Flavored Markdown** — no ADF wrapping. Apply the
same formatting conventions: `###` headings, bulleted lists, inline-code every
technical token, wrap URLs (no bare URLs), use compact refs. **Empty sections are
omitted.**

**Confirm (shared gate — identical to step 7).** Show the unified diff and proposed
title; print:

```
Tracker write pending:
  - 1 [ARCHIVE] snapshot comment
  - N field edit(s) — <body | title | body + title>

Accept? (y/N)
```

`N` (or bare enter) aborts — **no write before the user types `y`.**

**Write (on `y` — strict order).**

1. **Snapshot first.** Write `$TMP/archive-<id>.md` containing the `[ARCHIVE]`
   header and the verbatim pre-edit body (fenced in triple backticks, widened to
   four if the body itself contains a fence). Post it as a comment:

   ```bash
   TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" \
     comment <id> --body-file "$TMP/archive-<id>.md"
   ```

2. **Then overwrite the body.** Write `$TMP/rewrite-<id>.md` containing the new GFM
   body. Replace the issue body:

   ```bash
   TRACKER=<resolved-backend> bash "${CLAUDE_PLUGIN_ROOT}/scripts/bitacora-tracker.sh" \
     edit-body <id> --body-file "$TMP/rewrite-<id>.md"
   ```

   The snapshot step MUST complete successfully before `edit-body` is called — if the
   archive comment fails, abort without touching the body.

3. **Title edit (if in scope) — separate confirmed step.** Run:

   ```bash
   gh issue edit <id> --title "<new title>"
   ```

   Confirm the new title explicitly before running this command.

**Failure modes (cli arm)** mirror the Jira arm: archive failure → abort; body
failure after archive → report both states; title failure after body succeeds → report
partial state with the original title verbatim.

**Outcome.** Print:

```
Improved #<id>:
  - <issue URL>
  - archive comment: posted
  - body: updated   (if in scope)
  - title: updated  (if in scope)
```

Then stop. For the full verb contract see the `tracker-adapter` skill.

---

## 1. Resolve the target ticket (single, focused) — Jira path

Resolve exactly one ticket, in priority order (identical to resume/status):

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct
  candidates surface, **list them and let the user pick**. Never guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 2. Resolve the Atlassian site — Jira path

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the
`jira_cloud_id` override if configured, else ask. **If the MCP is absent, auth fails,
or the site can't be resolved, this is a hard stop** (see Error behavior) — improve
cannot do its job without Jira read + write access.

## 3. Read the ticket — Jira path

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

| Type | Sections — **each rendered as a Markdown `###` heading**, in order |
|------|---------------------|
| **Story** *(default — also `Task`, `Improvement`, unknown / custom)* | User story · Context · Acceptance criteria · Assumptions · Other information |
| **Bug** | Steps to reproduce · Expected · Actual · Environment · Notes |
| **Epic** | Goal · Scope outline · Success criteria · Assumptions · Risks · Other information |
| **Spike** | Question · Approach · Timebox · Recommendation *(left empty until the spike concludes)* · Other information |
| **Subtask** | Context · Acceptance criteria · Assumptions *(lighter shape)* |

**Formatting — match Jira's native AI "improve description" output:**

- Render each section name as a Markdown `###` heading, never a bold-label line.
- Use bulleted lists for every enumeration (criteria, affected files, services, blockers).
- **Inline-code every technical token:** endpoint URIs (`` `POST /prices/fetch-price-by-identifiers` ``),
  RPC / service / method names (`` `market.v1.RealtimePricesService.GetRealtimePrices` ``), proto /
  field names (`` `last` ``), `` `package@version` ``, file paths (`` `lib/api/rest/ai-api-client.ts` ``),
  config keys, and identifiers (`` `TRDPRC_1` ``). This is what makes the rewrite scannable in Jira.
- **Story shape specifically:** `### User story` opens with *"As a `<role>`, when `<situation>`, I want
  to `<action>` so that `<benefit>`."*; `### Context` is the grounding narrative (what's changing and
  why, the services/endpoints involved, the affected files as a bulleted list); `### Other information`
  collects blockers, cross-ticket dependencies, out-of-scope, and any open questions.

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
  someone-outside-engineering answering this."* Most rewrites have none. Place them under
  `### Other information` (Story/Epic) rather than a heading of their own.

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

````
[ARCHIVE] Pre-improve snapshot

Posted by /bitacora:improve before rewriting the fields. The block(s)
below are the verbatim pre-edit content; safe to scroll past.

---

Title (pre-edit):

<original title>

Description (pre-edit):

```
<original description verbatim, unmodified>
```
````

**Container format — use a fenced code block, never a blockquote.** Ticket
descriptions are themselves Markdown (`## headings`, `* lists`). Prefixing each line
with `> ` produces `> ## heading`, and the Markdown→ADF conversion drops block-level
constructs nested inside a blockquote, silently clipping the snapshot after the first
heading. A fenced ` ``` ` block preserves arbitrary content verbatim, which is the
whole point of the archive. Edge case: if the original description itself contains a
triple-backtick fence, widen the outer fence to four backticks (or more, always one
more than the longest run inside) so the snapshot still round-trips. The title is a
single plain-text line and needs no fence.

No timestamp in the header — the comment's `created` metadata is authoritative, per
the same rule `bitacora:jira-comment-format` enforces for `[CTX]` headers. Include
each block (title, description) only if the corresponding field is in scope for
this invocation. The archive comment always captures the *pre*-state of every field
about to be overwritten — no more, no less.

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
