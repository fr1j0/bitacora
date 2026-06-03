# Collision Detection on `/handoff` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warn at the `/handoff` confirm gate when a teammate's `[CTX]` posted within the last 48h would be buried by the current write, offering merge / proceed / skip.

**Architecture:** A pure, unit-testable shell helper (`collision-check.sh`) makes the fire/no-fire decision from author accountIds + epoch timestamps. The `session-handoff` skill extracts those inputs from the ticket's comments (it already can read them), calls the helper, and surfaces the result at the existing step-4 gate. Stateless — no per-ticket baseline file. Mirrors the repo's existing testable-helper pattern (`since-window.sh`, `validate-ctx.sh`).

**Tech Stack:** Bash (pure integer/UTC arithmetic, `set -uo pipefail`), GitHub Actions (`shellcheck` + matrix shell tests), Markdown skill prose, Atlassian MCP (`atlassianUserInfo`, `getJiraIssue`).

**Design doc:** `docs/superpowers/specs/2026-06-03-collision-detection-handoff-design.md`
**Tracking issue:** #93 (awaiting `ready-for-dev`)

---

## File Structure

- **Create** `plugins/bitacora/scripts/collision-check.sh` — pure decision helper. Input: current-user accountId, latest-`[CTX]` author + epoch, optional own-last-`[CTX]` epoch, now, window token. Output: `collision` / `clear` on stdout; exit 2 on bad args.
- **Create** `plugins/bitacora/scripts/test-collision-check.sh` — deterministic fixture suite (injected `--now`), CI-wired.
- **Modify** `.github/workflows/test.yml` — add a `collision-check` test step to the `shell-tests` job.
- **Modify** `plugins/bitacora/skills/session-handoff/SKILL.md` — step 2 (promote continuity-read to a performed read + collision check), step 4 (gate presentation + merge/proceed/skip actions), Configuration (`collision_window` key).
- **Modify** `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` — add live-render acceptance cases C1–C5.

---

## Task 1: `collision-check.sh` decision helper (TDD)

**Files:**
- Create: `plugins/bitacora/scripts/collision-check.sh`
- Test: `plugins/bitacora/scripts/test-collision-check.sh`

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-collision-check.sh`:

```bash
#!/usr/bin/env bash
# Deterministic tests for collision-check.sh. A fixed reference "now" is injected
# via --now so results never depend on the wall clock.
#   NOW = 2024-01-09 12:00:00 UTC = 1704801600
#   Default window 48h → cutoff = NOW - 172800 = 1704628800 (2024-01-07 12:00 UTC).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CC="$DIR/collision-check.sh"
fail=0

