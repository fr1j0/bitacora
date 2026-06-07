# `/status` ÷ `/digest` Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the multi-ticket / aggregate half of `bitacora:session-status` into a new `bitacora:session-digest` skill + `/bitacora:digest` command along the singular-vs-aggregate seam, leaving `/status` as a single-ticket read.

**Architecture:** Both commands are prompt-driven skills sharing the `[CTX]` read discipline and (newly) the audience-lens table in `jira-comment-format`. `session-status` keeps single-ticket read + the five single-ticket lens renders; `session-digest` owns epic rollup + multi-ticket scopes + query lenses (`--blocked`, `--standup`). Each command rejects the other's job with a clean error + pointer. No new runtime code — the existing shell helpers are reused unchanged.

**Tech Stack:** Markdown skill specs (prompt-driven), Claude Code plugin command/alias files (auto-discovered), grep-based deterministic fixture lint, bash helpers (`since-window.sh`, `standup-buckets.sh`, `staleness-check.sh` — unchanged).

---

## Context the engineer needs

- `/bitacora:*` behavior is **prompt-driven English spec** in `plugins/bitacora/skills/<name>/SKILL.md`, not code. "Implementing" = editing those specs precisely + moving the committed example renders and the lint that guards them.
- **Commands and skills are auto-discovered** from `plugins/bitacora/commands/*.md` and `plugins/bitacora/skills/*/SKILL.md`. `plugin.json` does **not** enumerate them — no registration edit is needed beyond creating the files.
- **`/bit:` aliases** live in `plugins/bitacora/alias/bit-*.md` and are copied (prefix stripped) into `~/.claude/commands/bit/` by `scripts/sync-bit-aliases.sh` on SessionStart. A new alias is just a new `alias/bit-<name>.md` file.
- The **`help` reference block** is duplicated in `commands/help.md` and `alias/bit-help.md` (a comment in `help.md` says to keep them in sync — there is no include primitive).
- **CHANGELOG + version bumps are done in the release PR**, not feature PRs (see how v0.6.0 landed: features in #102/#103, version+CHANGELOG in release PR #104). This plan does **not** touch `CHANGELOG.md`, `plugin.json`, or `marketplace.json`.
- Deterministic tests are bash scripts run directly: `bash plugins/bitacora/scripts/test-*.sh` (exit 0 = pass). No Makefile/npm runner.
- The repo forbids any `Co-Authored-By` / Claude attribution in commits — use the plain messages given.
- Work happens on branch `feature/status-digest-split` (already created; the spec `docs/superpowers/specs/2026-06-06-status-digest-split-design.md` is committed there). Do NOT switch branches.

## Current `session-status` section map (line numbers as of spec time)

`plugins/bitacora/skills/session-status/SKILL.md` (564 lines):

| Lines | Heading | Disposition |
|------|---------|-------------|
| 14 | `## 1. Parse arguments` | **slim** (drop scope/query-lens parsing; add multi-flag guard) |
| 49 | `## 2. Resolve the target ticket (single, focused)` | stays |
| 60 | `### 2a. Resolve a multi-ticket scope` | **move → digest** |
| 81 | `## 3. Resolve the Atlassian site` | stays (digest references it) |
| 88 | `## 4. Read the ticket (strict [CTX])` | stays |
| 106 | `### 4a. Single ticket or epic?` | **slim → epic-as-node** |
| 119 | `### 4b. Read the epic's children` | **move → digest** |
| 143 | `### 4c. Read the scope set` | **move → digest** |
| 156 | `## 5. Render for the selected mode` | stays; **lens table (162–172) → jira-comment-format** |
| 174 | `### Freshness` | stays |
| 196–276 | `### --for-self/eng/ops/pm/exec` | stays |
| 277 | `### Slack mrkdwn rendering` | **split** (single-ticket rules stay; index-entry link bullet → digest) |
| 299 | `### Aggregate signals (epic)` | **move → digest** |
| 319 | `### Aggregate render` | **move → digest** |
| 378 | `## 6. Print, then offer a clipboard copy` | stays (digest references it) |
| 394 | `## 7. Multi-ticket render (query lenses)` | **move → digest** |
| 418 | `### Default (no query flag) — cross-ticket digest` | **move → digest** |
| 431 | `### --blocked` | **move → digest** |
| 452 | `### --standup` | **move → digest** |
| 523 | `## Error / edge behavior` | **split** (single edges stay; multi/epic edges → digest) |
| 549 | `## Configuration` | **split** (`ctx_lookback`/`default_mode` stay; epic/fanout keys → digest) |

"Move verbatim" = copy the existing committed text unchanged except for the explicit adaptations a task names (heading renumbering, cross-reference repoints). The content already lives in the repo; do not paraphrase it.

## File structure (end state)

- `skills/jira-comment-format/SKILL.md` — gains an `## Audience lenses` section (the hoisted table) + `digest.*` config keys in its Configuration block.
- `skills/session-status/SKILL.md` — single-ticket only; lens table replaced by a reference.
- `skills/session-digest/SKILL.md` — **new**; aggregate/scope/query-lens reader.
- `skills/session-digest/examples/` — **new**; the relocated `multi-*.txt` + `epic-*.txt` fixtures.
- `commands/digest.md`, `alias/bit-digest.md` — **new** entry points; `commands/status.md` + `alias/bit-status.md` slimmed.
- `scripts/test-digest-fixtures.sh` — renamed from `test-multi-status-fixtures.sh`, paths repointed.
- `commands/help.md` + `alias/bit-help.md` — add `/digest`.
- `README.md`, `plugins/bitacora/README.md`, `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` — updated.

---

### Task 1: Hoist shared spec into `jira-comment-format`

**Files:**
- Modify: `plugins/bitacora/skills/jira-comment-format/SKILL.md`

- [ ] **Step 1: Add the `## Audience lenses` section**

Open `plugins/bitacora/skills/session-status/SKILL.md` and copy the table block at lines
162–172 (the `**Role → lens.**` paragraph, the `| Lens | Flag | Roles it serves | Leads with
/ strips |` table, and the `A lens **degrades gracefully**:` sentence). In
`jira-comment-format/SKILL.md`, insert a new section immediately **before** the
`## Read-side compliance` heading (currently line 143):

```markdown
## Audience lenses

`/bitacora:status` and `/bitacora:digest` both render `[CTX]` through five audience lenses;
pass the flag for the reader's role. This table is the single source of truth for lens
**altitude** (what each lens leads with and strips); each command supplies its own render
templates (single-ticket in `bitacora:session-status`, aggregate in `bitacora:session-digest`).

| Lens | Flag | Roles it serves | Leads with / strips |
|------|------|-----------------|---------------------|
| self | `--for-self` | you | terse recall — latest Status + Next |
| eng  | `--for-eng`  | frontend, backend, full-stack, staff, AI staff, tech lead | contract, `Artifacts:`, `Model/Eval:`, `Decisions:`+tags; keeps PR/commit links |
| ops  | `--for-ops`  | devops, infra, MLOps | `Deploy/Ops:`, rollback, watch-list, `Impact:`; keeps links |
| pm   | `--for-pm`   | product, technical managers | plain language; confidence; `Risk:`/`Dependencies:` as asks; strips PR/commit hashes, keeps ticket link |
| exec | `--for-exec` | CTO, CRAIO | business/risk/cost + confidence; strips implementation detail, keeps ticket link |

A lens **degrades gracefully**: if the `[CTX]` lacks a section the lens would lead with, omit
it silently (a UI ticket under `--for-ops` simply has no `Deploy/Ops:` to show).
```

- [ ] **Step 2: Document the `digest.*` config keys**

In the same file's `## Configuration` section (currently line 207), append the `digest.*`
namespace with the fallback rule. Add after the existing config block:

```markdown
`/bitacora:digest` reads its own `digest.*` keys, each **falling back to the legacy
`status.*` key** of the same name (then the built-in default) so existing configs keep working:

```yaml
digest:
  epic_type: Epic            # issue type that triggers epic rollup (was status.epic_type)
  epic_children_cap: 50      # max children read per epic (was status.epic_children_cap)
  epic_default_mode: exec    # lens for an epic target with no --for-* (was status.epic_default_mode)
  multi_fanout_cap: 25       # max tickets read per scope (was status.multi_fanout_cap)
  default_mode: self         # lens for a scope read with no --for-* (was the multi default)
```

Resolution per key: `digest.<key>` → legacy `status.<key>` → built-in default.
`status.ctx_lookback` and `status.default_mode` remain single-ticket-only.
```

- [ ] **Step 3: Verify**

Run: `grep -n "## Audience lenses\|digest:" plugins/bitacora/skills/jira-comment-format/SKILL.md`
Expected: the new section heading and the `digest:` config block both appear.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/SKILL.md
git commit -m "docs(format): hoist audience-lens table + digest.* config into jira-comment-format"
```

---

### Task 2: Create the `session-digest` skill

**Files:**
- Create: `plugins/bitacora/skills/session-digest/SKILL.md`
- Move (git mv): `skills/session-status/examples/{multi-aggregate,multi-aggregate-slack,multi-blocked,multi-standup,epic-exec,epic-eng}.txt` → `skills/session-digest/examples/`

Work from the **still-full** `session-status/SKILL.md` (it is slimmed in Task 3, after this).

- [ ] **Step 1: Move the fixtures**

```bash
mkdir -p plugins/bitacora/skills/session-digest/examples
git mv plugins/bitacora/skills/session-status/examples/multi-aggregate.txt        plugins/bitacora/skills/session-digest/examples/
git mv plugins/bitacora/skills/session-status/examples/multi-aggregate-slack.txt  plugins/bitacora/skills/session-digest/examples/
git mv plugins/bitacora/skills/session-status/examples/multi-blocked.txt          plugins/bitacora/skills/session-digest/examples/
git mv plugins/bitacora/skills/session-status/examples/multi-standup.txt          plugins/bitacora/skills/session-digest/examples/
git mv plugins/bitacora/skills/session-status/examples/epic-exec.txt              plugins/bitacora/skills/session-digest/examples/
git mv plugins/bitacora/skills/session-status/examples/epic-eng.txt               plugins/bitacora/skills/session-digest/examples/
```

- [ ] **Step 2: Author `session-digest/SKILL.md`**

Create `plugins/bitacora/skills/session-digest/SKILL.md`. Use this frontmatter + structure,
**moving the named blocks verbatim** from `session-status/SKILL.md` into the indicated
sections and applying the adaptations. (Section line numbers refer to the current
`session-status` map above.)

Frontmatter:

```markdown
---
name: session-digest
description: Aggregate Jira [CTX] reads — roll up an epic across its children, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) through a query lens (--blocked, --standup) or the default cross-ticket digest, in any of five audience lenses. Read-only; prints and offers a clipboard copy. Use when the user runs /bitacora:digest or /bit:digest.
---
```

Then assemble these sections in order:

1. **Intro paragraph** — one paragraph: digest is the aggregate sibling of `bitacora:session-status`; same strict `[CTX]` READ rules (`bitacora:jira-comment-format`); read-only, no Jira writes; apply the audience lens per the *Audience lenses* table in `bitacora:jira-comment-format`.
2. **`## 1. Parse arguments`** — move the multi-ticket/query-lens portions of `session-status` §1 (lines 14–48): the scope selectors (`--mine`/`--sprint`/`--jql`/2+ keys), the `--blocked`/`--standup`/`--since` query lenses, `--for-*`, `--copy-as-slack`, `--include-all`, `--board` reserved. Drop the single-ticket-only framing. Then **add the mirror guard** as the first resolution rule:

   ```markdown
   **Mirror guard (single ticket → /status).** If the arguments resolve to exactly **one
   explicit non-epic `project_key_pattern` key** with no scope selector, this is a
   single-ticket read — do not render. Print and stop:

   ```
   That's a single ticket — use /bitacora:status <KEY>.
   ```

   This fires only for an explicit single non-epic **key**. An epic key (rollup) and a scope
   that happens to match one ticket (degenerate one-item digest) both proceed normally.
   ```
