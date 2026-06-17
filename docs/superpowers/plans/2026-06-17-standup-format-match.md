# `--standup` format match (done/planned/blocked) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the `/bitacora:digest --standup` render to match the Claude Code `standup` skill — markdown `##`/`###` headings with a done/planned/blocked semantic split, replacing the day-bucket default.

**Architecture:** This is a skill-spec + fixture-contract change, not application code. The machine-checkable contract is `test-digest-fixtures.sh` asserting over the static `examples/multi-standup.txt`; the human/LLM-facing spec is `session-digest/SKILL.md`. We drive the change test-first: update the fixture assertions (red), regenerate the example to satisfy them (green), then bring the SKILL.md prose into line and retire the now-unused day-bucket helper.

**Tech Stack:** Markdown skill specs, Bash fixture-lint scripts, GitHub Actions (`.github/workflows/test.yml`).

**Spec:** `docs/superpowers/specs/2026-06-17-standup-format-match-design.md`

---

### Task 1: Update the fixture-test contract to the new render (red)

**Files:**
- Modify: `plugins/bitacora/scripts/test-digest-fixtures.sh:90-105`

- [ ] **Step 1: Replace the standup assertion block (#6)**

Replace lines 90-105 (the `# 6. --standup lens …` block through the `DATA-77 … >=2 occurrences` `if`/`fi`) with:

```bash
# 6. --standup lens — done/planned/blocked render (format-match).
#    AUTH-12 + DATA-77 have in-window [CTX] (DATA-77 spans two days, all Did
#    fold into Yesterday); UI-30 has a [CTX] but none in-window; PERF-9 has none.
check_has    "$STD" "## Standup —"       "standup uses the markdown title heading"
check_has    "$STD" "since 1d"           "standup subtitle carries the window token"
check_has    "$STD" "### Yesterday"      "standup renders the Yesterday (done) section"
check_has    "$STD" "### Today"          "standup renders the Today (planned) section"
check_has    "$STD" "### Blockers"       "standup renders the Blockers section"
check_has    "$STD" '`In Review`'        "standup tags per-ticket Jira status (inline code)"
check_has    "$STD" "AUTH-12"            "standup lists AUTH-12 (moved in-window)"
check_has    "$STD" "No movement: UI-30" "standup No-movement lists the in-window non-mover"
check_hasnot "$STD" "PERF-9"             "standup omits the no-[CTX] ticket"
check_hasnot "$STD" "Yesterday:"         "standup drops the old plain-label day bucket"
check_hasnot "$STD" "Moved:"             "standup uses sections, not a flat Moved: block"
```

Note the `'`In Review`'` argument is **single-quoted** so the backticks stay literal (double quotes would trigger command substitution).

- [ ] **Step 2: Run the fixture test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-digest-fixtures.sh`
Expected: FAIL — the still-old `multi-standup.txt` is missing `## Standup —`, `### Yesterday`, `### Today`, `### Blockers`, and `` `In Review` `` (several `FAIL:` lines from block #6; the script exits non-zero).

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/scripts/test-digest-fixtures.sh
git commit -m "test: assert done/planned/blocked standup render contract"
```

---

### Task 2: Regenerate the standup example fixture (green)

**Files:**
- Modify (overwrite): `plugins/bitacora/skills/session-digest/examples/multi-standup.txt`

- [ ] **Step 1: Replace the entire file contents**

```
## Standup — 2024-01-09
_since 1d · 4 tickets (3 reporting, 1 no [CTX])_

### Yesterday
- AUTH-12 "OAuth callback handling" `In Review` — handled the error-redirect edge case
- DATA-77 "Feature store migration" `In Progress` — cut over the read path to the new store; backfill verified; enabled dual-write, replication lag holding under 200ms

### Today
- AUTH-12 — address review comments
- DATA-77 — monitor 24h, then retire the old store

### Blockers
- DATA-77 — drift PSI could exceed threshold under May traffic

_No movement: UI-30_
```

This reflects the scenario in `test-digest-fixtures.sh` (lines 14-20): AUTH-12 + DATA-77 have in-window `[CTX]`; DATA-77's two days of `Did` fold into one Yesterday line (joined `created`-ascending with `; `); Today carries each ticket's latest `Next`; the lone `⚠` becomes the Blockers entry; UI-30 reports but did not move; PERF-9 (no `[CTX]`) is absent.

- [ ] **Step 2: Run the fixture test to verify it passes**

Run: `bash plugins/bitacora/scripts/test-digest-fixtures.sh`
Expected: PASS — all `PASS:` lines, script exits 0. (Confirms block #6 plus the cross-fixture coverage check `4 tickets (3 reporting, 1 no [CTX])`, the key-universe check, the bare-render `](http` check, and the `Parked debt:`-absence check all still hold.)

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-digest/examples/multi-standup.txt
git commit -m "feat(digest): done/planned/blocked standup example render"
```

---

### Task 3: Rewrite the SKILL.md `--standup` render section

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/SKILL.md:263-331`

- [ ] **Step 1: Replace the `### --standup …` section**

Replace from the `### --standup — what moved, by day` heading (line 263) through the line ending `` See `examples/multi-standup.txt`. `` (line 331) with:

````markdown
### --standup — done / planned / blocked

Resolve the window cutoff with the helper (deterministic, pure-arithmetic UTC):

```bash
cutoff=$("${CLAUDE_PLUGIN_ROOT}/scripts/since-window.sh" "<token>")
# <token> defaults to last-working-day; also accepts <N>d (1d, 2d, …).
# Prints a UTC epoch; a [CTX] whose `created` epoch is >= cutoff is "in the window".
```

(From the repo root the helper is `plugins/bitacora/scripts/since-window.sh`.)

**Read model — all in-window `[CTX]` (standup only).** Unlike every other lens, `--standup`
does **not** stop at the latest `[CTX]`. For each reporting ticket, take **every** compliant
`[CTX]` whose `created >= cutoff` (the comments are already in hand from §4 — just stop
discarding the earlier in-window ones; this is **no** extra API calls). A ticket with no
in-window `[CTX]` has **not moved**. This per-`[CTX]` read is scoped to `--standup`;
`--blocked`, the digest, and all epic paths keep latest-`[CTX]`-authoritative.

**Map the in-window `[CTX]` to three sections (no day-of-week bucketing).**

- **Yesterday (done)** — for each reporting ticket, the `Did` (Done / status-change) text
  from **all** its in-window `[CTX]`, joined in `created`-ascending order with `; `. One
  line per ticket: `<KEY> "<title>" `<Jira status>` — <joined Did>`. The inline-code status
  tag is printed **once per ticket, here only**.
- **Today (planned)** — the `Next` bullet(s) from the ticket's **latest** in-window `[CTX]`
  (earlier `Next`s are superseded). One line per ticket: `<KEY> — <Next>`. Omit a ticket
  whose latest in-window `[CTX]` carries no `Next`.
- **Blockers** — the `Risk` / `Blockers` one-liner from each ticket that has one, one bullet
  per ticket: `<KEY> — <one-liner>`. Always render the `### Blockers` heading; when no
  ticket has one, its body is `- _None_`.

Render in the chosen lens (default `self`):

```markdown
## Standup — <today's UTC date, YYYY-MM-DD>
_since <token> · <coverage>_

### Yesterday
- <KEY> "<title>" `<status>` — <all in-window Did, joined "; ">
- …

### Today
- <KEY> — <Next from the latest in-window [CTX]>
- …

### Blockers
- <KEY> — <Risk / Blockers one-liner>      (or `- _None_` when none)

_No movement: <KEY, …>_   (reporting tickets with no in-window [CTX]; omit if none)
```

The `## Standup — <date>` heading carries today's UTC date; the window token and coverage
move to the italic subtitle. `### Yesterday` / `### Today` are omitted only if genuinely
empty (a reporting ticket always has a `Did`, so Yesterday is effectively always present).
If nothing moved, print `No [CTX] activity since <token> across <coverage>.` The window is
UTC-day-aligned (a deliberate v1 simplification — a Monday `last-working-day` run picks up
Friday + the weekend under the same window); `--since 2d` widens it. The `### Yesterday`
heading stays literal regardless of window width — the exact span is in the subtitle. The
per-ticket **staleness marker** (below) is printed **once per ticket**, on its `### Yesterday`
line. See `examples/multi-standup.txt`.
````

- [ ] **Step 2: Verify no stale day-bucket references remain in the section**

Run: `grep -n "standup-buckets\|day index\|Friday\|Earlier\|two-bucket\|past bucket" plugins/bitacora/skills/session-digest/SKILL.md`
Expected: no matches inside the `--standup` section (lines ~263-320). A match in the Slack section (§ next task) is fine; this step only confirms the render section is clean.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-digest/SKILL.md
git commit -m "docs(digest): rewrite --standup render as done/planned/blocked"
```

---

### Task 4: Update the SKILL.md Slack rendering wording

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/SKILL.md` (Slack mrkdwn section, ~333-352)

- [ ] **Step 1: Add a heading-conversion bullet to the Slack bullet list**

Find the bullet list under `### Slack mrkdwn rendering (when `--copy-as-slack` is set)` (the bullets covering `*bold*`, angle-bracket links, plain bullets, no tables). Immediately after the `*bold*` bullet, add:

```markdown
- Headings have no Slack equivalent: `## Standup — <date>` → `*Standup — <date>*`, and each
  `### Yesterday` / `### Today` / `### Blockers` → its `*bold*` form
```

- [ ] **Step 2: Fix the day-headers phrasing in the ticket-key-links paragraph**

In the `**Ticket-key links (Slack only).**` paragraph, replace:

```
the `--standup` bucket
entries (under the day headers) — render its **leading key** as a Slack link
```

with:

```
the `--standup` per-ticket
entries (under the `Yesterday` / `Today` / `Blockers` headings) — render its **leading key** as a Slack link
```

- [ ] **Step 3: Verify the phrasing landed and no "day headers" remains**

Run: `grep -n "day headers\|bucket entries\|### Yesterday\|Headings have no Slack" plugins/bitacora/skills/session-digest/SKILL.md`
Expected: no `day headers` / `bucket entries` matches; the new `Headings have no Slack` bullet present.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-digest/SKILL.md
git commit -m "docs(digest): update Slack rendering notes for standup headings"
```

---

### Task 5: Retire the day-bucket helper and its CI step

**Files:**
- Delete: `plugins/bitacora/scripts/standup-buckets.sh`
- Delete: `plugins/bitacora/scripts/test-standup-buckets.sh`
- Modify: `.github/workflows/test.yml:40-41`

- [ ] **Step 1: Confirm the helper has no remaining live callers**

Run: `grep -rn "standup-buckets" plugins/bitacora/skills plugins/bitacora/commands plugins/bitacora/alias`
Expected: no matches (the SKILL.md reference was removed in Task 3; only the script files themselves and historical docs/CHANGELOG mention it).

- [ ] **Step 2: Delete the two scripts**

Run:
```bash
git rm plugins/bitacora/scripts/standup-buckets.sh plugins/bitacora/scripts/test-standup-buckets.sh
```

- [ ] **Step 3: Remove the CI step**

In `.github/workflows/test.yml`, delete these two lines (40-41):

```yaml
      - name: Run standup-buckets tests
        run: bash plugins/bitacora/scripts/test-standup-buckets.sh
```

- [ ] **Step 4: Run the full test suite to verify nothing else broke**

Run:
```bash
for t in validate-ctx since-window collision-check staleness-check digest-fixtures sync-bit-aliases statusline sync-statusline precompact-handoff-check; do
  echo "== $t =="; bash plugins/bitacora/scripts/test-$t.sh || echo "FAILED: $t"
done
```
Expected: every script ends with its `PASS` summary and no `FAILED:` line; `test-digest-fixtures.sh` in particular is all green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(digest): retire standup-buckets helper + CI step"
```

---

### Task 6: Update user-facing doc mentions

**Files:**
- Modify: `plugins/bitacora/alias/bit-digest.md:9`

- [ ] **Step 1: Fix the "by day" phrasing**

In `plugins/bitacora/alias/bit-digest.md`, replace `(what moved, by day)` with `(what moved — done / planned / blocked)`.

- [ ] **Step 2: Confirm no other doc promises day buckets**

Run: `grep -rn "by day\|day bucket\|Friday\|Earlier" README.md plugins/bitacora/README.md plugins/bitacora/commands plugins/bitacora/alias`
Expected: no `--standup`-related matches. (Other docs describe `--standup` as "what moved / what's stuck", which stays accurate.)

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/alias/bit-digest.md
git commit -m "docs: drop 'by day' from --standup alias blurb"
```

---

## Notes for the implementer

- **CHANGELOG + version bump are intentionally NOT in this plan.** They are handled as a
  single release step per the Bitácora release runbook (bump `marketplace.json` +
  `plugin.json` + `CHANGELOG.md`, PR with the `skip-issue-check` label, squash-merge,
  annotated tag, `gh release`) after this branch's content is reviewed and merged.
- **No live-render verification is automated here** — that is the M-series render half in
  `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`. If running manual acceptance, exercise
  `/bitacora:digest --mine --standup` and confirm the three-section shape, the per-ticket
  status tag on Yesterday, and the Slack copy.
- All work stays on branch `digest-standup-restyle`; open a PR to `main` when complete.