check() {  # desc, expected_stdout, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$CC" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local out code
  out="$(bash "$CC" "$@" 2>/dev/null)"; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

NOW=1704801600              # 2024-01-09 12:00 UTC
H3=$((NOW - 10800))         # 3h ago  (within 48h)
H2=$((NOW - 7200))          # 2h ago
CUTOFF=1704628800           # NOW - 48h (exact boundary)
JUST_OUT=$((CUTOFF - 1))    # 1s before the 48h boundary
TWO_DAYS=$((NOW - 172800))  # exactly 48h ago (== CUTOFF)

check "author=me → clear"                    clear     --me u1 --latest-author u1 --latest-epoch "$H3" --now "$NOW"
check "takeover (no mine-epoch), in window"  collision --me u1 --latest-author u2 --latest-epoch "$H3" --now "$NOW"
check "other newer than mine, in window"     collision --me u1 --latest-author u2 --latest-epoch "$H3" --mine-epoch "$H2" --now "$NOW"
check "mine newer than other → clear"        clear     --me u1 --latest-author u2 --latest-epoch "$H2" --mine-epoch "$H3" --now "$NOW"
check "other at 48h boundary → collision"    collision --me u1 --latest-author u2 --latest-epoch "$CUTOFF" --now "$NOW"
check "other 1s past window → clear"         clear     --me u1 --latest-author u2 --latest-epoch "$JUST_OUT" --now "$NOW"
check "1d window, 2d-old other → clear"      clear     --me u1 --latest-author u2 --latest-epoch "$TWO_DAYS" --window 1d --now "$NOW"
check "7d window, 2d-old other → collision"  collision --me u1 --latest-author u2 --latest-epoch "$TWO_DAYS" --window 7d --now "$NOW"

check_err "missing --me"             --latest-author u2 --latest-epoch "$H3" --now "$NOW"
check_err "missing --latest-author"  --me u1 --latest-epoch "$H3" --now "$NOW"
check_err "non-numeric latest-epoch" --me u1 --latest-author u2 --latest-epoch abc --now "$NOW"
check_err "bad window token"         --me u1 --latest-author u2 --latest-epoch "$H3" --window 48x --now "$NOW"

exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-collision-check.sh`
Expected: every line `FAIL` (the helper does not exist yet; `bash` cannot find `collision-check.sh`), script exits non-zero.

- [ ] **Step 3: Write the helper**

Create `plugins/bitacora/scripts/collision-check.sh`:

```bash
#!/usr/bin/env bash
# collision-check.sh — decide whether a teammate's [CTX] would be buried by a
# /handoff write (Bitácora collision detection). Pure arithmetic on UTC epoch
# seconds; no Jira calls — the caller (session-handoff skill) extracts the author
# accountIds and timestamps from the ticket's comments and passes them in.
#
# Usage:
#   collision-check.sh --me <accountId> --latest-author <accountId> \
#       --latest-epoch <N> [--mine-epoch <N>] [--now <N>] [--window <token>]
#
#   --me            accountId of the current Atlassian user (about to write).
#   --latest-author accountId who authored the ticket's most-recent [CTX].
#   --latest-epoch  creation time (epoch seconds) of that most-recent [CTX].
#   --mine-epoch    creation time of the current user's own most-recent [CTX] on
#                   the ticket; OMIT if the user has none (takeover case).
#   --now           reference "now" in epoch seconds (default: current time).
#                   Tests inject it for determinism.
#   --window        collision window as <N>h or <N>d (default 48h).
#
# Output : prints "collision" or "clear" to stdout, exit 0.
# Errors : missing/invalid args -> one-line reason on stderr, exit 2.
#
# A collision is reported iff ALL hold:
#   1. --latest-author != --me           (the newest context is someone else's)
#   2. --latest-epoch  >  --mine-epoch    (or --mine-epoch omitted: a takeover)
#   3. --latest-epoch  >= now - window    (the context is recent)
set -uo pipefail

me="" latest_author="" latest_epoch="" mine_epoch="" now="" window="48h"

while (( $# )); do
  case "$1" in
    --me)            me="${2:-}"; shift 2 ;;
    --latest-author) latest_author="${2:-}"; shift 2 ;;
    --latest-epoch)  latest_epoch="${2:-}"; shift 2 ;;
    --mine-epoch)    mine_epoch="${2:-}"; shift 2 ;;
    --now)           now="${2:-}"; shift 2 ;;
    --window)        window="${2:-}"; shift 2 ;;
    *) echo "collision-check: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -z "$me" ]]            && { echo "collision-check: missing --me" >&2; exit 2; }
[[ -z "$latest_author" ]] && { echo "collision-check: missing --latest-author" >&2; exit 2; }
[[ "$latest_epoch" =~ ^[0-9]+$ ]] || { echo "collision-check: --latest-epoch must be epoch seconds" >&2; exit 2; }
if [[ -n "$mine_epoch" && ! "$mine_epoch" =~ ^[0-9]+$ ]]; then
  echo "collision-check: --mine-epoch must be epoch seconds" >&2; exit 2
fi
[[ -z "$now" ]] && now="$(date +%s)"
[[ "$now" =~ ^[0-9]+$ ]] || { echo "collision-check: --now must be epoch seconds" >&2; exit 2; }

