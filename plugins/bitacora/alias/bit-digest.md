---
description: (alias of /bitacora:digest) Aggregate [CTX] reads — epic rollup or multi-ticket scope via --blocked / --standup / digest.
---

Use the `bitacora:session-digest` skill to run the aggregate status workflow.

Point it at an **epic key** to roll up the epic's children, or pass a **scope** — `--mine`,
`--sprint`, `--jql "<JQL>"`, or two or more keys — optionally with a query lens: `--blocked`
(what's stuck) or `--standup [--since 1d|2d|last-working-day]` (what moved — done / planned / blocked). With no
query lens, a scope renders a cross-ticket digest. The `--for-*` audience lens still applies.
A single (non-epic) ticket key redirects you to `/bit:status`.

Arguments: $ARGUMENTS
