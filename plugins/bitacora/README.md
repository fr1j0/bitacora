# Bitácora (plugin)

Jira-aware workflow layer for Claude Code. **Phase 1:** `/bitacora:handoff` and the
`[CTX]` comment-format discipline. Every bit of context, logged.

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
| `/bitacora:help` | Print the Bitácora command reference — shipped commands and the planned roadmap. |

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
command name), so any alias shipped in a later release is picked up by re-running
the snippet — no need to edit it. Then `/bit:handoff`, `/bit:resume`, `/bit:status`, and
`/bit:help` run the same workflows as their `/bitacora:…` forms.

## The `[CTX]` format

See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](../../docs/JIRA_AGENT_COMMENT_FORMAT.md). The
operational source of truth is the `jira-comment-format` skill; `scripts/validate-ctx.sh`
classifies any comment as `compliant` / `malformed` / `not-in-format`.

## Safety

Draft → show → confirm → write, always. No auto-update, no telemetry. Local scratch is
written first so Jira-write failures never lose mid-task detail.
