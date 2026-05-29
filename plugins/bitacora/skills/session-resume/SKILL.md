---
name: session-resume
description: Rehydrate a fresh session from a Jira ticket's latest [CTX] comment(s) — read the structured state and print a compact, read-only briefing (where you left off, what's done, decided, next). Read-side counterpart to session-handoff. Use when the user runs /bitacora:resume or /bit:resume.
---

Read a single ticket's latest `[CTX]` state back into the session and print a compact
briefing. This is the **read-side counterpart to `bitacora:session-handoff`** and is
strictly **read-only** — it never writes to Jira or mutates Remember, so there is no
confirmation gate. Follow the **READ** rules in `bitacora:jira-comment-format` for
extracting state from `[CTX]` comments.

Optional explicit ticket key: any Jira-style key the invoking command passed through
(parse with `project_key_pattern`). If present, it forces the target.

## 1. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order:

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct candidates
  surface, **list them and let the user pick** — resume is about focus, not breadth. Never
  guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 2. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the `jira_cloud_id`
override if configured, else ask which (identical to handoff). **If the MCP is absent,
auth fails, or the site can't be resolved, this is a hard stop** (see Error behavior) —
resume cannot do its job without Jira read access.

## 3. Read the ticket

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments
using **strict** compliance per the READ rules in `bitacora:jira-comment-format`
(compliant `[CTX]` only — comments missing `Status:`/`Next:` are tallied as malformed,
non-`[CTX]` comments as not-in-format; never silently dropped):

- The **latest** `[CTX]` is authoritative for `Status` and `Next`.
- Read up to `resume.ctx_lookback` prior `[CTX]` comments (default 1) to reconstruct a
  short `Done` trajectory without re-quoting everything.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Surface excluded-comment counts (non-`[CTX]`, malformed) per the format skill; never
  silently drop.

## 4. Synthesize the briefing

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve PR links / URLs verbatim. Suggested shape:

```
Resuming PROJ-1234 — "<ticket title>"  (Jira status: In Progress)
https://<site>/browse/PROJ-1234

Where you left off:  <latest Status line>
Recently done:       <condensed Done bullets across the lookback window>
Decisions:           <decision + rationale bullets>
Next:                <actionable Next bullets>
Blockers / open Qs:  <only if present>

Suggested next step: <derived from the first Next item>
```

### Vagueness hint (footer suggestion, after the briefing)

If **all three** conditions hold, emit a one-line suggestion **after** the briefing
and **before** step 5's local-scratch reconciliation:

- `resume.improve_suggest.enabled` is true (default true; see Configuration)
- The ticket's `description` field is shorter than
  `resume.improve_suggest.min_description_words` (default 50; whitespace-split count
  on the description text — *not* on `[CTX]` comments or other fields)
- No `[ARCHIVE]`-prefixed comment exists on the ticket whose `created` timestamp
  is within `resume.improve_suggest.suppress_window_days` (default 7) of now —
  i.e., the ticket has not already been improved recently

Suggested format:

```
💡 This ticket's description is brief (<N> words, no recent [ARCHIVE]).
    Consider /bitacora:improve <KEY> before starting — corpus-grounded rewrite
    grounded in [CTX] history, comments, Remember scratch, and git/PR refs.
```

The hint is a **suggestion, not a gate** — the engineer can ignore it and proceed.
Never block the briefing on this check. If the suppression check encounters an error
(`getJiraIssue` did not return comments, for example), skip the hint silently rather
than failing the briefing.

## 5. Reconcile local scratch (optional, additive)

If a clean read of the Remember scratch is available, surface its private gotchas (dead
ends, fragile-code warnings) under a separate **Local notes** heading. If not, skip
silently — Remember already auto-injects local scratch at session start. This *enriches*
the Jira briefing; it is never a substitute (a missing MCP is a hard stop in step 2, not
something scratch can backfill).

## 6. Print and stop

Output the briefing into the conversation. Read-only: no gate, no write. Note that it's
safe to continue working.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; do not pretend a local-only fallback. (Surfacing any
  auto-injected Remember scratch is fine, but it is not "resume succeeding.")
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` at session ends so future resumes have
  something to read.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry
  with a different key. No retry loop.
- **Nothing to resume (no ticket resolved):** say so; suggest passing a key.

## Configuration

Reuses `project_key_pattern`, the compliance modes, and `jira_cloud_id` from the
`bitacora:jira-comment-format` / handoff config (`${CLAUDE_PROJECT_DIR}/.bitacora.yml`
then `~/.claude/bitacora.yml`; absence is normal). One optional addition:

```yaml
resume:
  ctx_lookback: 1               # how many prior [CTX] comments to stitch for the Done trajectory
  improve_suggest:
    enabled: true               # silence the vagueness hint entirely
    min_description_words: 50   # threshold; tickets with shorter descriptions are flagged
    suppress_window_days: 7     # skip the hint if an [ARCHIVE] landed within this window
```
