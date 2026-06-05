# `--standup` Day-Bucketed Render Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat `Moved:` block in `/bitacora:status --standup` with a two-bucket, past-day-first render (previous worked day → Today) that names the past bucket Yesterday / a weekday / Earlier and shows multi-day tickets in both buckets.

**Architecture:** Add one pure-arithmetic shell helper (`standup-buckets.sh`) that maps a UTC epoch to its day index + weekday name; the prompt-driven `--standup` section of the session-status skill calls it to bucket each in-window `[CTX]` and label the past bucket. The render contract is verified by the existing deterministic fixture lint (no LLM, no Jira); the helper is unit-tested like its siblings.

**Tech Stack:** Bash (POSIX-ish, `set -uo pipefail`, integer arithmetic only — no GNU/BSD `date`), Markdown skill specs, grep-based fixture lint.

---

## Context the engineer needs

- This is the **Bitácora** plugin. The `/bitacora:status` behavior is **prompt-driven**: its
  logic lives as English spec in `plugins/bitacora/skills/session-status/SKILL.md`, not as code.
  "Implementing" the render means editing that spec precisely and updating the committed
  example renders + the lint that guards them.
- **Deterministic date logic is always a tested shell helper**, never inline prompt math.
  Precedent: `since-window.sh` (+ `test-since-window.sh`), `staleness-check.sh`
  (+ `test-staleness-check.sh`). We follow that pattern exactly.
- All date math is **UTC, pure integer arithmetic** to avoid GNU vs BSD `date` divergence.
  1970-01-01 was a Thursday (ISO weekday 4). For a day index `d = epoch / 86400`,
  `iso_weekday = ((d + 3) % 7) + 1` (Mon=1 … Sun=7). This formula already appears in
  `since-window.sh`.
- Tests are plain bash scripts run directly: `bash plugins/bitacora/scripts/test-*.sh`
  (exit 0 = pass). There is no Makefile/npm runner.
- Reference epochs reused across the date tests (UTC noon unless noted):
  `2024-01-04 Thu = 1704326400`, `2024-01-05 Fri = 1704456000`,
  `2024-01-06 Sat = 1704542400`, `2024-01-07 Sun = 1704628800`,
  `2024-01-08 Mon = 1704715200`, `2024-01-09 Tue = 1704801600`,
  `Fri midnight = 1704412800`.

## File Structure

- **Create** `plugins/bitacora/scripts/standup-buckets.sh` — given a UTC epoch, print
  `"<day_index> <Weekday>"`. Single responsibility: epoch → (day index, full weekday name).
- **Create** `plugins/bitacora/scripts/test-standup-buckets.sh` — deterministic unit tests
  for the helper.
- **Modify** `plugins/bitacora/skills/session-status/SKILL.md` — rewrite the `### --standup`
  render section (~lines 451-481), add a one-line read-model note in §4c, and retarget the
  three `--standup` `Moved:` references (Slack links + staleness marker) to "bucket entries".
- **Modify** `plugins/bitacora/skills/session-status/examples/multi-standup.txt` — re-author
  the committed example to the two-bucket render.
- **Modify** `plugins/bitacora/scripts/test-multi-status-fixtures.sh` — update the §6
  `--standup` assertions to the new render.
- **Modify** `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` — update item **M4** to the
  bucketed render.

The work is on branch `feature/standup-day-buckets` (already created; the design spec
`docs/superpowers/specs/2026-06-05-standup-day-buckets-design.md` is already committed there).

---

### Task 1: `standup-buckets.sh` helper (TDD)

**Files:**
- Create: `plugins/bitacora/scripts/standup-buckets.sh`
- Test: `plugins/bitacora/scripts/test-standup-buckets.sh`

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-standup-buckets.sh`:

```bash
#!/usr/bin/env bash
# Deterministic tests for standup-buckets.sh. Reference epochs (UTC noon) reused
# from test-since-window.sh:
#   2024-01-04 Thu, 2024-01-05 Fri, 2024-01-06 Sat, 2024-01-07 Sun,
#   2024-01-08 Mon, 2024-01-09 Tue.  Plus Friday UTC midnight as a boundary case.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SB="$DIR/standup-buckets.sh"
fail=0