3. **`## 2. Resolve the aggregate target`** — combine: epic key → the epic-children path; scope selector → the scope-set path. Move `session-status` §2a (lines 60–80) verbatim as the scope-resolution sub-part, and add a one-line lead: "An epic key resolves to the children read (§4); a scope selector resolves to the scope set (§4)."
4. **`## 3. Resolve the Atlassian site`** — one line: "Resolve `cloudId` exactly as `bitacora:session-status` §3 (`getAccessibleAtlassianResources`; `jira_cloud_id` override; hard-stop if the MCP is absent / auth fails)."
5. **`## 4. Read`** — move `session-status` §4b (lines 119–142, epic children) and §4c (lines 143–155, scope set) verbatim. Renumber internal "§4b/§4c" references to this section. Keep the strict-`[CTX]` classification (reporting / no-`[CTX]` / malformed / unreadable) and the per-reporting-ticket `created`+`updated` capture (needed by staleness, `--blocked`, `--standup`).
6. **`## 5. Aggregate signals`** — move `session-status` "### Aggregate signals (epic)" (lines 299–318) verbatim; generalize the lead so it applies to an epic's children **or** a resolved scope set (the computation is identical).
7. **`## 6. Render`** — move, verbatim: "### Aggregate render" (319–377), "## 7. Multi-ticket render (query lenses)" (394–417), "### Default (no query flag) — cross-ticket digest" (418–430), "### --blocked" (431–451), "### --standup — what moved, by day" (452–522). Also move the single bullet **"Ticket-key links in index entries"** from `session-status` "### Slack mrkdwn rendering" (the bullet near line 290) into this section's Slack guidance. Replace any "render in the chosen lens" phrasing's implicit table with: "apply the audience lens per the *Audience lenses* table in `bitacora:jira-comment-format`." Repoint internal `§5`/`§7`/`§4c` cross-references to this skill's section numbers.
8. **`## 7. Print, then offer a clipboard copy`** — one line: "Print the render, then offer/копy to clipboard exactly as `bitacora:session-status` §6 (best-effort `pbcopy`/`wl-copy`/`xclip`/`clip`; `--copy-as-slack` always copies)."
9. **`## Error / edge behavior`** — move only the multi-ticket/epic edges from `session-status` "## Error / edge behavior" (523–548): epic-with-no-children, epic-children-no-`[CTX]`, child-listing-fails, scope-matched-zero, all-reporting-no-`[CTX]`, `--board`, bad `--jql`, invalid mode flag. Add: "single non-epic key → mirror guard (§1) redirects to `/status`."
10. **`## Configuration`** — document that digest reads `digest.*` with `status.*` fallback, pointing to the `bitacora:jira-comment-format` Configuration block (added in Task 1) as the source of truth. List the five keys (`epic_type`, `epic_children_cap`, `epic_default_mode`, `multi_fanout_cap`, `default_mode`).

