# Handoff guardrail hook — design

An opt-in Claude Code hook that intercepts `/clear` and `/compact` when Bitácora
detects pending handoff work, blocks the action, and tells the user how to either
preserve the work (`/bitacora:handoff`) or explicitly bypass the check
(`.bitacora/skip-handoff-once` marker file). Catches the specific failure mode
identified by the 2026-05-29 UX-flow review: the engineer forgets to run
`/bitacora:handoff` before `/clear`, the live context wipes, and the Jira `[CTX]`
write that would have shared the session's outcomes with teammates never lands.

This was originally framed as a "PreCompact handoff hook" in the friction list;
brainstorming exposed that the right Claude Code event is `UserPromptSubmit`, not
`PreCompact` (`/clear` is a user-submitted prompt, not a compaction). Naming follows
the actual surface area, not the original misnomer.

## Problem

`/clear` wipes the live context window unconditionally. Bitácora's handoff is the
only mechanism that turns the about-to-be-lost session state into a durable, shared
artifact (a `[CTX]` Jira comment + a Remember scratch capture). The statusLine
already shows a `✎ handoff pending` indicator when there's unsaved work, but a
passive indicator is easy to miss in the moment — especially under the kind of
context-window pressure that drives an engineer to `/clear` in the first place.

The cost of missing the indicator is asymmetric:

- **Run handoff before /clear** → Jira ticket carries the narrative; the next
  session resumes cleanly; teammates can read the state asynchronously.
- **Skip handoff and /clear anyway** → the session's outcomes are gone from any
  shared surface. The next session has no `[CTX]` to resume from. Teammates
  don't know what changed. The work happened but it's invisible.

A guardrail that pauses on `/clear` when handoff is pending — with a clear path to
either resolve or bypass — is the only intervention that actually prevents the
loss. Soft warnings duplicate what the statusLine already does; hard auto-handoff
breaks Bitácora's draft → show → confirm → write voice.

## Goal

Ship a single shell script (`precompact-handoff-check.sh` — keeping the misnomer in
the filename for searchability) plus one `UserPromptSubmit` hook entry in the
plugin's `hooks.json`. When the script detects `/clear` or `/compact` *and* handoff
is pending, it returns a JSON block with a specific, action-oriented system message
and `decision: block`. When either condition fails, it exits silently.

The hook is opt-in (same install footprint as the statusLine: copy the script into
`~/.claude/bitacora/`, add a `hooks` entry to `~/.claude/settings.json`), and the
plugin's existing SessionStart sync mechanism keeps the installed copy up to date
with the bundled version.

## Prerequisites

- **Claude Code's `UserPromptSubmit` hook event.** The hook reads stdin JSON
  containing the user's prompt, and can return JSON to block the prompt and inject
  a system message. Standard Claude Code surface; no new permissions.
- **The plugin's existing `handoff-pending.sh` decision function**
  (`plugins/bitacora/statusline/handoff-pending.sh`) — pure decision function the
  statusLine already uses. We reuse it as-is to keep "is there pending work?" a
  single source of truth across the statusLine, the new hook, and any future
  consumer.
- **Bash 3.2+** (macOS's system `bash`; same constraint as every other Bitácora
  script).
- **`jq` is not required.** The hook reads its tiny stdin input with shell-only
  techniques (the `prompt` field is the only thing we extract; bash plus a sed
  fallback is sufficient).

## Non-goals (YAGNI)

- **No `PreCompact` subscription.** Auto-compact preserves context (it summarizes,
  it does not wipe), so handoff is not actually at risk. Manual `/compact` is
  caught by the same `UserPromptSubmit` matcher as `/clear`.
- **No `SessionStart trigger="clear"` "regret note".** The statusLine's
  `✎ handoff pending` segment already renders on the very next prompt after
  `/clear` if work is still pending. Adding a one-time SessionStart system message
  would duplicate the signal. Revisit if real users report missing the statusLine
  cue.
