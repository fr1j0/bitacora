# `/bitacora:help` — Command Reference

**Date:** 2026-05-27
**Status:** Approved (design)

## Problem

Bitácora has no command that lists what it offers. Claude Code's built-in `/`
menu and global `/help` exist, but neither answers "what does *this plugin* give
me and how do I run it." A plugin-specific quick reference closes that gap.

## Goal

Add `/bitacora:help` (with an opt-in `/bit:help` alias) that prints a curated,
static command reference: shipped commands with syntax, plus the planned ones as
a roadmap.

## Non-goals

- No `[CTX]` format primer (that belongs in the README / `jira-comment-format` skill).
- No integration/degradation status (Remember, Atlassian MCP).
- No dynamic enumeration of `commands/` — the block is hand-curated.

## Design

### New files

1. **`plugins/bitacora/commands/help.md`** — registers `/bitacora:help`.
   Frontmatter `description`; body instructs the model to print the help block
   below **verbatim**, with no tool calls and no enumeration.

2. **`plugins/bitacora/alias/bit-help.md`** — opt-in `/bit:help`, mirroring the
   existing `alias/bit-handoff.md` pattern (the user copies it into
   `~/.claude/commands/bit/` if they want the short form). Same delegating style:
   instructs the model to print the same block.

### Edited files

3. **`plugins/bitacora/README.md`** — add a `/bitacora:help` row to the command
   table; extend the alias section so the `cp` snippet covers both
   `bit-handoff.md` and `bit-help.md`.

4. **Root `README.md`** — add a `/bitacora:help` row (✅ shipped) to its command
   table.

### Help block (printed verbatim)

```
Bitácora — commands

  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:help                Show this command reference.

  Planned
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
  /bitacora:status    Summarize a ticket's current state (PM / eng / self modes).
  /bitacora:spike     Create a timeboxed spike ticket with a mandatory rec.
  /bitacora:next      Morning ticket picker across your boards.

  Alias: /bit:handoff, /bit:help (opt-in — see plugin README)
```

## Decisions

- **Curated static, not dynamic.** Predictable, fast, no run-to-run variation.
  Cost: the block must be updated by hand when commands change.
- **`help` lists itself** under Shipped — self-documenting.
- **Single source discipline.** The README command tables and this block both
  enumerate commands. This change keeps all three consistent; future command
  additions must touch all three.

## Testing / verification

No `[CTX]` content is involved, so `validate-ctx.sh` is unaffected. Verification
is by inspection: the two command files parse (valid frontmatter), and the three
command listings (help block, plugin README, root README) agree.
