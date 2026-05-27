---
description: (alias of /bitacora:help) Show the Bitácora command reference.
---

<!-- Keep the fenced block in sync with commands/help.md (command files have no include primitive). -->

Output the command reference below exactly as written, inside a code block —
nothing else: no preamble, commentary, or tool calls.

```
Bitácora — commands

  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:resume [KEY]        Rehydrate a cleared session from a
                                ticket's latest [CTX] (read-only).
  /bitacora:status [KEY]        Summarize a ticket's latest [CTX] for an
                                audience (--for-pm/--for-eng/--for-self).
  /bitacora:help                Show this command reference.

  Planned
  /bitacora:next      Morning ticket picker across your boards.

  Alias: /bit:handoff, /bit:resume, /bit:status, /bit:help (opt-in — see plugin README)
```