Replace the example references at the bottom so they point at `examples/` in this skill
(the files moved in Step 1): `examples/multi-aggregate.txt`, `multi-blocked.txt`,
`multi-standup.txt`, `epic-exec.txt`, `epic-eng.txt`, `multi-aggregate-slack.txt`.

- [ ] **Step 3: Verify no dangling self-references**

Run: `grep -nE "§[0-9]|session-status §" plugins/bitacora/skills/session-digest/SKILL.md`
Expected: every `§N` points to a section that exists **in this file**, except the three
explicit `bitacora:session-status §3`/`§6` utility references and the `jira-comment-format`
references. Fix any stale `§4b`/`§4c`/`§5`/`§7` that should now be this skill's own numbers.

Run: `grep -c "examples/" plugins/bitacora/skills/session-digest/SKILL.md`
Expected: ≥ 1 (example references present and pointing at relocated files).

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-digest/
git commit -m "feat(digest): add session-digest skill (epic rollup + scopes + query lenses)"
```

---

### Task 3: Slim `session-status` to single-ticket

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`

- [ ] **Step 1: Remove the moved sections**

Delete these sections entirely from `session-status/SKILL.md` (now living in `session-digest`):
`### 2a.` (60–80), `### 4b.` (119–142), `### 4c.` (143–155), `### Aggregate signals (epic)`
(299–318), `### Aggregate render` (319–377), `## 7. Multi-ticket render (query lenses)` and its
sub-sections `### Default …`, `### --blocked`, `### --standup …` (394–522). From "### Slack
mrkdwn rendering", delete only the **"Ticket-key links in index entries"** bullet (it moved to
digest); keep the rest.

