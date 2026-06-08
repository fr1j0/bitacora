# `/handoff` Self-Collision Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warn at the `/handoff` confirm gate when the user is about to stack a near-duplicate `[CTX]` on a ticket whose newest `[CTX]` is the user's own and recent (≤ `self_handoff_window`, default 2h).

**Architecture:** Add a `--self` mode to the existing tested `collision-check.sh` (the mirror of the teammate rule on the same inputs), wire it into the prompt-driven `session-handoff` skill's existing collision step + confirm gate, and add the `self_handoff_window` config key. Warn-only; never blocks. Time-window only (content-diff + in-place edit deferred per issue #100).

**Tech Stack:** Bash (pure-arithmetic helper, `set -uo pipefail`, deterministic `--now`-injected tests), prompt-driven Markdown skill spec, grep/CI test harness.

---

## Context the engineer needs

- `collision-check.sh` is a **pure decision helper** (no Jira calls): the `session-handoff`
  skill extracts author accountIds + `[CTX]` `created` epochs from the ticket's comments and
  passes them in; the script prints `collision` or `clear`. It already resolves `<N>h`/`<N>d`
  window tokens and accepts an injectable `--now` for deterministic tests.
- The **teammate** rule (existing): `collision` iff `latest_author != me AND latest_epoch >
  mine_epoch (or --mine-epoch omitted) AND latest_epoch >= now − window`.
- The **self** rule (this change): `collision` iff `latest_author == me AND latest_epoch >=
  now − window`. Mutually exclusive with the teammate rule on *whose `[CTX]` is newest*.
- `/handoff` behavior is prompt-driven English in `plugins/bitacora/skills/session-handoff/SKILL.md`
  — "implementing" the flow/gate/config means editing that spec precisely.
- Tests run directly: `bash plugins/bitacora/scripts/test-collision-check.sh` (exit 0 = pass);
  it's already wired into `.github/workflows/test.yml`.
- Repo rule: **no `Co-Authored-By` / Claude attribution** in commits.
- Work on branch `feature/100-self-collision-guard` (already created; the spec
  `docs/superpowers/specs/2026-06-08-self-collision-guard-design.md` is committed there). Do
  NOT switch branches.

## File structure

- `plugins/bitacora/scripts/collision-check.sh` — add `--self` mode (flag + branch + docstring).
- `plugins/bitacora/scripts/test-collision-check.sh` — add `--self` cases.
- `plugins/bitacora/skills/session-handoff/SKILL.md` — self-check branch in the collision step;
  `⚠ recent self-handoff` gate block; `self_handoff_window` config key.
- `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` — one self-collision manual item.

---

### Task 1: `--self` mode in `collision-check.sh` (TDD)

**Files:**
- Modify: `plugins/bitacora/scripts/collision-check.sh`
- Test: `plugins/bitacora/scripts/test-collision-check.sh`

- [ ] **Step 1: Add the failing `--self` test cases**

In `plugins/bitacora/scripts/test-collision-check.sh`, add a `H1` constant after the existing
`H2` line. Find:

```bash
H2=$((NOW - 7200))          # 2h ago
```

Replace with:

```bash
H2=$((NOW - 7200))          # 2h ago
H1=$((NOW - 3600))          # 1h ago
```

Then add these cases immediately after the existing `check "7d window, 2d-old other → collision" ...` line:

```bash

# --self mode: self-collision — collision iff the newest [CTX] is MINE and recent.
check "self: mine + recent (default 48h) → collision" collision --self --me u1 --latest-author u1 --latest-epoch "$H3" --now "$NOW"
check "self: mine + within 2h → collision"            collision --self --window 2h --me u1 --latest-author u1 --latest-epoch "$H1" --now "$NOW"
check "self: mine + older than 2h → clear"            clear     --self --window 2h --me u1 --latest-author u1 --latest-epoch "$H3" --now "$NOW"
check "self: mine at 2h boundary → collision"         collision --self --window 2h --me u1 --latest-author u1 --latest-epoch "$H2" --now "$NOW"
check "self: newest is a teammate's → clear"          clear     --self --window 2h --me u1 --latest-author u2 --latest-epoch "$H1" --now "$NOW"
```

- [ ] **Step 2: Run the tests to verify the new cases fail**

Run: `bash plugins/bitacora/scripts/test-collision-check.sh`
Expected: the five `self:` cases FAIL (the script doesn't know `--self` yet — it errors on the
unknown arg → empty stdout / exit 2, so the `check` lines report FAIL). The pre-existing cases
still PASS.

- [ ] **Step 3: Add the `--self` flag to the arg parser**

In `plugins/bitacora/scripts/collision-check.sh`, find the variable-init line:

```bash
me="" latest_author="" latest_epoch="" mine_epoch="" now="" window="48h"
```

