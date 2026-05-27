# `/bitacora:resume` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `/bitacora:resume [KEY]` (+ opt-in `/bit:resume`) — the read-side counterpart to `/bitacora:handoff` that reads a ticket's latest `[CTX]` comment(s) and prints a compact, read-only briefing.

**Architecture:** A thin command file delegates to a new `session-resume` skill that holds the workflow (resolve ticket → resolve site → read `[CTX]` → synthesize briefing → optional local-notes → print). Mirrors the `commands/handoff.md` → `skills/session-handoff` split exactly. Strictly read-only: no Jira write, no Remember mutation, no confirmation gate. Then four doc surfaces are updated to mark resume Shipped.

**Tech Stack:** Claude Code plugin markdown (command/skill/alias files with YAML frontmatter), the `bitacora:jira-comment-format` READ rules, the Atlassian Rovo read MCP, `git` for ticket resolution. No application code — verification is YAML/frontmatter validity, cross-listing consistency, and the existing `validate-ctx.sh` regression. Behavior (the live Jira read) is covered by manual acceptance, not an automated harness.

Spec: `docs/superpowers/specs/2026-05-27-bitacora-resume-command-design.md`

### Deviations from spec (deliberate, see session discussion)
- **No `allowed-tools` in the skill frontmatter.** Mirrors `session-handoff` (the working sibling), avoiding a hardcoded install-specific MCP server prefix in a distributable plugin.
- **Alias `cp` snippet untouched.** PR #16 already made it glob `bit-*.md`, so `bit-resume.md` is auto-covered; the spec's "extend the snippet" step is obsolete.
- **Narrative lines left as-is** (root README line 29 "Today — Phase 1 ships…", plugin README "Phase 1:" intro). Neither was updated when `/bitacora:help` shipped; keeping that precedent. Optional follow-up, not in scope.

---

### Task 1: `session-resume` skill (the workflow)

**Files:**
- Create: `plugins/bitacora/skills/session-resume/SKILL.md`

- [ ] **Step 1: Write the skill file**

Create `plugins/bitacora/skills/session-resume/SKILL.md` with exactly this content:

````markdown
---
name: session-resume
description: Rehydrate a fresh session from a Jira ticket's latest [CTX] comment(s) — read the structured state and print a compact, read-only briefing (where you left off, what's done, decided, next). Read-side counterpart to session-handoff. Use when the user runs /bitacora:resume or /bit:resume.
---

Read a single ticket's latest `[CTX]` state back into the session and print a compact
briefing. This is the **read-side counterpart to `bitacora:session-handoff`** and is
strictly **read-only** — it never writes to Jira or mutates Remember, so there is no
confirmation gate. Follow the **READ** rules in `bitacora:jira-comment-format` for
extracting state from `[CTX]` comments.

Optional explicit ticket key: any Jira-style key the invoking command passed through
(parse with `project_key_pattern`). If present, it forces the target.

## 1. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order:

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct candidates
  surface, **list them and let the user pick** — resume is about focus, not breadth. Never
  guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 2. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the `jira_cloud_id`
override if configured, else ask which (identical to handoff). **If the MCP is absent,
auth fails, or the site can't be resolved, this is a hard stop** (see Error behavior) —
resume cannot do its job without Jira read access.

## 3. Read the ticket

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments per
the **READ** rules in `bitacora:jira-comment-format`:

- The **latest** `[CTX]` is authoritative for `Status` and `Next`.
- Read up to `resume.ctx_lookback` prior `[CTX]` comments (default 1) to reconstruct a
  short `Done` trajectory without re-quoting everything.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Surface excluded-comment counts (non-`[CTX]`, malformed) per the format skill; never
  silently drop.

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

If a clean read of the Remember scratch is available, surface its private gotchas (dead
ends, fragile-code warnings) under a separate **Local notes** heading. If not, skip
silently — Remember already auto-injects local scratch at session start. This *enriches*
the Jira briefing; it is never a substitute (a missing MCP is a hard stop in step 2, not
something scratch can backfill).

## 6. Print and stop

Output the briefing into the conversation. Read-only: no gate, no write. Note that it's
safe to continue working.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; do not pretend a local-only fallback. (Surfacing any
  auto-injected Remember scratch is fine, but it is not "resume succeeding.")
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` at session ends so future resumes have
  something to read.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry
  with a different key. No retry loop.
- **Nothing to resume (no ticket resolved):** say so; suggest passing a key.

## Configuration

Reuses `project_key_pattern`, the compliance modes, and `jira_cloud_id` from the
`bitacora:jira-comment-format` / handoff config (`${CLAUDE_PROJECT_DIR}/.bitacora.yml`
then `~/.claude/bitacora.yml`; absence is normal). One optional addition:

```yaml
resume:
  ctx_lookback: 1     # how many prior [CTX] comments to stitch for the Done trajectory