- [ ] **Step 2: Slim §1 (Parse arguments) + add the multi-flag guard**

In `## 1. Parse arguments`, remove the **Scope (multi-ticket)** and **Query lens** and
`--since` paragraphs (the multi-ticket parsing). Then add, as the first rule after the mode-flag
parsing:

```markdown
**Single-ticket only — multi-ticket reads moved to `/bitacora:digest`.** If the arguments
carry a scope selector (`--mine`, `--sprint`, `--jql`), a query lens (`--blocked`,
`--standup`, `--since`), or **two or more** `project_key_pattern` keys, do not render. Print
and stop, echoing the flags back so the redirect is copy-pasteable:

```
Multi-ticket reads now live in /bitacora:digest.
Try:  /bitacora:digest <the same flags/keys the user passed>
```
```

- [ ] **Step 3: Replace §4a with epic-as-node**

Replace the entire `### 4a. Single ticket or epic?` section (106–118) with:

```markdown
### 4a. Epics render as a single node

`/bitacora:status` does **not** roll up epics — that is `/bitacora:digest`'s job. An epic key
flows through the single-ticket path like any other ticket: render its **own** `[CTX]` (the
status comment on the epic itself) through the chosen lens. When the epic has no own `[CTX]`,
fall to the no-`[CTX]` edge (below) and add a pointer:
`For the children rollup, use /bitacora:digest <EPIC-KEY>`.
```

