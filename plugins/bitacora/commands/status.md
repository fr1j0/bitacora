---
description: Synthesize one ticket's [CTX] (--for-self/eng/ops/pm/exec), roll up an epic, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) via --blocked / --standup / the default cross-ticket digest. Read-only; prints and offers a clipboard copy.
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts. A
`--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, or `--for-exec` flag selects the
audience lens (default: self). Point it at an **epic** and it rolls up the epic's children into a portfolio summary in the
chosen lens (no flag → `exec`); point it at a story/bug for the single-ticket summary.
Add `--copy-as-slack` to re-render the summary as Slack
`mrkdwn` and always copy it to the clipboard (skips the usual offer prompt).

For a **multi-ticket** read, pass a scope instead of one key — `--mine`, `--sprint`,
`--jql "<JQL>"`, or two or more keys — and optionally a query lens: `--blocked` (what's
stuck) or `--standup [--since 1d|2d|last-working-day]` (what moved). With no query lens, a
multi-ticket scope renders a cross-ticket digest. The `--for-*` audience lens still applies.

Arguments: $ARGUMENTS
