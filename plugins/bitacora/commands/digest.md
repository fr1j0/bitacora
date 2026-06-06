---
description: Aggregate [CTX] reads — roll up an epic across its children, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) via --blocked / --standup / the default cross-ticket digest, in five audience lenses. Read-only; prints and offers a clipboard copy.
---

Use the `bitacora:session-digest` skill to run the aggregate status workflow.

Point it at an **epic key** to roll up the epic's children into a portfolio summary, or pass a
**scope** — `--mine`, `--sprint`, `--jql "<JQL>"`, or two or more keys — to read across a set.
Add a query lens: `--blocked` (what's stuck) or `--standup [--since 1d|2d|last-working-day]`
(what moved, grouped by day). With no query lens, a scope renders a cross-ticket digest. A
`--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, or `--for-exec` flag selects the audience
lens (scope default: self; epic default: exec). Add `--copy-as-slack` to re-render as Slack
`mrkdwn` and copy to the clipboard. A single (non-epic) ticket key redirects you to
`/bitacora:status`.

Arguments: $ARGUMENTS
