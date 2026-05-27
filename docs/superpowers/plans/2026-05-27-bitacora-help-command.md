# `/bitacora:help` Command Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/bitacora:help` command (plus opt-in `/bit:help` alias) that prints a curated, static command reference — shipped commands with syntax, plus the planned roadmap.

**Architecture:** Two Claude Code command markdown files whose body instructs the model to print a fixed help block verbatim. No tool calls, no dynamic enumeration. Two README command tables are updated so all three command listings stay in sync.

**Tech Stack:** Claude Code plugin command files (markdown + YAML frontmatter). No build, no test runner — commands are discovered from `commands/`; aliases are opt-in manual copies. Verification is by inspection.

**Spec:** `docs/superpowers/specs/2026-05-27-bitacora-help-command-design.md`

---

### Task 1: Create the `/bitacora:help` command

**Files:**
- Create: `plugins/bitacora/commands/help.md`

- [ ] **Step 1: Write the command file**

Create `plugins/bitacora/commands/help.md` with exactly this content:

````markdown
---
description: Show the Bitácora command reference — shipped commands and the planned roadmap.
---

Print the command reference below verbatim — exactly the fenced block, with no
additions, tool calls, or commentary:

```
Bitácora — commands

  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:help                Show this command reference.

  Planned
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
  /bitacora:status    Summarize a ticket's current state (PM / eng / self modes).
  /bitacora:spike     Create a timeboxed spike ticket with a mandatory rec.
  /bitacora:next      Morning ticket picker across your boards.

  Alias: /bit:handoff, /bit:help (opt-in — see plugin README)
```
````

- [ ] **Step 2: Verify frontmatter parses**

Run: `head -3 plugins/bitacora/commands/help.md`
Expected: first line `---`, second line begins `description:`, third line `---`. Mirrors the structure of the sibling `commands/handoff.md`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/commands/help.md
git commit -m "feat: add /bitacora:help command reference"
```

---

### Task 2: Create the `/bit:help` alias

**Files:**
- Create: `plugins/bitacora/alias/bit-help.md`

- [ ] **Step 1: Write the alias file**

Create `plugins/bitacora/alias/bit-help.md` with exactly this content (same block as Task 1, alias description — mirrors the existing `alias/bit-handoff.md`):

````markdown
---
description: (alias of /bitacora:help) Show the Bitácora command reference.
---

Print the command reference below verbatim — exactly the fenced block, with no
additions, tool calls, or commentary:

```
Bitácora — commands

  Shipped
  /bitacora:handoff [KEYS...]   Wrap up a session cleanly: draft [CTX]
                                comments to each touched ticket + a
                                local handoff for next session.
  /bitacora:help                Show this command reference.

  Planned
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
  /bitacora:status    Summarize a ticket's current state (PM / eng / self modes).
  /bitacora:spike     Create a timeboxed spike ticket with a mandatory rec.
  /bitacora:next      Morning ticket picker across your boards.

  Alias: /bit:handoff, /bit:help (opt-in — see plugin README)
```
````

- [ ] **Step 2: Verify the block matches Task 1**

Run: `diff <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md)`
Expected: no output (the printed blocks are byte-identical).

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/alias/bit-help.md
git commit -m "feat: add opt-in /bit:help alias"
```

---

### Task 3: Update the plugin README

**Files:**
- Modify: `plugins/bitacora/README.md` (command table + alias section)

- [ ] **Step 1: Add the help row to the command table**

In `plugins/bitacora/README.md`, find the command table row (line ~21):

```markdown
| `/bitacora:handoff [KEYS...]` | Reconstruct the Jira tickets touched this session, draft a `[CTX]` status comment for each (confirm before writing), and save one consolidated local scratch via Remember. Pass ticket keys to force the set. |
```

Add a new row immediately after it:

```markdown
| `/bitacora:help` | Print the Bitácora command reference — shipped commands and the planned roadmap. |
```

- [ ] **Step 2: Update the alias section to cover both aliases**

