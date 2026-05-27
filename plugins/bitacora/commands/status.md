---
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary (--for-pm/--for-eng/--for-self). Read-only; prints and offers a clipboard copy.
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts. A
`--for-pm`, `--for-eng`, or `--for-self` flag selects the audience mode
(default: self).

Arguments: $ARGUMENTS
