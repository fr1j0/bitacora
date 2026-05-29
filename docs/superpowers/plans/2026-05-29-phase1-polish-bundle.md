# Phase 1 Polish Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship four small additive UX improvements per `docs/superpowers/specs/2026-05-29-phase1-polish-bundle-design.md` — a vagueness hint and since-when awareness in `/bitacora:resume`, a `--copy-as-slack` flag on `/bitacora:status`, and team-JQL discoverability docs in `/bitacora:next`.

**Architecture:** Workflow-prose changes only across three shipped skill files. No new files, no shell-script changes, no test-fixture changes, no new MCP permissions. Each item is one logical commit; the four-item bundle ships as a single PR.

**Tech Stack:** Markdown (skill prose). No code. Branch already created: `feat/phase1-polish-bundle` (spec committed at `9e99e37`).

> **Convention note for the implementer:** every `old_string` and `new_string` payload in this plan is wrapped in a **4-backtick** outer code fence (```` ```` ````) so that ordinary 3-backtick code fences appearing inside the payload don't break the outer wrapper. When applying via the `Edit` tool, copy the literal text *between* the two 4-backtick fences and pass it verbatim — do not strip or normalize whitespace, do not re-render any inner 3-backtick fences.

---

## File Structure

**Edited (no new files):**

- `plugins/bitacora/skills/session-resume/SKILL.md` — Items 1 + 2 (two commits)
  - Step 3 update: adaptive lookback bump on long absence (Item 2)
  - Step 4 update: briefing-template header line + vagueness-hint emission (Items 1 + 2)
  - Configuration block: 5 new optional keys under `resume:`
- `plugins/bitacora/skills/session-status/SKILL.md` — Item 3 (one commit)
  - Step 1 update: parse `--copy-as-slack` flag
  - Step 5 update: Slack-mrkdwn rendering branch
  - Step 6 update: auto-copy when flag set (skip the prompt)
- `plugins/bitacora/skills/session-next/SKILL.md` — Item 4 (one commit)
  - Configuration block: expand the `next.jql` example with a team-scoped pattern

**No-touch files** — explicitly out of scope:

- `plugins/bitacora/scripts/validate-ctx.sh` — no schema or rule change
- `plugins/bitacora/scripts/test-*.sh` — no shell logic added; no new fixtures
- `plugins/bitacora/skills/jira-comment-format/SKILL.md` — schema unchanged
- `plugins/bitacora/skills/session-handoff/SKILL.md`, `session-improve/SKILL.md` — out of bundle scope
- Any command/alias `.md` file, README, `PLUGIN_BRIEF.md`, marketplace metadata

---

## Task 1: Item 1 — Vagueness hint in `/bitacora:resume`

Add a one-line suggestion at the end of the briefing footer when the loaded ticket's description is brief and no recent `[ARCHIVE]` snapshot exists. Three new optional config keys land in the same commit.

**Files:**
- Modify: `plugins/bitacora/skills/session-resume/SKILL.md`

### Step 1: Update step 4 to emit the vagueness hint

- [ ] **Edit step 4's briefing template** to add the vagueness-hint sub-section between the closing fence of the briefing template and the start of step 5. Use the `Edit` tool with:

`old_string`:

````
## 4. Synthesize the briefing

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve PR links / URLs verbatim. Suggested shape:

```
Resuming PROJ-1234 — "<ticket title>"  (Jira status: In Progress)
https://<site>/browse/PROJ-1234

Where you left off:  <latest Status line>
Recently done:       <condensed Done bullets across the lookback window>
Decisions:           <decision + rationale bullets>
Next:                <actionable Next bullets>
Blockers / open Qs:  <only if present>

Suggested next step: <derived from the first Next item>
```

## 5. Reconcile local scratch (optional, additive)
````

`new_string`:

````
## 4. Synthesize the briefing

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve PR links / URLs verbatim. Suggested shape:

```
Resuming PROJ-1234 — "<ticket title>"  (Jira status: In Progress)
https://<site>/browse/PROJ-1234

Where you left off:  <latest Status line>
Recently done:       <condensed Done bullets across the lookback window>
Decisions:           <decision + rationale bullets>
Next:                <actionable Next bullets>
Blockers / open Qs:  <only if present>

Suggested next step: <derived from the first Next item>
```

### Vagueness hint (footer suggestion, after the briefing)

If **all three** conditions hold, emit a one-line suggestion **after** the briefing
and **before** step 5's local-scratch reconciliation:

- `resume.improve_suggest.enabled` is true (default true; see Configuration)
- The ticket's `description` field is shorter than
  `resume.improve_suggest.min_description_words` (default 50; whitespace-split count
  on the description text — *not* on `[CTX]` comments or other fields)
- No `[ARCHIVE]`-prefixed comment exists on the ticket whose `created` timestamp
  is within `resume.improve_suggest.suppress_window_days` (default 7) of now —
  i.e., the ticket has not already been improved recently

Suggested format:

```
💡 This ticket's description is brief (<N> words, no recent [ARCHIVE]).
    Consider /bitacora:improve <KEY> before starting — corpus-grounded rewrite
    grounded in [CTX] history, comments, Remember scratch, and git/PR refs.
```

The hint is a **suggestion, not a gate** — the engineer can ignore it and proceed.
Never block the briefing on this check. If the suppression check encounters an error
(`getJiraIssue` did not return comments, for example), skip the hint silently rather
than failing the briefing.

## 5. Reconcile local scratch (optional, additive)
````

### Step 2: Update the Configuration block to declare the three new keys

- [ ] **Edit the Configuration code-fence** at the bottom of the file. Use the `Edit` tool with:

`old_string`:

````
```yaml
resume:
  ctx_lookback: 1     # how many prior [CTX] comments to stitch for the Done trajectory
```
````

`new_string`:

````
```yaml
resume:
  ctx_lookback: 1               # how many prior [CTX] comments to stitch for the Done trajectory
  improve_suggest:
    enabled: true               # silence the vagueness hint entirely
    min_description_words: 50   # threshold; tickets with shorter descriptions are flagged
    suppress_window_days: 7     # skip the hint if an [ARCHIVE] landed within this window
```
````

### Step 3: Sanity-check the file

- [ ] Run:

```bash
grep -n "Vagueness hint\|improve_suggest" plugins/bitacora/skills/session-resume/SKILL.md
```

Expected: at least 5 matches — one in the new step-4 sub-section heading, three referencing the `improve_suggest.*` config keys in the prose, and one in the Configuration code-fence block (the `improve_suggest:` key line).

- [ ] Run all existing tests to confirm no regression:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
```

Expected: every line `PASS`; both scripts exit `0`.

### Step 4: Commit

- [ ] Stage and commit only the touched file:

```bash
git add plugins/bitacora/skills/session-resume/SKILL.md
git commit -m "feat(resume): add vagueness hint to briefing footer"
```

---

## Task 2: Item 2 — Since-when awareness in `/bitacora:resume`

Add a `Last touched: N days ago (YYYY-MM-DD)` line to the briefing header and adaptively widen the Done-trajectory lookback when the absence is long. Two new optional config keys land in the same commit. **This task builds on Task 1's edits** — the `old_string` of the Configuration edit below reflects Task 1's output. Do not execute out of order.

**Files:**
- Modify: `plugins/bitacora/skills/session-resume/SKILL.md`

### Step 1: Update step 3 to add the adaptive lookback rule

- [ ] **Edit step 3** to insert the long-absence-bump bullet between the existing `ctx_lookback` bullet and the `Use each comment's own created timestamp` bullet. Use the `Edit` tool with:

`old_string`:

````
- The **latest** `[CTX]` is authoritative for `Status` and `Next`.
- Read up to `resume.ctx_lookback` prior `[CTX]` comments (default 1) to reconstruct a
  short `Done` trajectory without re-quoting everything.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Surface excluded-comment counts (non-`[CTX]`, malformed) per the format skill; never
  silently drop.