```
````

- [ ] **Step 2: Verify frontmatter parses**

Run:
```bash
python3 - <<'PY'
import sys, yaml, pathlib
p = pathlib.Path("plugins/bitacora/skills/session-resume/SKILL.md")
t = p.read_text()
assert t.startswith("---\n"), "no frontmatter"
fm = t.split("---\n", 2)[1]
d = yaml.safe_load(fm)
assert d["name"] == "session-resume", d.get("name")
assert "description" in d and len(d["description"]) > 20
print("OK:", d["name"])
PY
```
Expected: `OK: session-resume`

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-resume/SKILL.md
git commit -m "feat: add session-resume skill (read-side workflow)"
```

---

### Task 2: `/bitacora:resume` command entry point

**Files:**
- Create: `plugins/bitacora/commands/resume.md`

- [ ] **Step 1: Write the command file**

Create `plugins/bitacora/commands/resume.md` with exactly this content (mirrors `commands/handoff.md`):

```markdown
---
description: Rehydrate a fresh session from a Jira ticket's latest [CTX] — read its Status / Decisions / Next back into context after a /clear. Read-only.
---

Use the `bitacora:session-resume` skill to run the session resume workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Verify frontmatter parses**

Run:
```bash
python3 - <<'PY'
import yaml, pathlib
t = pathlib.Path("plugins/bitacora/commands/resume.md").read_text()
d = yaml.safe_load(t.split("---\n", 2)[1])
assert "description" in d and len(d["description"]) > 20
assert "session-resume" in t and "$ARGUMENTS" in t
print("OK")
PY
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/commands/resume.md
git commit -m "feat: register /bitacora:resume command"
```

---

### Task 3: `/bit:resume` opt-in alias

**Files:**
- Create: `plugins/bitacora/alias/bit-resume.md`

- [ ] **Step 1: Write the alias file**

Create `plugins/bitacora/alias/bit-resume.md` with exactly this content (mirrors `alias/bit-handoff.md`):

```markdown
---
description: (alias of /bitacora:resume) Rehydrate a session from a ticket's latest [CTX].
---

Use the `bitacora:session-resume` skill to run the session resume workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Verify frontmatter parses and matches the command body**

Run:
```bash
python3 - <<'PY'
import yaml, pathlib
t = pathlib.Path("plugins/bitacora/alias/bit-resume.md").read_text()
d = yaml.safe_load(t.split("---\n", 2)[1])
assert d["description"].startswith("(alias of /bitacora:resume)")
assert "bitacora:session-resume" in t and "$ARGUMENTS" in t
print("OK")
PY
```
Expected: `OK`

Note: no edit to the README `cp` snippet is needed — it already globs `bit-*.md`, so this alias is auto-copied when a user re-runs the opt-in snippet.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/alias/bit-resume.md
git commit -m "feat: add opt-in /bit:resume alias"
```

---

### Task 4: Graduate resume to Shipped in the help listings (both files, kept in sync)

**Files:**
- Modify: `plugins/bitacora/commands/help.md`
- Modify: `plugins/bitacora/alias/bit-help.md`

Both files carry the identical fenced reference block (no include primitive). Apply the **same** edit to both.

- [ ] **Step 1: Edit the fenced block in BOTH files**

In each file, replace this region:

```
  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:help                Show this command reference.

  Next up (design merged)
  /bitacora:resume    Rehydrate a cleared session from a ticket's latest [CTX].

  Planned
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
```

with:

```
  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:resume [KEY]        Rehydrate a cleared session from a
                                ticket's latest [CTX] (read-only).
  /bitacora:help                Show this command reference.

  Planned
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
```

Then in each file update the Alias line:

```
  Alias: /bit:handoff, /bit:help (opt-in — see plugin README)
```

to:

```
  Alias: /bit:handoff, /bit:resume, /bit:help (opt-in — see plugin README)
```

(The "Next up (design merged)" tier is removed entirely — resume was its only entry.)

- [ ] **Step 2: Verify the two fenced blocks are byte-identical and resume is Shipped**

Run:
```bash
diff <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) \
     <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md) \
  && echo "IN SYNC" || echo "DIVERGED"
grep -q "Next up" plugins/bitacora/commands/help.md && echo "STALE: Next up tier still present" || echo "Next-up tier gone"
```
Expected: `IN SYNC` then `Next-up tier gone`

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md
git commit -m "docs: mark /bitacora:resume Shipped in help reference"
```