# Resolve the window token (<N>h | <N>d) to seconds.
case "$window" in
  *h) unit=3600;  n="${window%h}" ;;
  *d) unit=86400; n="${window%d}" ;;
  *)  echo "collision-check: bad --window '$window' (expected <N>h or <N>d)" >&2; exit 2 ;;
esac
if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )); then
  win=$(( n * unit ))
else
  echo "collision-check: bad --window '$window' (expected <N>h or <N>d)" >&2; exit 2
fi

# 1. Newest context is mine → no collision.
if [[ "$latest_author" == "$me" ]]; then echo clear; exit 0; fi
# 2. Newest context is not newer than my own last [CTX] → no collision.
if [[ -n "$mine_epoch" ]] && (( latest_epoch <= mine_epoch )); then echo clear; exit 0; fi
# 3. Recent enough?
cutoff=$(( now - win ))
if (( latest_epoch >= cutoff )); then echo collision; else echo clear; fi
exit 0
```

Then make it executable:

```bash
chmod +x plugins/bitacora/scripts/collision-check.sh plugins/bitacora/scripts/test-collision-check.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/bitacora/scripts/test-collision-check.sh`
Expected: every line `PASS:` (12 cases), script exits 0.

- [ ] **Step 5: Lint with shellcheck**

Run: `shellcheck --severity=warning plugins/bitacora/scripts/collision-check.sh plugins/bitacora/scripts/test-collision-check.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/scripts/collision-check.sh plugins/bitacora/scripts/test-collision-check.sh
git commit -m "feat(handoff): collision-check.sh decision helper + fixture suite"
```

---

## Task 2: Wire the helper test into CI

**Files:**
- Modify: `.github/workflows/test.yml` (the `shell-tests` job step list)

- [ ] **Step 1: Add the test step**

In `.github/workflows/test.yml`, inside the `shell-tests` job's `steps:` list, add a step immediately after the `Run since-window tests` step:

```yaml
      - name: Run collision-check tests
        run: bash plugins/bitacora/scripts/test-collision-check.sh
```

- [ ] **Step 2: Verify the step runs locally**

Run: `bash plugins/bitacora/scripts/test-collision-check.sh`
Expected: all `PASS`, exit 0 (same command CI will run).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: run collision-check fixture suite"
```

---

## Task 3: Wire collision detection into the `session-handoff` skill

**Files:**
- Modify: `plugins/bitacora/skills/session-handoff/SKILL.md` (step 2 continuity-read block; step 4 gate; Configuration block)

No automated test — this is skill prose. Verification is the manual-acceptance cases (Task 4) plus re-reading the edited sections. Make all three edits, then one commit.

- [ ] **Step 1: Replace the step-2 continuity-read paragraph with a performed read + collision check**

Find this paragraph (end of section `## 2. Draft a [CTX] per ticket`):

```
**Optional continuity-read (lenient):** before drafting, you may read the latest `[CTX]`
on the ticket via `getJiraIssue` (request the comments) to thread `Status`/`Next` and
avoid restating `Done`. Fall back gracefully if there is no prior `[CTX]` or the read
fails.
```

Replace it with:

```
**Continuity-read + collision check (lenient).** Before drafting, read the ticket's
comments via `getJiraIssue` to (a) thread `Status`/`Next` and avoid restating `Done`,
and (b) detect a **collision** — a teammate's recent `[CTX]` this handoff would bury.
Resolve the current user once via `atlassianUserInfo` → `accountId`. From the comments,
identify, using the `bitacora:jira-comment-format` read rules:

- the **most-recent `[CTX]`** — its author `accountId` and `created` timestamp;
- the current user's **own most-recent `[CTX]`** on the ticket, if any — its `created`.

Convert both timestamps to epoch seconds and call the decision helper:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/collision-check.sh" \
  --me "<my-accountId>" \
  --latest-author "<latest-ctx-author-accountId>" \
  --latest-epoch "<latest-ctx-epoch>" \
  [--mine-epoch "<my-last-ctx-epoch>"] \
  --window "<collision_window>"     # default 48h; see Configuration
# stdout: "collision" or "clear"; omit --mine-epoch when you have no prior [CTX] here.
```

