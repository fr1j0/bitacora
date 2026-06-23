---
name: tracker-adapter
description: How Bitácora selects and talks to a tracker backend (jira | github | gitlab). Use whenever a skill must read or write issues/comments — to resolve the active backend, pick the right verb, and reason about per-backend capability gaps.
allowed-tools: Read, Bash
---

This skill is the single source of truth for **tracker selection and the backend
verb layer**. The `[CTX]` comment format itself lives in `jira-comment-format`;
this skill says *which backend* a skill talks to and *how*.

## Resolve the active backend (every skill, first)

Run `resolve-tracker.sh` (in `plugins/bitacora/scripts/`):

    bash "$SCRIPTS/resolve-tracker.sh"   # → github | gitlab | jira

- exit 0: stdout is the backend.
- exit 4: not a git repo / no remote and no explicit `tracker:` — tell the user to
  set `tracker:` in `.bitacora.yml`, do not guess.

Branch once on **family**:

- `jira` → **mcp family**: use the Atlassian MCP exactly as today (unchanged).
- `github` / `gitlab` → **cli family**: use `bitacora-tracker.sh` (below). Run
  `bitacora-tracker.sh doctor` first; on exit 5 surface the auth/install guidance
  and stop.

## CLI verb reference (`bitacora-tracker.sh`)

Set `TRACKER` from the resolved backend; the data verbs emit normalized JSON
(`doctor` exits 0 with no output on success, exit 5 with guidance on failure).

| Need | Verb |
|---|---|
| issues assigned to me (for `next`) | `list-mine` |
| one issue | `view <id>` |
| the `[CTX]` corpus | `comments <id>` → `[{author,createdAt,body}]` |
| write a `[CTX]` / `[ARCHIVE]` comment | `comment <id> --body-file <f>` |
| rewrite the issue body (`improve`) | `edit-body <id> --body-file <f>` |
| current user | `whoami` |

Read the comment **date from `createdAt`**, never from the body (same rule as Jira).

## Capability table (semantic gaps the verbs can't hide)

| Capability | jira | github | gitlab |
|---|---|---|---|
| family | mcp | cli | cli |
| corpus = comments | ✓ | ✓ | ✓ |
| single editable body | description (ADF) | body (md) | description (md) |
| native issue types | ✓ | types (beta) / labels | labels |
| epic / rollup basis | epic→child link | sub-issues, else milestone | native epics |
| renderer autolinks bare URLs | ✗ (ADF) | ✓ (GFM)¹ | ✓ (GFM)¹ |
| identity token | accountId | `@me` / login | `@me` / username |
| scope unit | project key (map) | current repo | current project |

¹ Capability fact only — Bitácora wraps URLs regardless of backend. The shared
`validate-ctx.sh` gate rejects bare URLs on **every** family, so never emit one even
where the renderer would autolink it. See the render note in `jira-comment-format`.

Implications skills must honor:
- **Scope:** on the cli family the scope *is* the current repo — do not consult the
  Jira `remote_project_map`; `list-mine` is already repo-scoped.
- **Issue type:** on the cli family derive type from labels (or native issue type if
  present); fall back to a generic rewrite rather than refusing.
- **Epic rollup:** see `bitacora:session-digest` — degrade and label the basis.

## Render: see `jira-comment-format`

The `[CTX]` logical format is identical on every backend. Only the *render* differs
by family (URL wrapping, code marks); `jira-comment-format` documents both. Always
keep the literal `[CTX]` marker — it is the corpus selector.