---

### Task 5: Add resume row to the plugin README command table

**Files:**
- Modify: `plugins/bitacora/README.md`

- [ ] **Step 1: Insert the resume row between the handoff and help rows**

Replace:

```
| `/bitacora:help` | Print the Bitácora command reference — shipped commands and the planned roadmap. |
```

with:

```
| `/bitacora:resume [KEY]` | Rehydrate a fresh session from a ticket's latest `[CTX]`: read its `Status` / `Decisions` / `Next` back into context after a `/clear` and print a compact, read-only briefing. Pass a key to target a ticket; otherwise resolved from the branch. |
| `/bitacora:help` | Print the Bitácora command reference — shipped commands and the planned roadmap. |
```

- [ ] **Step 2: Update the alias prose line to mention `/bit:resume`**

Replace:

```
the snippet — no need to edit it. Then `/bit:handoff` and `/bit:help` run the same
workflows as their `/bitacora:…` forms.
```

with:

```
the snippet — no need to edit it. Then `/bit:handoff`, `/bit:resume`, and `/bit:help`
run the same workflows as their `/bitacora:…` forms.
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "bitacora:resume" plugins/bitacora/README.md
grep -q "bit:resume" plugins/bitacora/README.md && echo "alias prose updated"
```
Expected: `1` then `alias prose updated`

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/README.md
git commit -m "docs: add /bitacora:resume to plugin README"
```

---

### Task 6: Promote resume to Phase 1 in the root README roadmap

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Flip the status cell from Planned to Phase 1**

Replace:

```
| `/bitacora:resume` | 🚧 Planned | Rehydrate a fresh session from a ticket's latest `[CTX]` — pull its `Status` / `Decisions` / `Next` back into context after a `/clear`, closing the handoff loop from Jira (not just local Remember). |
```

with:

```
| `/bitacora:resume` | ✅ **Phase 1** | Rehydrate a fresh session from a ticket's latest `[CTX]` — pull its `Status` / `Decisions` / `Next` back into context after a `/clear`, closing the handoff loop from Jira (not just local Remember). |
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -E "bitacora:resume\` \| ✅ \*\*Phase 1\*\*" README.md && echo "promoted"
grep -c "bitacora:resume\` | 🚧 Planned" README.md
```
Expected: the promoted line prints, then `0`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: promote /bitacora:resume to Phase 1 in roadmap"
```

---

### Task 7: Verification sweep (consistency + regression)

**Files:** none (read-only checks)

- [ ] **Step 1: All four listings agree that resume is shipped**

Run:
```bash
echo "help block:"; grep -c "bitacora:resume \[KEY\]" plugins/bitacora/commands/help.md
echo "bit-help block:"; grep -c "bitacora:resume \[KEY\]" plugins/bitacora/alias/bit-help.md
echo "plugin README:"; grep -c "bitacora:resume \[KEY\]" plugins/bitacora/README.md
echo "root README Phase 1:"; grep -c "bitacora:resume\` | ✅" README.md
echo "no stale Planned/Next-up for resume:"; grep -rn "Next up\|bitacora:resume\` | 🚧" plugins/bitacora README.md || echo "none"
```
Expected: each count `1`; final line `none`.

- [ ] **Step 2: All three new files have valid frontmatter**

Run:
```bash
python3 - <<'PY'
import yaml, pathlib
for f in ["plugins/bitacora/commands/resume.md",
          "plugins/bitacora/alias/bit-resume.md",
          "plugins/bitacora/skills/session-resume/SKILL.md"]:
    t = pathlib.Path(f).read_text()
    yaml.safe_load(t.split("---\n", 2)[1])
    print("OK", f)
PY
```
Expected: three `OK` lines.

- [ ] **Step 3: `validate-ctx.sh` is unaffected (resume reads, never writes `[CTX]`)**

Run:
```bash
bash plugins/bitacora/scripts/test-validate-ctx.sh
```
Expected: all existing tests pass (same as before this branch).

- [ ] **Step 4: Manual acceptance (cannot be automated — record results in the PR)**

1. On a branch named for a ticket that already has a `[CTX]`, run `/bitacora:resume` → briefing reflects the latest `Status` / `Next`, preserves PR links, omits empty sections.
2. On a ticket with no `[CTX]` → graceful "nothing to resume" path (shows Jira status + title, suggests handoff).
3. With the Atlassian MCP disabled → **hard stop** with a clear reason (NOT a fake local-only success).
4. With multiple recent ticket branches → resume lists candidates and lets you pick, rather than guessing.