- [ ] **Step 4: Replace the §5 lens table with a reference**

In `## 5. Render for the selected mode`, replace the `**Role → lens.**` paragraph + the table +
the `degrades gracefully` sentence (162–172) with:

```markdown
**Audience lens.** Apply the lens for the reader's role per the *Audience lenses* table in
`bitacora:jira-comment-format` (the canonical altitude definitions). The single-ticket render
templates for each lens follow below.
```

- [ ] **Step 5: Split Error/edge + Configuration**

In `## Error / edge behavior`, remove the multi-ticket/epic edges that moved to digest
(epic-with-no-children, epic-children-no-`[CTX]`, child-listing-fails, scope-matched-zero,
all-reporting-no-`[CTX]`, `--board`, bad `--jql`). Keep the single-ticket edges (MCP absent,
no-`[CTX]`-on-ticket, ticket 404, no ticket resolved, invalid mode flag). Add:
`- **Multi-ticket flags / 2+ keys:** redirect to /bitacora:digest (see §1).`

In `## Configuration`, keep only `ctx_lookback` and `default_mode` under `status:`; remove
`epic_type`, `epic_children_cap`, `epic_default_mode`, `multi_fanout_cap` (now `digest.*` — add
a one-line "see `bitacora:jira-comment-format` for `digest.*`").

Also update the skill's frontmatter `description` to drop the epic-rollup / multi-ticket
clauses:

```markdown
description: Synthesize one Jira ticket's latest [CTX] into an audience-tailored summary across five lenses (--for-self/eng/ops/pm/exec). Epics render as a single node (their own [CTX]); multi-ticket and epic-rollup reads live in /bitacora:digest. Read-only; prints and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
```

- [ ] **Step 6: Verify no dangling references**

Run: `grep -nE "standup|--blocked|--mine|--sprint|--jql|Aggregate|epic rollup|§4b|§4c|§7|## 7\." plugins/bitacora/skills/session-status/SKILL.md`
Expected: no matches **except** the §1 redirect text (which names `--standup`/`--blocked`/etc.
in the guard) and the §4a `digest` pointer. Any leftover aggregate/query-lens machinery is a
missed deletion — remove it.

Run: `grep -n "Role → lens\|| Lens |" plugins/bitacora/skills/session-status/SKILL.md`
Expected: no matches (table is gone, replaced by the reference).