If it prints `collision`, flag the ticket for the gate (step 4) and keep the colliding
`[CTX]`'s author, age, and a `Status`/`Next` excerpt to show there. **Lenient
throughout:** if the MCP is absent, the read fails, the user can't be resolved, or there
is no prior `[CTX]`, skip the check silently and draft as normal — collision detection
never blocks a handoff.
```

- [ ] **Step 2: Add the collision flag and actions to the step-4 confirm gate**

In section `## 4. Confirm gate (multi-ticket)`, the current example block is:

```
/bitacora:handoff — N tickets touched this session

[1] PROJ-1234  (branch feature/PROJ-1234-oauth)        → [CTX] drafted
[2] PROJ-5678  (branch fix/PROJ-5678-flaky-test)       → [CTX] drafted
[3] PROJ-9999  (mentioned while on feature/PROJ-1234)  → [CTX] drafted
+ 1 consolidated local scratch capture (via Remember)

Approve all · Review individually · Skip specific ("skip 3") · Cancel
```

Replace that block with (note the `⚠ collision` line on `[2]` and the per-ticket actions):

```
/bitacora:handoff — N tickets touched this session

[1] PROJ-1234  (branch feature/PROJ-1234-oauth)        → [CTX] drafted
[2] PROJ-5678  (branch fix/PROJ-5678-flaky-test)       → [CTX] drafted   ⚠ collision
      Latest [CTX] is by Alice Méndez, 3h ago (after your last update):
        Status: Auth flow blocked on token refresh — see PR #214
        Next:   Rotate the staging secret, then re-run e2e
      [merge] re-draft threading Alice's context · [proceed] write mine as-is · [skip]
[3] PROJ-9999  (mentioned while on feature/PROJ-1234)  → [CTX] drafted
+ 1 consolidated local scratch capture (via Remember)

Approve all · Review individually · Skip specific ("skip 3") · Cancel
```

Then, immediately after the existing four bullets describing the gate choices
(`- **Approve all** …` through `- **Cancel** …`), add this paragraph:

```
**Collision-flagged tickets (`⚠ collision`).** When the step-2 check fired, show the
colliding `[CTX]`'s author, age, and a `Status`/`Next` excerpt, and offer three
per-ticket actions (warn-only — a collision never blocks the gate or the other tickets):

- **merge** → re-read the colliding `[CTX]` in full and re-draft this ticket's `[CTX]`
  threading its `Status`/`Next` so the teammate's context is carried forward, not buried;
  re-show the merged draft before writing. If several teammates posted `[CTX]` after your
  last one, merge the **single most-recent** (highest-signal; full-set merge is a follow-on).
- **proceed** → write the drafted `[CTX]` as-is (you've judged the overlap benign).
- **skip** → do not write this ticket's `[CTX]`.

`Approve all` writes every non-collision ticket as-is and pauses on each `⚠ collision`
ticket for one of the three actions above before writing it.
```

- [ ] **Step 3: Document the `collision_window` config key**

In the `## Configuration` section, the current YAML block is:

```yaml
session_ticket_tracking:
  enabled: true                 # multi-ticket handoff awareness
  source: reconstruct           # reconstruct | recorder  (recorder = Phase 1.5 hook)
  attribution: branch_name      # touched-ticket → branch mapping strategy
  # activity_threshold: <n>     # Phase 1.5 — substantive-vs-incidental auto-filter; v1 shows all
jira_cloud_id: ""               # optional; if set, skips the multi-site select prompt
```

Add one line so it reads:

```yaml
session_ticket_tracking:
  enabled: true                 # multi-ticket handoff awareness
  source: reconstruct           # reconstruct | recorder  (recorder = Phase 1.5 hook)
  attribution: branch_name      # touched-ticket → branch mapping strategy
  # activity_threshold: <n>     # Phase 1.5 — substantive-vs-incidental auto-filter; v1 shows all
collision_window: 48h           # collision detection lookback (<N>h | <N>d); a teammate's [CTX] newer than this is flagged at the gate
jira_cloud_id: ""               # optional; if set, skips the multi-site select prompt
```

