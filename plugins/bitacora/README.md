# Bitácora (plugin)

Jira-aware workflow layer for Claude Code. **Phase 1 (shipped):** `/bitacora:handoff`,
`/bitacora:resume`, `/bitacora:status`, `/bitacora:next`, `/bitacora:help`, an opt-in
statusLine context meter, and the `[CTX]` comment-format discipline. Every bit of
context, logged.

## Integrations

Bitácora runs on Claude Code alone. Both integrations below are **optional** — each one
enriches the handoff, and the workflow degrades gracefully when it's missing.

- **Remember** plugin (local session memory) — handoff delegates the consolidated local
  scratch to it. Without it, the scratch is printed to screen for you to save manually.
- **Atlassian Rovo MCP** with read/write to your Jira — for writing the `[CTX]` comments.
  Without it, handoff runs local-only: it still drafts and shows each comment, it just
  skips the Jira write.

## Commands

| Command | What it does |
|---------|--------------|
| `/bitacora:handoff [KEYS...]` | Reconstruct the Jira tickets touched this session, draft a `[CTX]` status comment for each (confirm before writing), and save one consolidated local scratch via Remember. Pass ticket keys to force the set. |
| `/bitacora:resume [KEY]` | Rehydrate a fresh session from a ticket's latest `[CTX]`: read its `Status` / `Decisions` / `Next` back into context after a `/clear` and print a compact, read-only briefing. Pass a key to target a ticket; otherwise resolved from the branch. |
| `/bitacora:status [KEY] [--for-pm\|--for-eng\|--for-self]` | Synthesize a ticket's latest `[CTX]` into an audience-tailored summary (default `--for-self`): different sections foregrounded and a different voice per mode. Read-only — prints the summary and offers a clipboard copy. |
| `/bitacora:next` | Morning ticket picker: query the tickets assigned to you, categorize into Continue / Ready / Quick wins + a Needs-attention tail, annotate each with a `[CTX]`-grounded reason-to-pick, recommend one, and chain into `/bitacora:resume <KEY>`. Read-only. |
| `/bitacora:improve` | Sharpen a ticket — read the ticket plus its `[CTX]` trail, free-form comments, local Remember scratch, and git/PR history; produce a type-aware structured rewrite (Story / Bug / Epic / Subtask) with confident engineering choices labeled as `Assumptions`; snapshot the pre-state to an `[ARCHIVE]` comment, then edit the description (and optionally the title) in place. |
| `/bitacora:help` | Print the Bitácora command reference. |

## Optional: the shorter `/bit:` alias

Command namespace equals the plugin name, so commands are `/bitacora:…` by default.
For the shorter `/bit:…` forms, copy the bundled aliases into your personal commands
dir (one-time, per machine):

```bash
mkdir -p ~/.claude/commands/bit
alias_file="$(find ~/.claude/plugins -path '*bitacora/alias/bit-handoff.md' | head -1)"
if [ -z "$alias_file" ]; then
  echo "bitacora alias dir not found — is the plugin installed?" >&2
else
  for f in "$(dirname "$alias_file")"/bit-*.md; do
    cp "$f" ~/.claude/commands/bit/"$(basename "$f" | sed 's/^bit-//')"
  done
fi
```

This copies every bundled alias (the `bit-` prefix is stripped to form the
command name). Then `/bit:handoff`, `/bit:resume`, `/bit:status`, `/bit:next`,
`/bit:improve`, and `/bit:help` run the same workflows as their `/bitacora:…` forms.

You only run this **once**. After `~/.claude/commands/bit/` exists, the plugin keeps
it in sync for you: a `SessionStart` hook (`scripts/sync-bit-aliases.sh`) re-copies the
bundled aliases at the start of each session, so any alias shipped in a later release
shows up automatically (on the next session) — no need to re-run the snippet. The hook
is **opt-in and additive**: it does nothing until that dir exists, and it only adds or
updates files, never deletes them.

## Optional: the statusLine

A single-line Claude Code statusLine that shows what ticket/branch you're on, how full
your context window is, and whether you have un-handed-off ticket work. Bolds + reds at
≥85% context — the moment to run `/bitacora:handoff` then `/clear` + `/bitacora:resume`.

```
AT-4104  ·  ctx ██████░░ 76%  ·  ✎ handoff pending
```

Opt in once (per machine):

```bash
mkdir -p ~/.claude/bitacora
src_file="$(find ~/.claude/plugins -path '*bitacora/statusline/statusline.sh' | head -1)"
if [ -z "$src_file" ]; then
  echo "bitacora statusline not found — is the plugin installed?" >&2
else
  cp "$(dirname "$src_file")"/*.sh ~/.claude/bitacora/
fi
```

Then **merge** this `statusLine` block into `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"$HOME\"/.claude/bitacora/statusline.sh"
  }
}
```

⚠️ **Don't overwrite the file.** After `/plugin install bitacora@bitacora`, the file already contains `extraKnownMarketplaces` and `enabledPlugins` entries that Claude Code needs to keep the plugin loaded. A heredoc that replaces the whole file will silently break the install. Use `jq` to add the key in place:

```bash
jq '.statusLine = {"type": "command", "command": "\"$HOME\"/.claude/bitacora/statusline.sh"}' ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
```

(Shell single-quotes around the jq program prevent `$HOME` from expanding at the bash level — jq writes the literal `"$HOME"` string so Claude Code itself expands it at statusLine-call time.)