````

`new_string`:

````
- The **latest** `[CTX]` is authoritative for `Status` and `Next`.
- Read up to `resume.ctx_lookback` prior `[CTX]` comments (default 1) to reconstruct a
  short `Done` trajectory without re-quoting everything.
- **Adaptive lookback for long absences:** if days-since-the-latest-`[CTX]` exceeds
  `resume.long_absence_days` (default 7), bump the lookback **for this invocation
  only** to `resume.long_absence_lookback` (default 3). Do not mutate the config;
  the bump is invocation-local. Intent: give the engineer a recap proportional to
  how long they've been away.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Surface excluded-comment counts (non-`[CTX]`, malformed) per the format skill; never
  silently drop.
````

### Step 2: Update step 4's briefing template to add the `Last touched:` header line

- [ ] **Edit the briefing template** inside step 4. Use the `Edit` tool with:

`old_string`:

````
Resuming PROJ-1234 — "<ticket title>"  (Jira status: In Progress)
https://<site>/browse/PROJ-1234

Where you left off:  <latest Status line>
````

`new_string`:

````
Resuming PROJ-1234 — "<ticket title>"  (Jira status: In Progress)
Last touched: 12 days ago (2026-05-17)
https://<site>/browse/PROJ-1234

Where you left off:  <latest Status line>
````

### Step 3: Add a one-paragraph clarification of the `Last touched:` line

- [ ] **Edit step 4** to insert a clarification paragraph between the closing of the briefing template and the start of the "Vagueness hint" sub-section (added in Task 1). Use the `Edit` tool with:

`old_string`:

````
Suggested next step: <derived from the first Next item>
```

### Vagueness hint (footer suggestion, after the briefing)
````

`new_string`:

````
Suggested next step: <derived from the first Next item>
```

The `Last touched:` line is computed from the latest compliant `[CTX]`'s own `created`
timestamp (from the Jira API; never hand-typed). If the ticket has zero `[CTX]`
comments, the line reads `Last touched: never (no [CTX] yet)` instead of a date.

### Vagueness hint (footer suggestion, after the briefing)
````

### Step 4: Update the Configuration block to add the two `long_absence_*` keys

- [ ] **Edit the Configuration code-fence**. This step's `old_string` reflects Task 1's output. Use the `Edit` tool with:

`old_string`:

````
```yaml
resume:
  ctx_lookback: 1               # how many prior [CTX] comments to stitch for the Done trajectory
  improve_suggest:
    enabled: true               # silence the vagueness hint entirely
    min_description_words: 50   # threshold; tickets with shorter descriptions are flagged
    suppress_window_days: 7     # skip the hint if an [ARCHIVE] landed within this window
```
````

`new_string`:

````
```yaml
resume:
  ctx_lookback: 1               # how many prior [CTX] comments to stitch for the Done trajectory
  long_absence_days: 7          # threshold (days since last [CTX]) above which the lookback widens
  long_absence_lookback: 3      # invocation-local ctx_lookback when over the threshold
  improve_suggest:
    enabled: true               # silence the vagueness hint entirely
    min_description_words: 50   # threshold; tickets with shorter descriptions are flagged
    suppress_window_days: 7     # skip the hint if an [ARCHIVE] landed within this window
```
````

### Step 5: Sanity-check the file

- [ ] Run:

```bash
grep -n "Adaptive lookback\|Last touched\|long_absence" plugins/bitacora/skills/session-resume/SKILL.md
```

Expected: at least 5 matches — one in the step-3 "Adaptive lookback" bullet, one in the briefing template's `Last touched:` line, one in the post-template clarification paragraph, and two in the Configuration code-fence block (`long_absence_days:`, `long_absence_lookback:`).