In the same file, replace the alias section body. Find:

```markdown
Command namespace equals the plugin name, so commands are `/bitacora:…` by default.
For a shorter `/bit:handoff`, copy the bundled alias into your personal commands dir
(one-time, per machine):

```bash
mkdir -p ~/.claude/commands/bit
cp "$(dirname "$(find ~/.claude/plugins -path '*bitacora/alias/bit-handoff.md' | head -1)")/bit-handoff.md" \
   ~/.claude/commands/bit/handoff.md
```

Then `/bit:handoff` and `/bitacora:handoff` both run the same workflow.
```

Replace with:

```markdown
Command namespace equals the plugin name, so commands are `/bitacora:…` by default.
For the shorter `/bit:…` forms, copy the bundled aliases into your personal commands
dir (one-time, per machine):

```bash
mkdir -p ~/.claude/commands/bit
alias_dir="$(dirname "$(find ~/.claude/plugins -path '*bitacora/alias/bit-handoff.md' | head -1)")"
cp "$alias_dir/bit-handoff.md" ~/.claude/commands/bit/handoff.md
cp "$alias_dir/bit-help.md"    ~/.claude/commands/bit/help.md
```

Then `/bit:handoff` and `/bit:help` run the same workflows as their `/bitacora:…` forms.
```

- [ ] **Step 3: Verify both edits landed**

Run: `grep -n "bitacora:help\|bit-help.md\|/bit:help" plugins/bitacora/README.md`
Expected: three matches — the command-table row, the `cp` line, and the closing sentence.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/README.md
git commit -m "docs: list /bitacora:help and /bit:help in plugin README"
```

---

### Task 4: Update the root README

**Files:**
- Modify: `README.md` (command table)

- [ ] **Step 1: Add the help row to the command table**

In the root `README.md`, find the shipped-command row:

```markdown
| `/bitacora:handoff` | ✅ **Phase 1** | Wrap up a session cleanly. Writes a structured `[CTX]` comment to each touched Jira ticket plus a local handoff for next-session continuity. |
```

Add a new row immediately after it:

```markdown
| `/bitacora:help` | ✅ **Phase 1** | Print the Bitácora command reference — shipped commands and the planned roadmap. |
```

- [ ] **Step 2: Verify the edit landed**

Run: `grep -n "bitacora:help" README.md`
Expected: one match — the new command-table row.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: list /bitacora:help in root README command table"
```

---

### Task 5: Final consistency check

**Files:** none (verification only)

- [ ] **Step 1: Confirm all three command listings agree**

Run: `grep -rn "bitacora:help" README.md plugins/bitacora/README.md plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md`
Expected: at least one match in each of the four files — root README row, plugin README row, the help command's self-reference, and the alias's self-reference.

- [ ] **Step 2: Confirm validate-ctx still passes (unaffected, but verify no regression)**

Run: `bash plugins/bitacora/scripts/test-validate-ctx.sh`
Expected: all tests pass (this change touches no `[CTX]` logic).

---

## Self-Review

**1. Spec coverage:**
- New `commands/help.md` → Task 1. ✓
- New `alias/bit-help.md` → Task 2. ✓
- Plugin README (table + alias section) → Task 3. ✓
- Root README table row → Task 4. ✓
- Help block printed verbatim, lists itself, single-source discipline → embedded in Tasks 1–4. ✓
- Non-goals (no [CTX] primer, no integration status, no dynamic enumeration) → respected; nothing in the plan adds them. ✓
- Verification by inspection + validate-ctx unaffected → Task 5. ✓

**2. Placeholder scan:** No TBD/TODO; every file's full content and every command is shown literally. ✓

**3. Type consistency:** The help block is byte-identical between Task 1 and Task 2 (enforced by Task 2 Step 2 `diff`). Command names (`handoff`, `help`, `improve`, `status`, `spike`, `next`) are spelled consistently across all tasks and both READMEs. ✓
