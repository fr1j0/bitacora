---
description: Show the Bitácora command reference.
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
  /bitacora:resume [KEY]        Rehydrate a cleared session from a
                                ticket's latest [CTX] (read-only).
  /bitacora:status [KEY]        Summarize ONE ticket's latest [CTX] for an
                                audience — 5 lenses (self/eng/ops/pm/exec).
  /bitacora:digest [KEY|SCOPE]  Aggregate read — epic rollup or a multi-ticket
                                scope (--mine/--sprint/--jql) via --blocked /
                                --standup / the default cross-ticket digest.
  /bitacora:next                Morning ticket picker — categorized
                                shortlist of your assigned tickets
                                grounded in [CTX] (read-only).
  /bitacora:improve             Sharpen a ticket — corpus-grounded
                                rewrite (Story/Bug/Epic-aware) with a
                                snapshot to [ARCHIVE] before the edit.
  /bitacora:help                Show this command reference.

  Alias: /bit:handoff, /bit:resume, /bit:status, /bit:digest, /bit:next, /bit:improve, /bit:help (opt-in — see plugin README)
```

## Tracker backend

Bitácora targets **Jira** by default. In a repo whose tracker is **GitHub Issues**,
set the backend (or let it infer from the git remote):

```yaml
# .bitacora.yml (repo) or ~/.claude/bitacora.yml (home)
tracker: github   # jira | github | gitlab — omit to infer from the git remote host
```

GitHub/GitLab backends require the `gh`/`glab` CLI installed and authenticated
(`gh auth login` / `glab auth login`). All skills read and write `[CTX]` comments on the selected
tracker's issues exactly as they do on Jira.