check() {  # desc, expected, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$SB" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local code
  bash "$SB" "$@" >/dev/null 2>&1; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

check "Thu noon"               "19726 Thursday"  1704326400
check "Fri noon"               "19727 Friday"    1704456000
check "Sat noon"               "19728 Saturday"  1704542400
check "Sun noon"               "19729 Sunday"    1704628800
check "Mon noon"               "19730 Monday"    1704715200
check "Tue noon"               "19731 Tuesday"   1704801600
check "Fri midnight (boundary)" "19727 Friday"   1704412800

check_err "missing epoch"
check_err "non-numeric"  abc
check_err "negative"     -5

exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-standup-buckets.sh`
Expected: every `check` line FAILs (helper file does not exist yet), script exits non-zero.

- [ ] **Step 3: Write the helper**

Create `plugins/bitacora/scripts/standup-buckets.sh`:

```bash
#!/usr/bin/env bash
# standup-buckets.sh — map a UTC epoch to its day index and full weekday name.
#
# Usage:  standup-buckets.sh <epoch>
#   epoch : a timestamp in epoch seconds (non-negative integer).
# Output : prints "<day_index> <Weekday>" to stdout, e.g. "19727 Friday".
#          day_index = epoch / 86400 (UTC midnight buckets); Weekday is the full
#          English name (Monday .. Sunday). Exit 0.
# Errors : missing / non-numeric / negative epoch -> one-line reason on stderr, exit 2.
#
# Pure integer arithmetic in UTC, so there is no GNU/BSD `date` divergence. 1970-01-01
# was a Thursday (ISO weekday 4); for day index d, iso_weekday = ((d + 3) % 7) + 1
# (Mon=1 .. Sun=7).
#
# The --standup render (session-status SKILL.md §7) calls this once for "now" to learn
# today's day index, then once per in-window [CTX] `created` epoch; it buckets a [CTX]
# into Today (day index == today's) or the past bucket (day index < today's), and labels
# the past bucket Yesterday / <weekday> / Earlier from the distinct day indices it holds.
set -uo pipefail

epoch="${1:-}"
day=86400

if [[ -z "$epoch" ]]; then
  echo "standup-buckets: missing epoch (expected non-negative integer seconds)" >&2
  exit 2
fi
if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
  echo "standup-buckets: bad epoch '$epoch' (expected non-negative integer seconds)" >&2
  exit 2
fi

idx=$(( epoch / day ))
wd=$(( ( (idx + 3) % 7 ) + 1 ))   # 1=Mon .. 7=Sun
names=(_ Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
echo "$idx ${names[$wd]}"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/bitacora/scripts/test-standup-buckets.sh`
Expected: all lines `PASS`, script exits 0.

- [ ] **Step 5: Make the helper executable**

Run: `chmod +x plugins/bitacora/scripts/standup-buckets.sh plugins/bitacora/scripts/test-standup-buckets.sh`
(Match the existing scripts' mode — confirm with `ls -l plugins/bitacora/scripts/since-window.sh`.)

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/scripts/standup-buckets.sh plugins/bitacora/scripts/test-standup-buckets.sh
git commit -m "feat(status): add standup-buckets.sh — epoch → UTC day index + weekday"
```

---

### Task 2: Rewrite the `--standup` render spec

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`

- [ ] **Step 1: Replace the `### --standup` section**

Find the section beginning `### --standup — what moved in the window` (≈ line 451) through the
line ending `See` ... `examples/multi-standup.txt.` (≈ line 480). Replace the **entire** section
with:

````markdown
### --standup — what moved, by day

Resolve the window cutoff with the helper (deterministic, pure-arithmetic UTC):

```bash
cutoff=$("${CLAUDE_PLUGIN_ROOT}/scripts/since-window.sh" "<token>")
# <token> defaults to last-working-day; also accepts <N>d (1d, 2d, …).
# Prints a UTC epoch; a [CTX] whose `created` epoch is >= cutoff is "in the window".
```

(From the repo root the helper is `plugins/bitacora/scripts/since-window.sh`.)

**Read model — all in-window `[CTX]` (standup only).** Unlike every other lens, `--standup`
does **not** stop at the latest `[CTX]`. For each reporting ticket, take **every** compliant
`[CTX]` whose `created >= cutoff` (the comments are already in hand from §4c — just stop
discarding the earlier in-window ones; this is **no** extra API calls). A ticket with no
in-window `[CTX]` has **not moved**. This per-`[CTX]` read is scoped to `--standup`;
`--blocked`, the digest, and all single-ticket / epic paths keep
latest-`[CTX]`-authoritative.

**Bucket each in-window `[CTX]` by its UTC day.** Get today's day index once, and each
`[CTX]`'s day index + weekday name, from the helper:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/standup-buckets.sh" "<epoch>"   # prints "<day_index> <Weekday>"
```

- **Today** — `[CTX]` whose day index equals today's.
- **Past** — `[CTX]` whose day index is *less than* today's (still ≥ cutoff).

Render the **past bucket first, then Today** (chronological). **Omit an empty bucket.** Within
a bucket, order entries by `[CTX]` `created` descending. A ticket with in-window `[CTX]` on
**both** the past day and today appears in **both** buckets, each line carrying that day's own
`Did` / `Next` (within a bucket, the ticket's latest `[CTX]` in that bucket drives the line).

**Past-bucket header** — derived from the distinct day indices present in the past bucket
(call that set D; let `T` = today's day index):

- `|D| == 1` and that day is `T − 1` → **`Yesterday`**
- `|D| == 1` and that day is `< T − 1` (a weekend / non-working gap sits between) → that
  **weekday name** (e.g. `Friday`)
- `|D| > 1` (only possible with a wide `--since Nd`) → **`Earlier`**

`Today` is always literally `Today`. Render in the chosen lens (default `self`):

```
Standup — since <token> · <coverage>

<Yesterday | Friday | Earlier>:
- <KEY> "<title>" — <Jira status>
    Did: <Done / Status change from that day's [CTX]>
    Next: <first Next bullet>
    ⚠ <Risk or Blockers one-liner>            (only if present)
- …

Today:
- <KEY> "<title>" — <Jira status>
    Did: …
    Next: …
- …

No movement: <KEY, KEY, …>   (reporting tickets with no in-window [CTX]; omit if none)
```

If nothing moved, print `No [CTX] activity since <token> across <coverage>.` The window is
UTC-day-aligned (a deliberate v1 simplification — a Monday `last-working-day` run picks up
Friday + weekend, all under the `Friday` header); `--since 2d` widens it. The per-ticket
**staleness marker** (below) is printed **once per ticket**, on its entry in the **latest**
bucket it appears in (Today if present, else the past bucket). See
`examples/multi-standup.txt`.
````

- [ ] **Step 2: Add the read-model note to §4c**

Find this text in §4c (≈ line 148):

```
latest-`[CTX]` `created` timestamp from comment metadata (needed by `--blocked` staleness and
`--standup` windowing) and the ticket's `updated` timestamp (needed by the staleness marker
```

Replace it with:

```
latest-`[CTX]` `created` timestamp from comment metadata (needed by `--blocked` staleness and
`--standup` windowing — note `--standup` additionally consumes **every** in-window `[CTX]` per
ticket, not just the latest; see §7's `--standup`) and the ticket's `updated` timestamp (needed by the staleness marker
```

- [ ] **Step 3: Retarget the Slack ticket-key reference (step 5 block)**

Find (≈ line 291):

```
- **Ticket-key links in index entries** (the multi-ticket / aggregate `By ticket:` / `By child:`
  / `--blocked` / `--standup` `Moved:` lists): render the leading key as
```

Replace with:

```
- **Ticket-key links in index entries** (the multi-ticket / aggregate `By ticket:` / `By child:`
  / `--blocked` entries / `--standup` bucket entries under the day headers): render the leading key as
```

- [ ] **Step 4: Retarget the §7 Slack-only reference**

Find (≈ line 403):

```
(rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup` `Moved:`
entries — render its **leading key** as a Slack link `<https://<site>/browse/KEY|KEY>`, where
```

Replace with:

```
(rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup` bucket
entries (under the day headers) — render its **leading key** as a Slack link `<https://<site>/browse/KEY|KEY>`, where
```

- [ ] **Step 5: Retarget the §7 staleness-marker reference**

Find (≈ line 412):

```
helper call) using its latest-`[CTX]` `created` and its `updated` (both captured in §4c). When
it returns `stale Nd`, suffix that ticket's per-index entry — `By ticket:` / `By child:`,
`--blocked` entries, `--standup` `Moved:` entries — with ` · ⚠ behind <N>d`, after any status
```

Replace with:

```
helper call) using its latest-`[CTX]` `created` and its `updated` (both captured in §4c). When
it returns `stale Nd`, suffix that ticket's per-index entry — `By ticket:` / `By child:`,
`--blocked` entries, the `--standup` bucket entry in the ticket's latest bucket — with ` · ⚠ behind <N>d`, after any status
```

- [ ] **Step 6: Sanity-check the edits**

Run: `grep -n "Moved:" plugins/bitacora/skills/session-status/SKILL.md`
Expected: **no matches** (every `Moved:` reference has been retargeted to bucket wording).

Run: `grep -n "what moved, by day\|standup-buckets.sh\|all in-window" plugins/bitacora/skills/session-status/SKILL.md`
Expected: the new heading, the helper call, and the read-model note all appear.

- [ ] **Step 7: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): two-bucket day-grouped --standup render"
```

---

### Task 3: Re-author the committed `multi-standup.txt` example

**Files:**
- Modify: `plugins/bitacora/skills/session-status/examples/multi-standup.txt`

This fixture shares the canonical 4-ticket scenario (reporting: `AUTH-12`, `DATA-77`,
`UI-30`; no-`[CTX]`: `PERF-9`; coverage `4 tickets (3 reporting, 1 no [CTX])`). The new
render must exercise: a past bucket (`Yesterday`), a `Today` bucket, a ticket (`DATA-77`)
appearing in **both** buckets, and a `No movement:` tail. `PERF-9` must not appear.

- [ ] **Step 1: Overwrite the file**

Replace the entire contents of `plugins/bitacora/skills/session-status/examples/multi-standup.txt`
with:

```
Standup — since 1d · 4 tickets (3 reporting, 1 no [CTX])

Yesterday:
- AUTH-12 "OAuth callback handling" — In Review
    Did: handled the error-redirect edge case
    Next: address review comments
- DATA-77 "Feature store migration" — In Progress
    Did: cut over the read path to the new store; backfill verified
    Next: enable dual-write, monitor lag
    ⚠ drift PSI could exceed threshold under May traffic

Today:
- DATA-77 "Feature store migration" — In Progress
    Did: enabled dual-write; replication lag holding under 200ms
    Next: monitor 24h, then retire the old store

No movement: UI-30
```

- [ ] **Step 2: Verify the printed render stays bare (no links)**

Run: `grep -F "](http" plugins/bitacora/skills/session-status/examples/multi-standup.txt`
Expected: **no matches** (printed renders keep bare keys; Slack-linking is a separate path).

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-status/examples/multi-standup.txt
git commit -m "docs(status): two-bucket --standup example render"
```

---

### Task 4: Update the fixture lint and run the suite

**Files:**
- Modify: `plugins/bitacora/scripts/test-multi-status-fixtures.sh:85-89`

The current §6 block asserts the old single-block render. `AUTH-12` now moves (so it leaves
`No movement:`), and we add bucket-structure assertions.

- [ ] **Step 1: Replace the §6 `--standup` assertions**

Find this block (≈ lines 85-89):

```bash
# 6. --standup lens — since 1d window; only DATA-77 moved; no-[CTX] ticket absent
check_has    "$STD" "Standup — since 1d"            "standup header carries the window token"
check_has    "$STD" "DATA-77"                       "standup Moved lists DATA-77"
check_has    "$STD" "No movement: AUTH-12, UI-30"   "standup No-movement lists the non-movers"
check_hasnot "$STD" "PERF-9"                        "standup omits the no-[CTX] ticket from movement lines"
```

Replace it with:

```bash
# 6. --standup lens — since 1d window, two-bucket day render.
#    AUTH-12 + DATA-77 moved yesterday; DATA-77 also moved today (appears in BOTH
#    buckets); UI-30 has a [CTX] but none in-window; PERF-9 has no [CTX] at all.
check_has    "$STD" "Standup — since 1d"   "standup header carries the window token"
check_has    "$STD" "Yesterday:"           "standup renders the past (Yesterday) bucket"
check_has    "$STD" "Today:"               "standup renders the Today bucket"
check_has    "$STD" "AUTH-12"              "standup lists AUTH-12 (moved yesterday)"
check_has    "$STD" "No movement: UI-30"   "standup No-movement lists the in-window non-mover"
check_hasnot "$STD" "PERF-9"               "standup omits the no-[CTX] ticket from movement lines"
check_hasnot "$STD" "Moved:"               "standup uses day buckets, not a flat Moved: block"
# DATA-77 spans both buckets → it must appear at least twice.
if (( $(grep -c "DATA-77" "$STD") >= 2 )); then
  pass "standup shows DATA-77 in both buckets (>=2 occurrences)"
else
  bad "standup should show DATA-77 in both Yesterday and Today (>=2 occurrences)"
fi
```

- [ ] **Step 2: Run the fixture lint**

Run: `bash plugins/bitacora/scripts/test-multi-status-fixtures.sh`
Expected: all `PASS`, script exits 0. (This also re-checks the cross-fixture coverage line,
the key-universe guard, and the bare-render guard against the new example.)

- [ ] **Step 3: Run the full helper test suite (no regressions)**

Run:
```bash
for t in plugins/bitacora/scripts/test-standup-buckets.sh \
         plugins/bitacora/scripts/test-since-window.sh \
         plugins/bitacora/scripts/test-multi-status-fixtures.sh; do
  echo "== $t =="; bash "$t" || echo "SUITE FAILED: $t"
done
```
Expected: each prints only `PASS` lines and no `SUITE FAILED` marker.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/scripts/test-multi-status-fixtures.sh
git commit -m "test(status): assert two-bucket --standup fixture render"
```

---

### Task 5: Update the manual-acceptance checklist

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md:46-48`

- [ ] **Step 1: Replace item M4**

Find (≈ lines 46-48):

```
- [ ] **M4 — `--standup`:** `/bitacora:status --mine --standup --since 1d`. → Only tickets
      whose latest `[CTX]` is within 1 day under `Moved:`; the rest under `No movement:`;
      `last-working-day` default picks up Friday on a Monday run.
```

Replace with:

```
- [ ] **M4 — `--standup` (day buckets):** `/bitacora:status --mine --standup --since 1d`. →
      In-window `[CTX]` grouped into a past bucket then `Today`, past-first; the past header
      reads `Yesterday` (midweek), a weekday name when a weekend gap intervenes, or `Earlier`
      for a wide multi-day window. A ticket touched on both days appears in both buckets with
      each day's `Did`/`Next`. Non-movers fall under `No movement:`. A Monday
      `last-working-day` run files Friday's work under the `Friday` header.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs(status): manual-acceptance M4 for bucketed --standup"
```

---

## Self-Review

**Spec coverage** (against `2026-06-05-standup-day-buckets-design.md`):

- Two buckets, past-first, empty omitted, within-bucket sort desc → Task 2 Step 1. ✓
- Data-driven weekend-aware header (Yesterday / weekday / Earlier) → helper Task 1 + label
  rule Task 2 Step 1. ✓
- Multi-day ticket in both buckets via all-in-window `[CTX]` read → Task 2 Steps 1-2. ✓
- Render shape, empty-result line, staleness on latest bucket, Slack both-buckets → Task 2
  Steps 1, 4, 5. ✓
- Helper + tests + example + fixture lint → Tasks 1, 3, 4. ✓
- "Scoped to `--standup` only; other lenses unchanged" → stated in Task 2 Steps 1-2; the
  fixture lint still exercises the unchanged aggregate/blocked fixtures (Task 4 Step 2). ✓

**Placeholder scan:** no TBD/TODO; every code/spec/edit step shows full content and exact
old→new strings. ✓

**Type/name consistency:** helper output contract `"<day_index> <Weekday>"` is identical in
Task 1 (impl + test) and Task 2 (caller). Full weekday names (`Friday`, not `Fri`) are used
consistently in the helper, the header rule, and the `--standup` example. The header label
set `{Yesterday, <weekday>, Earlier}` matches between Task 2 and the M4 checklist. ✓

## Notes for landing

After all tasks pass, this branch (`feature/standup-day-buckets`) is ready for a PR per the
repo workflow (topic branch → PR → review → squash-merge; never push to `main` directly).
Filing the GitHub issue / labels is the maintainer's gate — do not self-apply approval labels.
The render-altitude behavior (`--for-*` × `--standup`) remains covered by manual acceptance,
not the deterministic lint.