- [ ] Run all existing tests:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
```

Expected: every line `PASS`; both scripts exit `0`.

### Step 6: Commit

- [ ] Stage and commit:

```bash
git add plugins/bitacora/skills/session-resume/SKILL.md
git commit -m "feat(resume): add since-when awareness (Last touched + adaptive lookback)"
```

---

## Task 3: Item 3 — `--copy-as-slack` flag on `/bitacora:status`

Add a new flag, compatible with `--for-pm` / `--for-eng` / `--for-self`, that re-renders the audience-tailored summary in Slack `mrkdwn` and auto-copies to clipboard (skipping the existing offer-prompt).

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`

### Step 1: Update step 1 to parse the new flag

- [ ] **Edit step 1** to add the `--copy-as-slack` bullet alongside the existing argument bullets. Use the `Edit` tool with:

`old_string`:

````
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
````

`new_string`:

````
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.
- **`--copy-as-slack`:** optional; re-render the summary in Slack `mrkdwn` and copy to
  clipboard automatically (skipping the prompt in step 6). Compatible with all three
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
  rules.
````

### Step 2: Add the Slack mrkdwn rendering sub-section in step 5

- [ ] **Edit step 5** to insert a new sub-section after the three existing mode blocks but before the `examples/*.txt` reference. Use the `Edit` tool with:

`old_string`:

````
See `examples/self.txt`, `examples/eng.txt`, `examples/pm.txt` — the same `[CTX]` rendered
in all three modes.
````

`new_string`:

````
### Slack mrkdwn rendering (when `--copy-as-slack` is set)

Render the **same content** as the chosen mode (`--for-self` / `--for-eng` / `--for-pm`),
but with Slack `mrkdwn` conventions instead of Markdown:

- `*bold*` instead of `**bold**` (single asterisks for emphasis)
- `<https://example.com|label>` instead of `[label](https://example.com)` (Slack
  angle-bracket link form with `|` as the label separator)
- Plain bulleted lines (`• item` with U+2022) instead of Markdown lists (`- item`) —
  Slack renders Markdown lists inconsistently
- **No Markdown tables.** If a mode would have used a table (none currently do, but
  defensive), fall back to one bullet per row
- Surface the ticket key + URL prominently as the leading line, e.g.:
  `*PROJ-1234* — <https://site/browse/PROJ-1234|OAuth callback handling>`

All read semantics (strict `[CTX]` extraction, ticket resolution, error handling) are
unchanged from the default render path.

See `examples/self.txt`, `examples/eng.txt`, `examples/pm.txt` — the same `[CTX]` rendered
in all three modes.
````

### Step 3: Update step 6 to auto-copy when the flag is set

- [ ] **Edit step 6** to handle the flag's skip-the-prompt behavior. Use the `Edit` tool with:

`old_string`:

````
## 6. Print, then offer a clipboard copy

Print the rendered summary into the conversation. Then offer to copy it to the clipboard —
**read-only, no Jira write, no gate**. Clipboard is best-effort: pipe the rendered text to
the first available of `pbcopy` (macOS), `wl-copy` or `xclip -selection clipboard` (Linux),
or `clip` (Windows). If none is found, skip the offer silently — the printed summary always
stands on its own.
````

`new_string`:

````
## 6. Print, then offer a clipboard copy

Print the rendered summary into the conversation. Then:

- **Default** (no `--copy-as-slack`): offer to copy to clipboard, gated by user
  confirmation. **Read-only, no Jira write, no gate beyond the copy prompt.**
- **`--copy-as-slack` set:** **always** copy to clipboard (skip the prompt — the user
  has declared intent). If clipboard delivery fails (no `pbcopy` / `wl-copy` / `xclip` /
  `clip` available), print a one-line note that the rendered text was not copied; the
  printed summary still stands on its own.

Clipboard is best-effort: pipe the rendered text to the first available of `pbcopy`
(macOS), `wl-copy` or `xclip -selection clipboard` (Linux), or `clip` (Windows). If
none is found in the default path, skip the offer silently. With `--copy-as-slack`,
surface the absence as a one-line note (see above) so the user knows to copy manually.
````

