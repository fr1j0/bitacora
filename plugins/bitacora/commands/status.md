---
description: Synthesize one ticket's latest [CTX] into an audience-tailored summary across five lenses (--for-self/eng/ops/pm/exec). Epics render as a single node; multi-ticket and epic-rollup reads live in /bitacora:digest. Read-only; prints and offers a clipboard copy.
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket; otherwise resolve
it from the current branch or recent checkouts. A `--for-self`, `--for-eng`, `--for-ops`,
`--for-pm`, or `--for-exec` flag selects the audience lens (default: self). An epic key renders
its own `[CTX]` as a single node — for the children rollup use `/bitacora:digest`. Add
`--copy-as-slack` to re-render the summary as Slack `mrkdwn` and copy it to the clipboard.
Multi-ticket reads (`--mine`/`--sprint`/`--jql`/2+ keys, `--blocked`, `--standup`) live in
`/bitacora:digest`.

Arguments: $ARGUMENTS