Replace with:

```bash
me="" latest_author="" latest_epoch="" mine_epoch="" now="" window="48h" self=false
```

Then find the arg-parse `case` block and its `--window` arm:

```bash
    --window)        window="${2:-}"; shift 2 ;;
```

Add a `--self` arm immediately after it (note: a flag, so `shift 1`):

```bash
    --window)        window="${2:-}"; shift 2 ;;
    --self)          self=true; shift ;;
```

- [ ] **Step 4: Add the `--self` decision branch**

In the same file, find the decision section (after the window is resolved into `win`):

```bash
# 1. Newest context is mine → no collision.
if [[ "$latest_author" == "$me" ]]; then echo clear; exit 0; fi
```

Insert the self-mode branch immediately **before** that `# 1.` line:

```bash
# --self mode: self-collision — report collision iff the newest [CTX] is MINE and recent.
# (Mirror of the teammate rule; --mine-epoch is irrelevant here — when the newest [CTX] is
# mine, that IS my recent self-handoff.)
if [[ "$self" == "true" ]]; then
  [[ "$latest_author" == "$me" ]] || { echo clear; exit 0; }
  cutoff=$(( now - win ))
  if (( latest_epoch >= cutoff )); then echo collision; else echo clear; fi
  exit 0
fi
# 1. Newest context is mine → no collision.
if [[ "$latest_author" == "$me" ]]; then echo clear; exit 0; fi
```

- [ ] **Step 5: Update the docstring**

In the same file's header comment, find the usage line:

```bash
#   collision-check.sh --me <accountId> --latest-author <accountId> \
#       --latest-epoch <N> [--mine-epoch <N>] [--now <N>] [--window <token>]
```

Replace with:

```bash
#   collision-check.sh [--self] --me <accountId> --latest-author <accountId> \
#       --latest-epoch <N> [--mine-epoch <N>] [--now <N>] [--window <token>]
```

And find the rule description:

```bash
# A collision is reported iff ALL hold:
#   1. --latest-author != --me           (the newest context is someone else's)
#   2. --latest-epoch  >  --mine-epoch    (or --mine-epoch omitted: a takeover)
#   3. --latest-epoch  >= now - window    (the context is recent)
```

Replace with:

```bash
# Default (teammate) mode — a collision is reported iff ALL hold:
#   1. --latest-author != --me           (the newest context is someone else's)
#   2. --latest-epoch  >  --mine-epoch    (or --mine-epoch omitted: a takeover)
#   3. --latest-epoch  >= now - window    (the context is recent)
#
# --self mode — a self-collision is reported iff BOTH hold (a duplicate re-handoff):
#   1. --latest-author == --me           (the newest context is mine)
#   2. --latest-epoch  >= now - window    (it is recent)
```

- [ ] **Step 6: Run the tests to verify all pass**

Run: `bash plugins/bitacora/scripts/test-collision-check.sh`
Expected: all `PASS` (the five new `self:` cases + all pre-existing cases), exit 0.

- [ ] **Step 7: Shellcheck**

Run: `shellcheck --severity=warning plugins/bitacora/scripts/collision-check.sh plugins/bitacora/scripts/test-collision-check.sh`
Expected: no output (clean).

- [ ] **Step 8: Commit**

```bash
git add plugins/bitacora/scripts/collision-check.sh plugins/bitacora/scripts/test-collision-check.sh
git commit -m "feat(handoff): add --self mode to collision-check.sh (self-collision rule)"
```

---

### Task 2: Wire the self-check into the handoff skill + config + manual acceptance

**Files:**
- Modify: `plugins/bitacora/skills/session-handoff/SKILL.md`
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

This is a prompt-driven spec change (no unit test; verified by manual acceptance + the Task 1
helper tests). Make the edits exactly.

- [ ] **Step 1: Add the self-check branch to the collision step**

In `plugins/bitacora/skills/session-handoff/SKILL.md`, find the paragraph that ends the
existing collision step:

```
If it prints `collision`, flag the ticket for the gate (step 4) and keep the colliding
`[CTX]`'s author, age, and a `Status`/`Next` excerpt to show there. **Lenient
throughout:** if the MCP is absent, the read fails, the user can't be resolved, or there
is no prior `[CTX]`, skip the check silently and draft as normal — collision detection
never blocks a handoff.
```

Insert immediately **after** it (new blank line, then):

````
**Self-collision (your own recent `[CTX]`).** The teammate check above fires only when the
newest `[CTX]` is someone else's. When the newest `[CTX]` is **your own**, run the same helper
in `--self` mode to catch a duplicate re-handoff:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/collision-check.sh" --self \
  --me "<my-accountId>" \
  --latest-author "<latest-ctx-author-accountId>" \
  --latest-epoch "<latest-ctx-epoch>" \
  --window "<self_handoff_window>"   # default 2h; see Configuration