### Step 4: Sanity-check the file

- [ ] Run:

```bash
grep -n "copy-as-slack\|Slack mrkdwn\|mrkdwn" plugins/bitacora/skills/session-status/SKILL.md
```

Expected: at least 4 matches across the step-1 flag bullet, the step-5 sub-section heading and its description bullets, and the step-6 conditional.

- [ ] Run all existing tests:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
```

Expected: every line `PASS`; both scripts exit `0`.

### Step 5: Commit

- [ ] Stage and commit:

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): add --copy-as-slack flag for one-paste Slack updates"
```

---

## Task 4: Item 4 — Team-JQL discoverability docs for `/bitacora:next`

Documentation-only fix. Expand the existing `next.jql` example in the skill's Configuration block to surface the team-scoped picker pattern. No code change.

**Files:**
- Modify: `plugins/bitacora/skills/session-next/SKILL.md`

### Step 1: Expand the Configuration block

- [ ] **Edit the Configuration code-fence** at the bottom of the file. Use the `Edit` tool with:

`old_string`:

````
```yaml
next:
  jql: ""            # overrides the default query verbatim when set
  stale_days: 30     # "stale" threshold for the Needs-attention tail
```
````

`new_string`:

````
```yaml
next:
  # The default JQL is:
  #   assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
  # Override below for team-scoped pickers (account-id or email per teammate;
  # accountId form is more stable across renames):
  jql: ""            # overrides the default query verbatim when set; e.g.:
                     #   "assignee in (currentUser(), 5a17b8c2..., 5b22d9e3...) AND statusCategory != Done ORDER BY updated DESC"
  stale_days: 30     # "stale" threshold for the Needs-attention tail
```
````

### Step 2: Sanity-check the file

- [ ] Run:

```bash
grep -n "team-scoped\|account-id\|assignee in" plugins/bitacora/skills/session-next/SKILL.md
```

Expected: at least 2 matches inside the Configuration code-fence.

- [ ] Run all existing tests:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
```

Expected: every line `PASS`; both scripts exit `0`.

### Step 3: Commit

- [ ] Stage and commit:

```bash
git add plugins/bitacora/skills/session-next/SKILL.md
git commit -m "docs(next): surface team-JQL pattern in next.jql example"
```

---

## Task 5: Final verification + push + open PR

**Files:** none modified — verification only.

### Step 1: Run all existing test suites

- [ ] Validate that no regression landed:

```bash
plugins/bitacora/scripts/test-validate-ctx.sh
plugins/bitacora/scripts/test-sync-bit-aliases.sh
plugins/bitacora/scripts/test-statusline.sh
plugins/bitacora/scripts/test-sync-statusline.sh
```

Expected: every line `PASS`; every script exits `0`.

### Step 2: Confirm the help block's lockstep invariant still holds

- [ ] No `help.md` edits in this PR, but verify the invariant anyway:

```bash
diff \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) \
  <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md)
```

Expected: no output.

### Step 3: Review the full diff against main

- [ ] Inspect the branch's commits and the per-file diff:

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Expected: 5 commits (spec + 4 task commits) on `feat/phase1-polish-bundle`, touching only:
- `docs/superpowers/specs/2026-05-29-phase1-polish-bundle-design.md`
- `docs/superpowers/plans/2026-05-29-phase1-polish-bundle.md`
- `plugins/bitacora/skills/session-resume/SKILL.md`
- `plugins/bitacora/skills/session-status/SKILL.md`
- `plugins/bitacora/skills/session-next/SKILL.md`

### Step 4: Push the branch

- [ ] Push with upstream tracking:

```bash
git push -u origin feat/phase1-polish-bundle
```

### Step 5: Open the PR

- [ ] Open the PR with the `skip-issue-check` + `enhancement` labels (precedent set by PRs #40, #42, #43, #44, #45, #46, #47, #48, #49, #50, #51, #52, #53, #54). Use `gh pr create`:

```bash
gh pr create --title "feat: Phase 1 polish bundle — resume/status/next UX touches" \
             --label "skip-issue-check,enhancement" \
             --body "$(cat <<'EOF'
