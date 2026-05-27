# statusLine "handoff pending" indicator — design

**Date:** 2026-05-27
**Status:** Approved design. Implementation deferred — this is a sub-feature of **Phase 6 (statusLine)**, which is "build last."
**Depends on:** the Phase 6 statusLine script (`statusline/statusline.sh`) existing.

## Problem

When a session fills the context window, the right move is `/clear` and resume. But
clearing *before* running `/bitacora:handoff` loses the curated handoff note — the
`remember.md` briefing is never written, so the next session starts from the raw
auto-saved transcript instead of a clean summary. There is currently no visible cue that
you have un-handed-off work when you reach for `/clear`.

## Goal

A status-bar indicator that appears when there is unsaved Jira-ticket work, nudging the
user to run `/bitacora:handoff` before clearing.

## Non-goals

- **Not context-gated.** It shows on *any* unsaved Jira work, independent of context level
  (decided during brainstorming). Context-pressure escalation is an optional visual cue only.
- **Does not block `/clear`.** Purely a visual nudge; no enforcement.
- **Does not call Jira.** The statusLine renders constantly; a network call per render
  would lag the terminal. Detection is local (git + a marker file) only.

## Decisions (locked during brainstorming)

| Decision | Choice |
|----------|--------|
| When the icon appears | On unsaved Jira work, regardless of context level |
| What counts as "Jira work" | On a branch whose name matches `project_key_pattern`, **and** there is a commit or working-tree edit since the last handoff |
| Detection mechanism | Stateless: git state + a handoff timestamp marker (no per-tool hook) |
| Appearance | Explicit label `✎ handoff pending`; absent when clean |

## Architecture

Only two touch points:

1. **`statusline/statusline.sh`** — adds one segment and a pure decision function.
2. **`/bitacora:handoff`** — on successful completion, writes the marker `.bitacora/last-handoff`.

```
/bitacora:handoff ──writes──▶ .bitacora/last-handoff (epoch ts)
                                        │
                                        ▼ reads
git working tree / log ──────▶ statusline.sh ──renders──▶ "✎ handoff pending"
```

## Detection logic (each render, git-only)

```
branch = current git branch
if branch does NOT match project_key_pattern   → no indicator        (not ticket work)
marker_ts = contents of .bitacora/last-handoff  (0 if file absent)
tree_dirty     = `git status --porcelain` is non-empty            (uncommitted edits)
last_commit_ts = `git log -1 --format=%ct`                        (0 if no commits)
dirty = tree_dirty OR (last_commit_ts > marker_ts)
if dirty → render the "✎ handoff pending" segment
```

The decision is factored into a **pure function** so it is unit-testable without a real repo:

```
handoff_pending(is_ticket_branch, tree_dirty, last_commit_ts, marker_ts) -> bool
  = is_ticket_branch AND (tree_dirty OR last_commit_ts > marker_ts)
```

`statusline.sh` gathers the four inputs from git/filesystem and calls this function. This
mirrors the existing `validate-ctx.sh` pattern (pure classifier + thin I/O wrapper).

## The marker

- Path: `.bitacora/last-handoff` (project root). `.bitacora/` is gitignored.
- Contents: a single epoch-seconds timestamp.
- Written by `/bitacora:handoff` on **successful completion** (after the writes in step 5/6),
  including local-only handoffs (resetting the clock is harmless when there were no tickets).
- `project_key_pattern` and the `.bitacora/` location are shared with the
  `jira-comment-format` skill's configuration.

## Appearance & placement

Appended after the context meter; absent when clean:

```
bitácora  AT-4104  ·  ctx ██████░░ 64%  ·  ✎ handoff pending
```

**Optional escalation (nice-to-have, deferred to implementation):** when context is also
past the 85% shape-shift threshold, render the segment bold/colored — it is most urgent
exactly when the user would clear. The icon still shows below that threshold.

## Configuration

- Reuses `project_key_pattern` from the `jira-comment-format` skill (same regex used for
  ticket detection elsewhere; user-overridable).
- `statusline.handoff_indicator: true` — toggle to disable the segment.

## Edge cases

| Situation | Behavior |
|-----------|----------|
| Not a git repo / detached HEAD / non-ticket branch | Indicator absent |
| No marker file yet (never handed off) | `marker_ts = 0` → any work on a ticket branch shows it (correct: you haven't handed off) |
| Branch switching / multiple tickets in a session | Time-based `marker_ts` handles it — any commit after the marker on any ticket branch counts |
| Ticket branch, clean tree, no commit since handoff | Clean → absent |
| git command error / timeout | Fail-safe to **absent** — never break or hang the status bar (wrap git calls in a short timeout) |

## Testing

`test-statusline-handoff.sh` driving the pure function (no real repo needed for the core):

- ticket branch + dirty tree → on
- ticket branch + commit newer than marker → on
- ticket branch + clean + no new commit → off
- non-ticket branch → off
- no marker + work present → on
- not a git repo → off (I/O wrapper level)

## Dependencies & sequencing

- Sub-feature of **Phase 6 (statusLine)** — implement when that phase is built.
- The only part that could ship earlier is the marker-write in `/bitacora:handoff`; it is
  harmless on its own (writes a file nothing yet reads).
- No blocking open questions. Escalation styling is the only deferred detail.
