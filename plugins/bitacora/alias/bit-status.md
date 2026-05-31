---
description: (alias of /bitacora:status) Audience-tailored summary of a ticket's latest [CTX].
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts. A
`--for-self`, `--for-eng`, `--for-ops`, `--for-pm`, or `--for-exec` flag selects the
audience lens (default: self). Add `--copy-as-slack` to re-render the summary as Slack
`mrkdwn` and always copy it to the clipboard (skips the usual offer prompt).

Arguments: $ARGUMENTS
