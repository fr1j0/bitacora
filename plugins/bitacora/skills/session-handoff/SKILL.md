---
name: session-handoff
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
- **Branches visited recently:** `git reflog --date=iso | grep -i checkout | head -n 20` —
  extract key matches from branch names. The reflog is unbounded history, so cap it
  (≈ last 20 checkouts), de-duplicate, and treat it as a heuristic: stale branches may
  appear, which is fine — the gate lets the user drop anything irrelevant. Prefer tickets
  with actual session work over bare branch visits.
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
PR), no speculation. For a ticket that was only *mentioned* while you worked on another
ticket's branch, its `[CTX]` should capture only the outcomes or decisions directly about
that ticket (e.g. a blocker found, a dependency noted) — not a re-summary of the session.

**Work-type enrichment (auto-populate the optional sections).** While drafting, detect what
the session actually did and populate the matching optional sections from the
`bitacora:jira-comment-format` skill — **from real evidence only, never invented.** Cues:

| Detected signal | Populate |
|---|---|
| `*.tf`, `Dockerfile`, k8s / `helm/` manifests, or CI config touched | `Deploy/Ops:` + `Impact: infra` |
| `migrations/` or schema files touched | `Impact: schema` + a contract note in `Decisions:` |
| `*.ipynb`, mlflow/wandb references, model files, or eval scripts | `Model/Eval:` + `Impact: model-serving` |
| component/route files touched | `Impact: ui` (add an `Artifacts:` design link only when a Figma URL is actually present) |
| API spec / server route files touched | `Impact: api` + a contract delta in `Decisions:` |
| other ticket keys mentioned this session | `Dependencies:` |

When several rows match, **merge their surfaces into a single `Impact:` line** (e.g.
`Impact: infra, schema`) — never emit more than one `Impact:` line.

When the evidence is weak or ambiguous, **omit the section rather than guess** — the confirm
gate (step 4) shows the conservative draft and the user can add detail. `Risk:` is not
auto-detected from file signals; add it at the confirm gate when a latent risk is apparent
from the session. Separately, add the `Status:` confidence cue and the `[precedent]` /
`[debt]` / `[blast-radius]` decision tags when warranted.

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
   passing the scratch content prepared in step 3. If it fails, warn and **print the
   scratch to screen** for manual save, then proceed to the Jira writes — the existing
   per-ticket confirmation gate in step 4 still applies; do **not** add a second
   "still attempt Jira writes?" prompt here.
2. **Resolve the Atlassian site:** `getAccessibleAtlassianResources` → `cloudId`. If
   multiple sites, ask which (or use a `jira_cloud_id` override if configured).
3. **Validate each drafted `[CTX]` body before writing.** Pipe the body through
   `${CLAUDE_PLUGIN_ROOT}/scripts/validate-ctx.sh` (or `plugins/bitacora/scripts/validate-ctx.sh`
   from the repo root). If the output is anything other than `compliant`, **do not write
   that ticket's comment** — surface the validator's stderr reason to the user, keep the
   draft, and offer: edit-and-retry / skip-this-ticket / cancel-all. Other tickets are
   unaffected. The validator catches the structural rule (missing `Status:`/`Next:`) and
   the *Write rules* hygiene classes from `jira-comment-format` — bare URLs (Jira won't
   linkify) and tool-arg-leak sentinels (`<parameter name=`, `</commentBody>`, …).
   Example:

   ```bash
   printf '%s\n' "$body" | "${CLAUDE_PLUGIN_ROOT}/scripts/validate-ctx.sh" >/dev/null
   # exit 0 = compliant; 1 = malformed (reason on stderr); 2 = not-in-format
   ```

4. **Write each approved+validated ticket's `[CTX]`** via `addCommentToJiraIssue`,
   following the *Write mechanics* rule in `jira-comment-format` (blank line before/after
   every section label and bullet list, or build ADF directly) so labels like
   `Decisions:`/`Next:` don't get absorbed into the preceding bullet. **Per-ticket
   failures are isolated** — one ticket's 404 / permission error does not abort the
   others.

## 6. Report

Print a per-ticket ✓/✗ table (comment links for successes, reasons for failures) + the
scratch result, offer to retry any failed tickets within this same invocation (the scratch
is already safe; a new invocation would overwrite it), and
note it's safe to `/clear`.

## 7. Mark the session handed off (for the statusLine indicator)

After a successful Report — whether full Jira-writing or local-only — write the current
epoch seconds to `.bitacora/last-handoff` in the project root. Create `.bitacora/` if it
does not exist. This marker is read by the opt-in Bitácora statusLine to clear the
`✎ handoff pending` segment. Resetting the clock on local-only handoffs is harmless and
keeps the indicator from going stale forever on Jira-less work. Skip silently if the
working directory is not a git repo (no `.git`) — the indicator is git-scoped, and there
is nothing for it to read in that case.

Exact command:

```bash
[ -d .git ] && { mkdir -p .bitacora && date +%s > .bitacora/last-handoff; } || true
```

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** treat exactly like the
  no-ticket path — skip the Jira half gracefully, complete the local scratch, report the
  reason. **No retry loop.**
- **Ticket 404 / 403 / no write permission:** surface for that ticket, keep its draft,
  offer retry with a different key or skip; other tickets unaffected. (`getJiraIssue`
  may succeed while `addCommentToJiraIssue` returns 403 — Jira's project-level comment
  permission is a distinct grant from view permission.)
- **Empty/trivial session:** say "nothing substantive to hand off" and write nothing
  unless the user insists.
- **Remember unavailable:** warn, print the scratch for manual save, still offer the Jira
  writes.
- Re-running in one session writes a new `[CTX]` per ticket (one per logical update is
  fine); the continuity-read avoids restating `Done`.

## Configuration

`project_key_pattern` and the compliance modes come from the `bitacora:jira-comment-format`
skill's Configuration section. Handoff adds two optional keys (same override files —
`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is normal):

```yaml
session_ticket_tracking:
  enabled: true                 # multi-ticket handoff awareness
  source: reconstruct           # reconstruct | recorder  (recorder = Phase 1.5 hook)
  attribution: branch_name      # touched-ticket → branch mapping strategy
  # activity_threshold: <n>     # Phase 1.5 — substantive-vs-incidental auto-filter; v1 shows all
jira_cloud_id: ""               # optional; if set, skips the multi-site select prompt
```