- **No auto-run of `/bitacora:handoff` from inside the hook.** Paternalistic;
  breaks the draft → show → confirm → write voice; the user explicitly declined
  this during brainstorming. The hook *guides* the user to run handoff; it does
  not *perform* handoff.
- **No customizable block message in v1.** The string is in the shell script;
  teams that want a different tone can fork or edit. Adding
  `.bitacora.yml → hook.block_message` is a follow-up if anyone asks.
- **No env-var silencer** (e.g. `BITACORA_SKIP_HANDOFF_CHECK=1`). The marker file
  covers the per-attempt case; removing the `settings.json` entry covers the
  per-machine case. Two stages, both discoverable, no third hidden lever.
- **No `Stop` subscription.** Stop fires more broadly than `/clear` (including
  per-turn stops in some Claude Code variants); using it as the trigger would
  risk hook noise on every turn. `UserPromptSubmit` with a strict prefix match
  catches exactly what we need.

## Design

Single new script, single hook entry, two small additions to the existing
SessionStart sync hook, and an installation snippet in the plugin README.

### New files

- `plugins/bitacora/scripts/precompact-handoff-check.sh` — the hook itself. Reads
  JSON from stdin, decides whether to block, emits JSON on stdout when blocking.
- `plugins/bitacora/scripts/test-precompact-handoff-check.sh` — assertion harness
  for the decision matrix (matches `/clear`, matches `/compact`, ignores
  unrelated prompts, consumes marker file, fails open on git errors, etc.).

### Edited files

- `plugins/bitacora/hooks/hooks.json` — add a new top-level event entry
  `UserPromptSubmit` whose `hooks` list invokes the new script. (Existing
  `SessionStart` entries are unchanged.)
- `plugins/bitacora/scripts/sync-statusline.sh` — extend by one block to also
  copy `precompact-handoff-check.sh` into `~/.claude/bitacora/` *if that dir
  already exists*. Same opt-in / additive pattern the existing sync uses for the
  statusline scripts.
- `plugins/bitacora/scripts/test-sync-statusline.sh` — add an assertion that the
  hook script is also copied when present.
- `plugins/bitacora/README.md` — add a new "Optional: the handoff guardrail hook"
  subsection after the statusLine subsection. Same shape as the statusLine
  install snippet (one-time copy + `settings.json` edit + note about auto-sync).
- `plugins/bitacora/commands/help.md` and `alias/bit-help.md` — no change. The
  help block lists commands, not hooks. Hooks live in the plugin README.
- `.github/workflows/test.yml` — no change. The shell-tests matrix already picks
  up new `test-*.sh` files via the existing per-script step pattern.

  *(Note for the implementer: confirm during T-final that the new test script is
  wired into `test.yml` — the workflow currently lists each test script by name,
  so a new step needs to be added.)*

### Workflow (the hook script)

The script runs synchronously on every `UserPromptSubmit` event. Most invocations
exit silently in well under 5ms. Decision flow:

```
1. Read stdin JSON. If parse fails or no `prompt` field present → exit 0.
2. Extract the trimmed-leading-whitespace prefix of the prompt body.
3. If it does not match `/clear` or `/compact` (allowing optional trailing
   args) → exit 0. Vast majority of turns terminate here.
4. Check for the marker file `.bitacora/skip-handoff-once` in $PWD's repo root.
   If present → `rm` it and exit 0. /clear proceeds.
5. Detect git context:
   - Run `git rev-parse --is-inside-work-tree`. If non-zero → exit 0 (not in a
     repo; fail-open).
   - Run `git branch --show-current` to get the branch name. If no
     `project_key_pattern` match → exit 0 (not a ticket branch; nothing to hand
     off about).
   - Gather `tree_dirty`, `last_commit_ts`, `marker_ts` (the same four inputs
     the statusLine gathers).
6. Source `~/.claude/bitacora/handoff-pending.sh` (synced into place by
   `sync-statusline.sh`).
7. Call `handoff_pending "$is_ticket" "$tree_dirty" "$last_commit_ts" "$marker_ts"`.
   If it returns false (1) → exit 0. Nothing to block.
8. If it returns true (0) → emit the block JSON to stdout and exit 0:

   {
     "decision": "block",
     "stopReason": "<the rendered block message from 'Block message format' below>",
     "hookSpecificOutput": {
       "hookEventName": "UserPromptSubmit",
       "additionalContext": "Bitácora blocked /clear: handoff pending on <KEY>. The user should run /bitacora:handoff or touch .bitacora/skip-handoff-once before retrying."
     }
   }

   Exit 0 because the hook itself succeeded; the `decision: block` field is what
   tells Claude Code to suppress the prompt. The `additionalContext` line is
   what the *next* turn's model sees as a system reminder — useful when the
   user, instead of running `/bitacora:handoff`, types something off-script
   (a question, a code edit). The model sees the context and can remind the
   user about the pending handoff.
```

The hook never exits non-zero on its own logic; non-zero exits are reserved for
infrastructure failures (missing bash, missing source file). In every "should I
do nothing?" branch, the script exits 0 silently — never blocks `/clear` on
infrastructure trouble (fail-open).

### Block message format (rendered to the user)

```
Bitácora: handoff pending on <KEY>.
  · <N> commit(s) since the last handoff marker
  · uncommitted changes in the working tree   [if dirty]

To preserve this session in Jira:
    /bitacora:handoff

To bypass this check for one /clear:
    touch .bitacora/skip-handoff-once
    /clear
```

The bullets render only when the corresponding condition holds: the "commits
since last handoff" line appears when `last_commit_ts > marker_ts`; the
"uncommitted changes" line appears when `tree_dirty` is true.

### Prompt matching rules

Strict, to avoid false positives:

- Trim leading whitespace from the prompt body.
- Match against `^/clear($|[[:space:]])` and `^/compact($|[[:space:]])`.
- `/clear`, `/clear   `, `/clear --some-arg` → match.
- `/clear-something`, `let me clear my mind`, `# /clear (in a code block)` → no match.

### Configuration (.bitacora.yml)

Reuses `project_key_pattern` from `bitacora:jira-comment-format`. No new
configuration keys. The hook's behavior is binary (block when pending, silent
otherwise); the escape hatches (`.bitacora/skip-handoff-once`, removing the
`settings.json` entry) are the only knobs.

### Installation surface (per the plugin README)

Mirrors the statusLine install pattern. Opt-in is two steps the user runs once
per machine:

```bash
mkdir -p ~/.claude/bitacora  # already exists if statusLine is installed
src_file="$(find ~/.claude/plugins -path '*bitacora/scripts/precompact-handoff-check.sh' | head -1)"
if [ -z "$src_file" ]; then
  echo "bitacora hook not found — is the plugin installed?" >&2
else
  cp "$src_file" ~/.claude/bitacora/
  chmod +x ~/.claude/bitacora/precompact-handoff-check.sh
fi
```

Then add the hook entry to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/bitacora/precompact-handoff-check.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