If `~/.claude/settings.json` doesn't exist yet (rare — you'd have to opt in *before* installing), create it with just the `statusLine` block above.

After opt-in, a `SessionStart` hook keeps the scripts in sync at `~/.claude/bitacora/`
so future plugin releases pick up automatically — no need to re-run the snippet.

**Caveats**

- **Claude Code permits exactly one `statusLine.command`** — installing this **replaces**
  any existing statusLine. Wrap our script if you have your own (unsupported in v1).
- The `✎ handoff pending` segment appears only on ticket branches (`PROJ-1234`-style names)
  with unsaved work since the last `/bitacora:handoff`.
- Set `NO_COLOR=1` to disable ANSI; a `⚠ ` prefix substitutes at the escalation threshold.
- Per-segment toggles via env vars: `BITACORA_SHOW_BRANCH`, `BITACORA_SHOW_METER`,
  `BITACORA_SHOW_HANDOFF`, `BITACORA_THRESHOLD` (default `85`).

## Optional: the handoff guardrail hook

A Claude Code `UserPromptSubmit` hook that intercepts `/clear` and `/compact` when
Bitácora detects pending handoff work on the current ticket branch, prints a clear
action-oriented message suggesting `/bitacora:handoff`, and exposes a one-shot
escape hatch via a `.bitacora/skip-handoff-once` marker file. The friction it
catches: typing `/clear` to recover from context pressure without first writing the
`[CTX]` comment that would have shared the session's outcomes with teammates.

The hook only blocks when **all** of these hold:

- The prompt body starts with `/clear` or `/compact` (after trimming leading whitespace).
- The current directory is inside a git repository.
- The current branch matches a project-key pattern (e.g. `PROJ-1234`).
- Bitácora's existing handoff-pending check (the same one the statusLine uses) is true.

Anything else → silent no-op. The hook also exits silently (fail-open) on any
infrastructure trouble — missing `jq`, missing source files, hook timeouts, malformed
input — so it can never brick a `/clear` you genuinely needed.

Opt in once (per machine):

```bash
mkdir -p ~/.claude/bitacora  # already exists if the statusLine is installed
src_file="$(find ~/.claude/plugins -path '*bitacora/scripts/precompact-handoff-check.sh' | head -1)"
if [ -z "$src_file" ]; then
  echo "bitacora hook not found — is the plugin installed?" >&2
else
  cp "$src_file" ~/.claude/bitacora/
  chmod +x ~/.claude/bitacora/precompact-handoff-check.sh
fi
```

Then **merge** the hook into `~/.claude/settings.json`. The shape to add:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME\"/.claude/bitacora/precompact-handoff-check.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

⚠️ **Don't overwrite the file** — see the warning under [Optional: the statusLine](#optional-the-statusline). The same `jq`-in-place pattern works:

```bash
jq '.hooks.UserPromptSubmit = [{"hooks":[{"type":"command","command":"bash \"$HOME\"/.claude/bitacora/precompact-handoff-check.sh","timeout":5}]}]' ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
```

If you already have a different `UserPromptSubmit` hook chain, append to it rather than replacing — `jq '.hooks.UserPromptSubmit += [...]'` instead of `=`.

After opt-in, the same `SessionStart` hook that syncs the statusLine scripts also
keeps `precompact-handoff-check.sh` in sync at `~/.claude/bitacora/` — no need to
re-run the snippet on plugin updates.

**Bypassing the check:**

- **One attempt:** `touch .bitacora/skip-handoff-once` and re-issue `/clear`. The
  marker is consumed on use; the next `/clear` with pending work fires the check
  again.
- **Permanent:** remove the `UserPromptSubmit` entry from `~/.claude/settings.json`.

**Caveats**

- **Plugin-side activation also exists.** Installing the plugin via Claude Code's
  plugin system activates the hook automatically via `hooks/hooks.json`. The
  manual `settings.json` route above is for users who want to install just the
  hook (without the rest of the plugin) or who want per-machine control.
- **The hook does not catch auto-compact.** Auto-compact preserves context
  (it summarises), so handoff is not actually at risk. Manual `/compact` is
  caught by the same `/clear` matcher.
- **`jq` is required.** If `jq` isn't on PATH the hook fails open and prints a
  one-line `bitacora: jq not on PATH; handoff guardrail disabled` note to stderr.
  `/clear` proceeds and the handoff is lost. Same dependency as the statusLine.
- **Project key pattern is fixed.** The hook recognises tickets matching the
  default `[A-Z][A-Z0-9]+-[0-9]+` pattern (e.g. `PROJ-1234`, `AT-4539`) only.
  The skills honour a `project_key_pattern` override in
  `${CLAUDE_PROJECT_DIR}/.bitacora.yml`, but the hook does not — it has no yaml
  parser baked in. If your team uses lowercase or non-standard alphanumeric
  keys, the guard will silently skip and `/clear` will proceed unchecked.
  Tracked in [#64](https://github.com/fr1j0/bitacora/issues/64) as a future
  enhancement.

## The `[CTX]` format

See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](../../docs/JIRA_AGENT_COMMENT_FORMAT.md). The
operational source of truth is the `jira-comment-format` skill; `scripts/validate-ctx.sh`
classifies any comment as `compliant` / `malformed` / `not-in-format`.

## Safety

Draft → show → confirm → write, always. No auto-update, no telemetry. Local scratch is
written first so Jira-write failures never lose mid-task detail.
