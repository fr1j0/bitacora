---
description: (alias of /bitacora:status) Audience-tailored summary of one ticket's latest [CTX].
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket; otherwise resolve
it from the current branch or recent checkouts. A `--for-self`, `--for-eng`, `--for-ops`,
`--for-pm`, or `--for-exec` flag selects the audience lens (default: self). An epic key renders
its own `[CTX]` as a single node — for the children rollup use `/bit:digest`. Add
`--copy-as-slack` to re-render as Slack `mrkdwn` and copy it to the clipboard.

Arguments: $ARGUMENTS