- [ ] **Step 4: Re-read the three edited sections**

Read steps 2, 4, and Configuration in `plugins/bitacora/skills/session-handoff/SKILL.md` and confirm: the helper path uses `${CLAUDE_PLUGIN_ROOT}/scripts/collision-check.sh`, the flag names match Task 1 exactly (`--me`, `--latest-author`, `--latest-epoch`, `--mine-epoch`, `--window`), and the default window reads `48h` everywhere.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-handoff/SKILL.md
git commit -m "feat(handoff): collision detection — performed continuity-read, gate warning, merge/proceed/skip"
```

---

## Task 4: Manual-acceptance cases

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

- [ ] **Step 1: Append a collision-detection section**

At the end of `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, add:

```markdown
## Collision detection on `/handoff` (v1)

> Needs a second Atlassian account (or a teammate) to post a `[CTX]` so the latest
> context on a ticket is authored by someone other than you. The fire/no-fire math is
> unit-tested in `plugins/bitacora/scripts/test-collision-check.sh`; the cases below are
> the live-render half (LLM extracting authors/timestamps + driving the gate).

- [ ] **C1 — fires (takeover):** Have the other account post a `[CTX]` on a ticket you
      have never `[CTX]`-ed, within 48h. Work the ticket, run `/bitacora:handoff`. → That
      ticket shows `⚠ collision` at the gate with the other author, age, and Status/Next
      excerpt; the three actions are offered.
- [ ] **C2 — merge:** On a C1 collision, choose **merge**. → Your `[CTX]` is re-drafted
      carrying the teammate's Status/Next forward; the merged draft is re-shown before
      writing; on write it does not erase their context.
- [ ] **C3 — proceed / skip:** On a C1 collision, choose **proceed** → your draft writes
      as-is; on a second run choose **skip** → that ticket is not written; other tickets in
      the same handoff are unaffected either way.
- [ ] **C4 — no fire (solo / stale / mine-newest):** (a) All `[CTX]` on the ticket are
      yours → no flag. (b) The teammate's `[CTX]` is older than 48h → no flag. (c) You
      posted a `[CTX]` after the teammate's → no flag.
- [ ] **C5 — lenient skip:** Disconnect/deny the Atlassian MCP (or use a ticket whose read
      fails), run handoff. → No collision flag, no error about the check; handoff proceeds
      exactly as the no-check path.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs: manual-acceptance cases for /handoff collision detection (C1–C5)"
```

---

## Self-Review

**Spec coverage:**
- Detection signal (author≠me + newer-than-mine + within window) → Task 1 helper logic + Task 3 step 1.
- 48h default window → Task 1 default + Task 3 step 3 config.
- Hook at step 2 (performed, lenient read) → Task 3 step 1.
- Gate presentation + merge/proceed/skip → Task 3 step 2.
- merge in v1 → Task 3 step 2; manual C2.
- Multi-teammate = most-recent only → Task 3 step 2 (merge bullet).
- Failure/edge (MCP absent, read fail, solo, takeover, out-of-window) → Task 1 cases + Task 3 step 1 lenient clause + manual C4/C5.
- Testable helper mirroring `since-window.sh` + CI wiring → Tasks 1 & 2.
- Manual acceptance cases → Task 4.
- Out of v1 (resume/status heads-up, seen-marker state) → not implemented, by design.

**Placeholder scan:** none — every code/test/YAML block is complete; every command has expected output.

**Type/name consistency:** flag names (`--me`, `--latest-author`, `--latest-epoch`, `--mine-epoch`, `--now`, `--window`), outputs (`collision` / `clear`), exit codes (0 / 2), helper path (`${CLAUDE_PLUGIN_ROOT}/scripts/collision-check.sh`), and the `48h` default are identical across the helper, the test, the CI step, and the skill prose.
