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
and `/bit:help` run the same workflows as their `/bitacora:…` forms.

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

Then add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/bitacora/statusline.sh"
  }
}
```

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

## The `[CTX]` format

See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](../../docs/JIRA_AGENT_COMMENT_FORMAT.md). The
operational source of truth is the `jira-comment-format` skill; `scripts/validate-ctx.sh`
classifies any comment as `compliant` / `malformed` / `not-in-format`.

## Safety

Draft → show → confirm → write, always. No auto-update, no telemetry. Local scratch is
written first so Jira-write failures never lose mid-task detail.
