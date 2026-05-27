---
description: Show the Bitácora command reference — shipped commands and the planned roadmap.
---

<!-- Keep the fenced block in sync with alias/bit-help.md (command files have no include primitive). -->

Output the command reference below exactly as written, inside a code block —
nothing else: no preamble, commentary, or tool calls.

```
Bitácora — commands

  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:help                Show this command reference.

  Next up (design merged)
  /bitacora:resume    Rehydrate a cleared session from a ticket's latest [CTX].

  Planned
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
  /bitacora:status    Summarize a ticket's current state (PM / eng / self modes).
  /bitacora:spike     Create a timeboxed spike ticket with a mandatory rec.
  /bitacora:next      Morning ticket picker across your boards.

  Alias: /bit:handoff, /bit:help (opt-in — see plugin README)
```