- [ ] **Step 7: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "refactor(status): slim to single-ticket; epic-as-node; redirect multi reads to /digest"
```

---

### Task 4: Rename + repoint the fixture lint

**Files:**
- Rename (git mv): `scripts/test-multi-status-fixtures.sh` → `scripts/test-digest-fixtures.sh`
- Modify: the renamed script's `EX=` path

- [ ] **Step 1: Rename**

```bash
git mv plugins/bitacora/scripts/test-multi-status-fixtures.sh plugins/bitacora/scripts/test-digest-fixtures.sh
```

- [ ] **Step 2: Repoint the examples dir**

In `plugins/bitacora/scripts/test-digest-fixtures.sh`, the `EX` variable currently is:

```bash
EX="$DIR/../skills/session-status/examples"
```

Change it to:

```bash
EX="$DIR/../skills/session-digest/examples"
```

(The fixture filenames are unchanged — only the skill dir moved. No other line needs editing.)

- [ ] **Step 3: Run the lint**

Run: `bash plugins/bitacora/scripts/test-digest-fixtures.sh`
Expected: all `PASS`, exit 0 (same assertions, fixtures now found in `session-digest/examples`).

- [ ] **Step 4: Run the full suite (no regressions)**

```bash
for t in plugins/bitacora/scripts/test-digest-fixtures.sh \
         plugins/bitacora/scripts/test-standup-buckets.sh \
         plugins/bitacora/scripts/test-since-window.sh \
         plugins/bitacora/scripts/test-staleness-check.sh; do
  echo "== $t =="; bash "$t" >/tmp/o 2>&1 && echo "PASS ($(grep -c '^PASS' /tmp/o))" || { echo "FAIL"; grep '^FAIL' /tmp/o; }
done
```
Expected: every line `PASS`.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/scripts/test-digest-fixtures.sh
git commit -m "test(digest): rename fixture lint and repoint to session-digest/examples"
```

---

### Task 5: Command + alias entry points

**Files:**
- Create: `plugins/bitacora/commands/digest.md`, `plugins/bitacora/alias/bit-digest.md`
- Modify: `plugins/bitacora/commands/status.md`, `plugins/bitacora/alias/bit-status.md`

- [ ] **Step 1: Create `commands/digest.md`**

```markdown
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
```

- [ ] **Step 2: Create `alias/bit-digest.md`**

```markdown
---
description: (alias of /bitacora:digest) Aggregate [CTX] reads — epic rollup or multi-ticket scope via --blocked / --standup / digest.
---

Use the `bitacora:session-digest` skill to run the aggregate status workflow.

Point it at an **epic key** to roll up the epic's children, or pass a **scope** — `--mine`,
`--sprint`, `--jql "<JQL>"`, or two or more keys — optionally with a query lens: `--blocked`
(what's stuck) or `--standup [--since 1d|2d|last-working-day]` (what moved, by day). With no
query lens, a scope renders a cross-ticket digest. The `--for-*` audience lens still applies.
A single (non-epic) ticket key redirects you to `/bit:status`.

Arguments: $ARGUMENTS
```

- [ ] **Step 3: Slim `commands/status.md`**

Replace the body of `plugins/bitacora/commands/status.md` with (drop the epic-rollup and
multi-ticket paragraphs; keep single-ticket + lenses + Slack):

```markdown
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
```

- [ ] **Step 4: Slim `alias/bit-status.md`**

Replace its body to match (single-ticket framing; the alias had no multi-ticket paragraph but
update the epic line):

```markdown
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
```

- [ ] **Step 5: Verify the alias-sync test still passes**

Run: `bash plugins/bitacora/scripts/test-sync-bit-aliases.sh`
Expected: PASS (the new `bit-digest.md` is just another alias source; the sync is add-only).

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/commands/digest.md plugins/bitacora/alias/bit-digest.md plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md
git commit -m "feat(digest): add /digest command + alias; slim /status entry points"
```

---

### Task 6: Help, READMEs, manual-acceptance

**Files:**
- Modify: `plugins/bitacora/commands/help.md`, `plugins/bitacora/alias/bit-help.md`
- Modify: `README.md`, `plugins/bitacora/README.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

- [ ] **Step 1: Update the help reference block (both copies)**

In **both** `plugins/bitacora/commands/help.md` and `plugins/bitacora/alias/bit-help.md`, inside
the fenced `Bitácora — commands` block: (a) change the `/bitacora:status` line to read
single-ticket, and (b) add a `/bitacora:digest` line after it. Replace the status line:

```
  /bitacora:status [KEY]        Summarize a ticket's latest [CTX] for an
                                audience — 5 lenses (self/eng/ops/pm/exec).
```

with:

```
  /bitacora:status [KEY]        Summarize ONE ticket's latest [CTX] for an
                                audience — 5 lenses (self/eng/ops/pm/exec).
  /bitacora:digest [KEY|SCOPE]  Aggregate read — epic rollup or a multi-ticket
                                scope (--mine/--sprint/--jql) via --blocked /
                                --standup / the default cross-ticket digest.
```

And in the `Alias:` line, add `/bit:digest`:

```
  Alias: /bit:handoff, /bit:resume, /bit:status, /bit:digest, /bit:next, /bit:improve, /bit:help (opt-in — see plugin README)
```

- [ ] **Step 2: Update both READMEs**

In `README.md` and `plugins/bitacora/README.md`, find the command list/table and add a
`/bitacora:digest` row next to `/bitacora:status`, and adjust the `/status` description to
"one ticket" / single-ticket. Use the same one-line description as the `commands/digest.md`
frontmatter. (Match the surrounding list/table formatting exactly — read the file's existing
command list first and mirror its style.)

- [ ] **Step 3: Re-point MANUAL-ACCEPTANCE**

In `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, change every multi-ticket / epic check
(the `M`-series that invokes `--mine`/`--sprint`/`--jql`/`--blocked`/`--standup`/epic rollup,
and the Slack/staleness index-entry items) from `/bitacora:status …` to `/bitacora:digest …`.
Leave the single-ticket lens checks under `/bitacora:status`. Then add two guard checks:

```markdown
- [ ] **G1 — status rejects multi:** `/bitacora:status --mine --standup` → prints
      "Multi-ticket reads now live in /bitacora:digest" with the flags echoed; no render.
- [ ] **G2 — digest rejects a single key:** `/bitacora:digest AT-1234` (a non-epic key) →
      prints "That's a single ticket — use /bitacora:status AT-1234"; no render.
      `/bitacora:status AT-EPIC` (an epic) → renders the epic's own [CTX] as one node (or the
      no-[CTX] line + a `/bitacora:digest` pointer).
```

- [ ] **Step 4: Verify cross-references**

Run: `grep -rn "session-status" plugins/bitacora/skills/session-digest/ plugins/bitacora/commands/digest.md`
Expected: only the intended `§3`/`§6` utility references — no accidental "run the session-status
skill" in the digest command.

Run: `grep -rn "rolls up an epic\|multi-ticket scope" plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md`
Expected: no matches (slimmed out of the status entry points).

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md README.md plugins/bitacora/README.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs(digest): document /digest in help, READMEs, manual-acceptance"
```

---

## Self-Review

**Spec coverage:**
- Singular/aggregate seam → Tasks 2 (digest) + 3 (status slim). ✅
- `/status` multi-flag error+pointer → Task 3 Step 2. ✅
- `/status` epic-as-node + pointer → Task 3 Step 3. ✅
- `/digest` mirror guard (single non-epic key → /status; scope-of-one renders) → Task 2 Step 2.2. ✅
- Lens table hoisted into `jira-comment-format`; both skills reference → Task 1 Step 1, Task 2 (§ refs), Task 3 Step 4. ✅
- `digest.*` config with `status.*` fallback → Task 1 Step 2, Task 2 §10, Task 3 Step 5. ✅
- Fixtures + lint move/repoint → Task 2 Step 1, Task 4. ✅
- New command/alias auto-discovered; slim old → Task 5. ✅
- help / READMEs / manual-acceptance → Task 6. ✅
- CHANGELOG/version deferred to release PR → noted in Context (correctly out of scope). ✅

**Placeholder scan:** No TBD/TODO. "Move verbatim" instructions name exact source sections + line ranges + adaptations — the content is committed in-repo, so this is a relocation, not an unspecified write; every *new/changed* string is given in full.

**Type/name consistency:** Skill name `session-digest`, command `/bitacora:digest`, alias `bit-digest.md`, fixture lint `test-digest-fixtures.sh`, config namespace `digest.*` — used identically across Tasks 1–6. The five lens flags and the fixture filenames match their originals.

## Notes for landing

After all tasks pass, this branch is ready for a PR (topic → PR → owner approval label →
squash-merge). The version bump to **v0.7.0** + CHANGELOG happen in the **separate release
PR**, per repo convention — not here. Manual-acceptance G1/G2 + the relocated M-series are the
human verification gate for the redirect behavior the deterministic lint can't fully cover.