# stdout: "collision" or "clear". --self reports "collision" iff the newest [CTX] is yours
# AND within the window.
```

The teammate and self checks are **mutually exclusive** (decided by whose `[CTX]` is newest),
so it stays one decision per ticket: run the teammate check when the newest `[CTX]` is a
teammate's, and the `--self` check when it is your own. If `--self` prints `collision`, flag the
ticket **`⚠ recent self-handoff`** for the gate (step 4). Same lenient rule — skip silently if
the MCP is absent, the user can't be resolved, or there is no prior `[CTX]`.
````

- [ ] **Step 2: Add the self-handoff gate block**

Find the paragraph that closes the collision gate section:

```
`Approve all` writes every non-collision ticket as-is and pauses on each `⚠ collision`
ticket for one of the three actions above before writing it.
```

Insert immediately **after** it (new blank line, then):

````
**Self-handoff-flagged tickets (`⚠ recent self-handoff`).** When the `--self` check fired,
show the age of your own last `[CTX]` and the window, and offer two per-ticket actions
(warn-only — never blocks the gate or the other tickets):

- **append** → write the drafted `[CTX]` as normal (the second handoff is legitimate).
- **skip** → do not write this ticket's `[CTX]`.

Example gate line:

```
[2] PROJ-5678  (branch fix/PROJ-5678-flaky-test)       → [CTX] drafted   ⚠ recent self-handoff
      Your own [CTX] here is 18m ago (within the 2h self-handoff window).
      [append] write this [CTX] anyway · [skip] don't write this ticket
```

`Approve all` also pauses on each `⚠ recent self-handoff` ticket for append/skip before writing it.
````

- [ ] **Step 3: Add the `self_handoff_window` config key**

Find the config line:

```
collision_window: 48h           # collision detection lookback (<N>h | <N>d); a teammate's [CTX] newer than this is flagged at the gate
```

Replace with:

```
collision_window: 48h           # collision detection lookback (<N>h | <N>d); a teammate's [CTX] newer than this is flagged at the gate
self_handoff_window: 2h         # self-collision lookback (<N>h | <N>d); a re-handoff within this of your own last [CTX] is flagged at the gate
```

- [ ] **Step 4: Verify the skill edits**

Run: `grep -nc "recent self-handoff\|--self\|self_handoff_window" plugins/bitacora/skills/session-handoff/SKILL.md`
Expected: ≥ 4 matches (the self-check branch, the gate marker block, the example line, the config key).

- [ ] **Step 5: Add the manual-acceptance item**

In `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, locate the `/handoff` collision check
item (search for `collision`). Add this item right after it, matching the file's existing
`- [ ] **<id> — <name>:**` bullet style (use the next free item id in that section):

```markdown
- [ ] **Self-collision:** Run `/bitacora:handoff` on a ticket whose newest `[CTX]` is your own
      and < 2h old → the gate shows `⚠ recent self-handoff` with `[append]` / `[skip]`;
      `append` writes the new `[CTX]`, `skip` does not. A handoff hours later (outside
      `self_handoff_window`) shows no marker. Teammate `⚠ collision` is unaffected.
```

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/skills/session-handoff/SKILL.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "feat(handoff): self-collision guard at the confirm gate + self_handoff_window config (#100)"
```

---

## Self-Review

**Spec coverage:**
- `--self` mode (rule: latest==me AND recent) → Task 1 Steps 3-4. ✓
- Reuses arg/window parsing + `--now` → Task 1 (no new parsing; same script). ✓
- Handoff one-decision-per-ticket self/teammate branch → Task 2 Step 1. ✓
- `⚠ recent self-handoff` gate marker + append/skip, warn-only → Task 2 Step 2. ✓
- `self_handoff_window` default 2h config → Task 2 Step 3. ✓
- Tests (`--self` cases, `--now`-injected, boundary, teammate-under-self) → Task 1 Step 1. ✓
- Manual-acceptance item → Task 2 Step 5. ✓
- Lenient skip behavior → Task 2 Step 1 (carried in the inserted prose). ✓
- Out of scope (content-diff, in-place edit) → not implemented, matching the spec. ✓

**Placeholder scan:** none — every code/spec step shows full content and exact old→new strings.

**Type/name consistency:** flag `--self`, var `self`, config `self_handoff_window`, marker
`⚠ recent self-handoff`, actions `append`/`skip` — used identically across Tasks 1-2, the
tests, and the spec. The helper output contract (`collision`/`clear`) is unchanged.

## Notes for landing

After both tasks pass, the branch is ready for a PR linked with `Closes #100` (the issue is
`ready-for-dev`, so the gate passes off the link — no `skip-issue-check`). Version bump +
CHANGELOG happen in a separate release PR per repo convention.
