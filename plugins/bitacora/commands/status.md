---
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary (--for-self/--for-eng/--for-ops/--for-pm/--for-exec). Read-only; prints and offers a clipboard copy.
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts. A
`--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, or `--for-exec` flag selects the
audience lens (default: self). Point it at an **epic** and it rolls up the epic's children into a portfolio summary in the
chosen lens (no flag → `exec`); point it at a story/bug for the single-ticket summary.
Add `--copy-as-slack` to re-render the summary as Slack
`mrkdwn` and always copy it to the clipboard (skips the usual offer prompt).

Arguments: $ARGUMENTS