## Summary

Bundle of four small additive UX improvements per docs/superpowers/specs/2026-05-29-phase1-polish-bundle-design.md, closing friction points surfaced by the 2026-05-29 UX-flow review.

- /bitacora:resume gains a vagueness hint that suggests /bitacora:improve when the loaded ticket's description is brief and no recent [ARCHIVE] exists. Heuristic-driven, opt-out via resume.improve_suggest.enabled: false.
- /bitacora:resume gains a Last touched: N days ago line in the briefing header, plus an invocation-local lookback bump (1 -> 3 by default) when the gap since the latest [CTX] exceeds 7 days. Gives long-absence resumes a recap proportional to the gap.
- /bitacora:status gains a --copy-as-slack flag that re-renders the audience-tailored summary in Slack mrkdwn (single-asterisk bold, <url|label> links, plain bullets, no Markdown tables) and auto-copies. One-paste status updates without manual reformatting.
- /bitacora:next docs surface the team-scoped picker pattern via the existing next.jql override. No code change — discoverability fix.

Non-goals (explicitly out of scope, see spec): Slack webhook auto-post, next.team_members syntactic-sugar config, AC-section detection for vagueness, [CORRECTION] prefix, /bitacora:start command, PreCompact handoff hook.

## Why skip-issue-check

No tracked issue; review-driven polish bundle. Precedent: every recent maintainer-chore PR.

## Test plan

- [x] All existing test suites pass (validate-ctx, sync-bit-aliases, statusline, sync-statusline) — no regression.
- [x] Help block lockstep invariant holds (no help.md edits, but verified).
- [x] Diff scoped to spec + plan + three skill files only.
- [ ] Live acceptance per item (per spec) — to be eyeballed after merge.
EOF
)"
```

### Step 6: Wait for CI

- [ ] Poll until all checks complete:

```bash
until gh pr view <PR#> --json statusCheckRollup --jq '[.statusCheckRollup[] | select(.status != "COMPLETED")] | length == 0' | grep -q true; do sleep 10; done
gh pr view <PR#> --json mergeable,mergeStateStatus,statusCheckRollup --jq '{mergeable, mergeStateStatus, checks: [.statusCheckRollup[] | {name, conclusion}]}'
```

Expected: all six checks green (3× `gate`, `lint`, `shell-tests (ubuntu-latest)`, `shell-tests (macos-latest)`); `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`.

Stop here and report to the user. **Do not auto-merge** — the user confirms each merge explicitly this session.

---

## Notes for the implementer

- **Branch is already created** — `feat/phase1-polish-bundle`. Spec is committed at `9e99e37`. All tasks build on it.
- **No new shell logic** — the four items are skill-prose touches. Existing test suites are regression checks only; no new tests are needed.
- **No new MCP permissions** — all four items reuse what resume/status/next already require.
- **Edit-tool discipline** — every code-modifying step in this plan gives exact `old_string` and `new_string` text wrapped in 4-backtick fences. Apply with the `Edit` tool, not by re-typing or reformatting. Inner 3-backtick fences in the payloads must survive intact.
- **Task 2 depends on Task 1's Configuration edit** — Task 2's `old_string` for the Configuration block reflects Task 1's output. If executing out of order (which you shouldn't), Task 2's Configuration edit will fail to match.
- **No Co-Authored-By trailer in any commit** (project convention; see prior commit history).
- **The Vagueness hint heuristic is intentionally coarse** (word count + recent `[ARCHIVE]` only). Do not extend it with AC-section detection — that was explicitly dropped as a non-goal in the spec.
- **No PLUGIN_BRIEF.md or README updates** — these are skill-internal config additions, surfaced in the skill's own Configuration block. The READMEs already point at the skills as the operational source of truth.