After opt-in, the existing `SessionStart` `sync-statusline.sh` hook (which the
user already has installed if they're using the statusLine) keeps
`precompact-handoff-check.sh` in sync with the bundled version. Same additive,
opt-in semantics: it does nothing if `~/.claude/bitacora/` doesn't exist; it
never deletes files; it always exits 0 so a SessionStart hook can never break a
session.

**Plugin-side hook declaration** (in `plugins/bitacora/hooks/hooks.json`) — for
the in-plugin install path (when the user enables the plugin via Claude Code's
plugin system rather than the manual copy):

```json
{
  "hooks": {
    "SessionStart": [
      { ... unchanged existing entries ... }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/precompact-handoff-check.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Two install paths (in-plugin via `hooks.json`, manual via `settings.json`) are
intentional: the in-plugin path activates the hook for any user who enables the
plugin (no extra step), while the manual path is the existing escape route for
users who want fine-grained control (or who want to install just the hook
without the rest of the plugin).

### Failure modes

- **Hook script timeout (5s ceiling)** → Claude Code proceeds with the prompt.
  `/clear` happens. The user loses the handoff. Acceptable: infrastructure
  trouble should not block work. Mitigation: the script's hot path is
  `git rev-parse` + `git branch --show-current` + a few `stat` calls, well
  inside 5s.
- **Malformed JSON output from the script** → Claude Code's hook plumbing falls
  back; the prompt proceeds. Acceptable; same fail-open posture.
- **`handoff-pending.sh` not sourceable** → the `.` invocation fails. The script
  exits 0 (fail-open) rather than blocking, since handoff-pending status cannot
  be determined.
- **Marker file present but read-only directory** → `rm` fails, marker survives.
  The next /clear would also pass (marker still consumes). Mitigation: this is
  a degenerate case the user can resolve by manually deleting the marker.
- **`~/.claude/bitacora/` does not exist** (no opt-in to statusLine, no opt-in
  to the hook) → the `command` in `settings.json` is never installed in the
  first place, so the hook never runs. The hook is opt-in; absence is a no-op
  by construction.

### Edge cases

- **`/clear` invoked on `main` (non-ticket branch)** → no `project_key_pattern`
  match; hook exits silently. `/clear` proceeds.
- **`/clear` invoked outside any git repo** → `git rev-parse` fails; hook exits
  silently.
- **User opts in but never runs `/bitacora:handoff`** → every `/clear` blocks
  until they hand off or touch the marker. By construction, this is the
  intended behavior — the hook exists precisely to make this case visible.
- **Marker file committed to git accidentally** → `.bitacora/` should already
  be in `.gitignore` (the statusLine tests rely on this). Plugin README's
  install notes will reinforce this. If a user does commit it, the marker is
  consumed on first use anyway.
- **User on a worktree, not the main checkout** → `git rev-parse
  --is-inside-work-tree` succeeds; the rest of the gather works against the
  worktree's HEAD. Hook behaves correctly.

## Decisions

- **`UserPromptSubmit`, not `PreCompact` or `Stop`.** `PreCompact` does not fire
  on `/clear`; `Stop` fires too broadly (every turn-stop in some Claude Code
  variants). `UserPromptSubmit` with a strict prefix match catches exactly the
  user-driven `/clear` and `/compact` actions we want to intercept.
- **Block + suggest, not soft-warn.** Soft-warn would duplicate the statusLine's
  `✎ handoff pending` indicator. Hard block is the only intervention that
  actually prevents the loss.
- **Block + suggest, not block + auto-run.** The user explicitly declined the
  auto-run pattern; it would break draft → show → confirm → write.
- **Marker file as the escape hatch, not env var.** The marker can be created
  from inside Claude Code via the `!` shell escape; an env var would require
  the user to leave Claude Code, export the var, and re-launch.
- **Per-attempt marker, not per-session silence.** Per-session silence is a
  footgun: the user silences once and forgets to re-enable, then loses a
  subsequent session. One-shot marker keeps the guardrail honest.
- **Two install paths (in-plugin `hooks.json` + manual `settings.json`),
  intentionally.** The in-plugin path is the default; the manual path lets
  users opt in to just the hook without the rest of the plugin, or opt out of
  the hook while keeping other plugin features.
- **Reuse `handoff-pending.sh` as-is.** Single source of truth for "is there
  pending work?" across the statusLine, the hook, and any future consumer. No
  duplication.
- **Fail-open everywhere.** Every error path — bad JSON, missing source file,
  git not in path, timeout — proceeds with `/clear`. The hook is a guardrail,
  not a kernel lock. Better to occasionally lose a handoff than to occasionally
  brick the user's session.
- **Filename keeps the original misnomer `precompact-handoff-check.sh`.** The
  friction was originally titled "PreCompact handoff hook"; preserving the
  filename helps find the script via memory / docs even though the chosen
  event is `UserPromptSubmit`. The spec body explains the mismatch.

## Testing / verification

The script has real shell logic and edge cases, so it ships with a test harness
parallel to `test-validate-ctx.sh` / `test-statusline.sh`. Run via
`plugins/bitacora/scripts/test-precompact-handoff-check.sh`.

### Test cases (each as an inline assertion in the harness)

1. **No match, no block** — feed a prompt like `tell me a joke`; assert the
   script exits 0 and emits no output.
2. **`/clear` with no pending work** — inside a clean repo on a ticket branch,
   feed `/clear`; assert exit 0, no output.
3. **`/clear` with dirty tree on a ticket branch** — uncommitted changes
   present; feed `/clear`; assert the script emits JSON with
   `decision: "block"` and the message names the ticket key.
4. **`/clear` with commits since marker on a ticket branch** — commits added
   since `.bitacora/last-handoff`; feed `/clear`; assert block + correct count.
5. **`/clear` on `main`** — non-ticket branch; feed `/clear`; assert exit 0,
   no output even with dirty tree.
6. **`/clear` outside any git repo** — `cd /tmp`; feed `/clear`; assert exit
   0, no output.
7. **Marker file present** — touch `.bitacora/skip-handoff-once` with pending
   work; feed `/clear`; assert exit 0, no output, marker file gone after.
8. **`/compact` matches** — same setup as case 3, with `/compact` instead of
   `/clear`; assert block.
9. **`/clear-foo` does not match** — assert exit 0, no output.
10. **Prompt with leading whitespace** — `   /clear`; assert match.
11. **Empty stdin** — feed empty input; assert exit 0, no output (graceful
    handling of malformed input).
12. **Malformed JSON stdin** — feed `not json`; assert exit 0, no output.

### Adjunct checks

- `test-sync-statusline.sh` gains one assertion that
  `precompact-handoff-check.sh` is copied into the dest dir when the source is
  available.
- `.github/workflows/test.yml` gains one step running
  `test-precompact-handoff-check.sh` on both `ubuntu-latest` and
  `macos-latest`.
- ShellCheck (via the existing `lint` job) covers the new script with
  `--severity=warning`.

### Live acceptance test (per spec, eyeball after merge)

- On a ticket branch with uncommitted changes, type `/clear` in a Claude Code
  session. Confirm the block message appears with the right ticket key, commit
  count, and dirty-tree note.
- Run `/bitacora:handoff` (or touch the marker). Re-issue `/clear`. Confirm
  the second attempt proceeds.
- On `main` with no ticket-key match, type `/clear`. Confirm no interception.
- Disable the plugin / remove the `settings.json` hook entry. Confirm `/clear`
  works unimpeded.

## Notes for the implementer

- The filename `precompact-handoff-check.sh` deliberately preserves the
  original friction-list name even though the chosen event is
  `UserPromptSubmit`. Do not rename to `userpromptsubmit-handoff-check.sh` or
  similar; the spec body documents the mismatch.
- The script's hot path (when the prompt does not match `/clear`/`/compact`)
  must be cheap. Aim for < 5ms wall-clock on a typical macOS machine. Avoid
  invoking `git` or any subprocess in the non-matching path.
- `handoff-pending.sh` is sourced via the user's `~/.claude/bitacora/` copy
  (synced by `sync-statusline.sh`), NOT from `${CLAUDE_PLUGIN_ROOT}`. The
  script's install path is `~/.claude/bitacora/`, so its sibling source file
  must be there too. This is why the install snippet copies the script into
  the same dir.
- When emitting the block message, use real Unicode characters (em-dash U+2014,
  middle dot U+00B7) consistent with the rest of the Bitácora prose. No ASCII
  fallbacks.
- The hook output JSON should be a single line (or use minimal whitespace) to
  ease the test harness's assertions.
