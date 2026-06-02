# Multi-Ticket `/status` (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `/bitacora:status` to read across an arbitrary multi-ticket scope (`--mine` / `--sprint` / `--jql` / 2+ keys) and surface it through two query lenses (`--blocked`, `--standup`) plus the default portfolio aggregate — reusing the existing epic-rollup machinery, fully backward-compatible.

**Architecture:** A four-layer pipeline added behind the existing command — scope resolution (JQL → key list) → corpus read (strict `[CTX]` per key, reusing the §4b child-read discipline) → query lens (default aggregate / `--blocked` / `--standup`) → render (existing `--for-*` altitude). The only new executable code is a pure-arithmetic `since-window.sh` helper for the `--standup` window; everything else is skill prose + rendered-output fixtures. Multi-ticket mode activates only on a scope flag or 2+ keys, so `/status KEY` and `/status EPIC` are untouched.

**Tech Stack:** Bash 3.2+ (macOS/Linux), the `session-status` skill (Markdown prose), Atlassian Rovo MCP (`searchJiraIssuesUsingJql`, `getJiraIssue`), GitHub Actions CI (shellcheck + bash test scripts).

**Spec:** `docs/superpowers/specs/2026-06-02-multi-ticket-status-design.md`
**Issue:** #83

---

## File structure

| File | Responsibility | Action |
|------|----------------|--------|
| `plugins/bitacora/scripts/since-window.sh` | Resolve a `--since` token (`<N>d` / `last-working-day`) to a UTC cutoff epoch. Pure integer arithmetic, no `date -d/-v` divergence. | Create |
| `plugins/bitacora/scripts/test-since-window.sh` | Deterministic tests for the helper (injected `now`). | Create |
| `.github/workflows/test.yml` | Add the new test to the `shell-tests` job. | Modify |
| `plugins/bitacora/skills/session-status/SKILL.md` | The pipeline prose: arg parsing, §2a scope resolution, §4c corpus read, §7 query-lens renders, config, error edges, frontmatter. | Modify |
| `plugins/bitacora/skills/session-status/examples/multi-aggregate.txt` | Rendered expected output — default aggregate over a 4-ticket scope. | Create |
| `plugins/bitacora/skills/session-status/examples/multi-blocked.txt` | Rendered expected output — `--blocked`. | Create |
| `plugins/bitacora/skills/session-status/examples/multi-standup.txt` | Rendered expected output — `--standup --since 1d`. | Create |
| `plugins/bitacora/commands/status.md` | Document the new scopes + query lenses in the command surface. | Modify |
| `README.md` | Update the `/status` command-table row. | Modify |
| `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` | Multi-ticket acceptance items (M-series). | Modify |

**Shared scenario for the three fixtures** (keep them consistent): scope `--mine` resolves to **4 tickets** — `AUTH-12`, `DATA-77`, `UI-30` reporting a compliant `[CTX]`, and `PERF-9` with no `[CTX]` (the coverage bucket).
- `AUTH-12` "OAuth token refresh" — In Progress, confidence medium, latest `[CTX]` **2 days** old, **Blockers** (API contract) + a `Dependencies:` on `PLATFORM-4`.
- `DATA-77` "Feature store migration" — In Progress, confidence high, latest `[CTX]` **today** (in a 1d window), an open `Risk:`, no blockers.
- `UI-30` "Settings page redesign" — In Review, latest `[CTX]` **5 days** old, no blockers, outside a 1d window.
- `PERF-9` — no compliant `[CTX]`.

---

## Task 1: `since-window.sh` window helper (TDD, automated)

**Files:**
- Create: `plugins/bitacora/scripts/since-window.sh`
- Test: `plugins/bitacora/scripts/test-since-window.sh`
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-since-window.sh`:

```bash
#!/usr/bin/env bash
# Deterministic tests for since-window.sh. A fixed reference "now" is injected as
# arg 2 so results never depend on the wall clock. Reference dates (UTC):
#   2024-01-05 = Friday, 2024-01-06 = Saturday, 2024-01-07 = Sunday,
#   2024-01-08 = Monday,  2024-01-09 = Tuesday.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SW="$DIR/since-window.sh"
fail=0

check() {  # desc, expected_epoch, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$SW" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local out code
  out="$(bash "$SW" "$@" 2>/dev/null)"; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

NOW_TUE=1704801600   # 2024-01-09 12:00:00 UTC (Tuesday)
NOW_MON=1704715200   # 2024-01-08 12:00:00 UTC (Monday)
NOW_SUN=1704628800   # 2024-01-07 12:00:00 UTC (Sunday)
NOW_SAT=1704542400   # 2024-01-06 12:00:00 UTC (Saturday)
FRI_MID=1704412800   # 2024-01-05 00:00:00 UTC (Friday midnight)
MON_MID=1704672000   # 2024-01-08 00:00:00 UTC (Monday midnight)

check "1d from Tue noon"        "$((NOW_TUE - 86400))"   1d "$NOW_TUE"
check "2d from Tue noon"        "$((NOW_TUE - 172800))"  2d "$NOW_TUE"
check "7d from Tue noon"        "$((NOW_TUE - 604800))"  7d "$NOW_TUE"
check "last-working-day on Tue" "$MON_MID" last-working-day "$NOW_TUE"
check "last-working-day on Mon" "$FRI_MID" last-working-day "$NOW_MON"
check "last-working-day on Sun" "$FRI_MID" last-working-day "$NOW_SUN"
check "last-working-day on Sat" "$FRI_MID" last-working-day "$NOW_SAT"

check_err "unknown token"  next-week "$NOW_TUE"
check_err "zero days"      0d        "$NOW_TUE"
check_err "non-numeric d"  xd        "$NOW_TUE"
check_err "missing token"

exit $fail
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash plugins/bitacora/scripts/test-since-window.sh`
Expected: fails (the script does not exist yet) — non-zero exit, `FAIL` lines.

- [ ] **Step 3: Write the helper**

Create `plugins/bitacora/scripts/since-window.sh`:

```bash
#!/usr/bin/env bash
# since-window.sh — resolve a --standup --since token to a UTC cutoff epoch.
#
# Usage:  since-window.sh <token> [now_epoch]
#   token     : <N>d  (N>=1, e.g. 1d 2d 7d)  |  last-working-day
#   now_epoch : optional reference "now" in epoch seconds (default: current time).
#               Tests inject it for determinism.
# Output : prints the cutoff epoch (seconds) to stdout. A [CTX] comment whose
#          `created` epoch is >= the cutoff is "in the window". Exit 0.
# Errors : unknown/!malformed token -> one-line reason on stderr, exit 2.
#
# All math is pure integer arithmetic in UTC, so there is no GNU/BSD `date`
# divergence. 1970-01-01 was a Thursday (ISO weekday 4); for a day index
# d = epoch / 86400, iso_weekday = ((d + 3) % 7) + 1  (Mon=1 .. Sun=7).
# "last-working-day" walks back from yesterday to the most recent Mon–Fri and
# returns that day's UTC midnight (so a Monday standup picks up Friday + weekend).
set -uo pipefail

token="${1:-}"
now="${2:-$(date +%s)}"
day=86400

if [[ -z "$token" ]]; then
  echo "since-window: missing token (expected <N>d or last-working-day)" >&2
  exit 2
fi

case "$token" in
  last-working-day)
    today_mid=$(( (now / day) * day ))
    off=1
    while :; do
      d=$(( today_mid / day - off ))
      wd=$(( ( (d + 3) % 7 ) + 1 ))   # 1=Mon .. 7=Sun
      if (( wd >= 1 && wd <= 5 )); then break; fi
      off=$(( off + 1 ))
    done
    echo $(( today_mid - off * day ))
    ;;
  *d)
    n="${token%d}"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )); then
      echo $(( now - n * day ))
    else
      echo "since-window: bad day count in '$token' (expected <N>d, N>=1)" >&2
      exit 2
    fi
    ;;
  *)
    echo "since-window: unknown token '$token' (expected <N>d or last-working-day)" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Make it executable, run the test, verify it passes**

Run:
```bash
chmod +x plugins/bitacora/scripts/since-window.sh
bash plugins/bitacora/scripts/test-since-window.sh
```
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: ShellCheck both scripts (CI gate parity)**

Run: `shellcheck --severity=warning plugins/bitacora/scripts/since-window.sh plugins/bitacora/scripts/test-since-window.sh`
Expected: no warning-or-above output (clean exit). Fix any finding before committing.

- [ ] **Step 6: Wire the test into CI**

In `.github/workflows/test.yml`, the `shell-tests` job, add a step after the `Run [CTX] validator tests` step (the exact existing step block to anchor on):

```yaml
      - name: Run [CTX] validator tests
        run: bash plugins/bitacora/scripts/test-validate-ctx.sh
```

Insert immediately after it:

```yaml
      - name: Run since-window tests
        run: bash plugins/bitacora/scripts/test-since-window.sh
```

- [ ] **Step 7: Commit**

```bash
git add plugins/bitacora/scripts/since-window.sh plugins/bitacora/scripts/test-since-window.sh .github/workflows/test.yml
git commit -m "feat(status): since-window.sh helper for --standup windows (#83)"
```

---

## Task 2: Scope resolution + corpus read (the multi-ticket plumbing)

Adds arg parsing, the `--board` not-yet rejection, scope→key-list resolution, the `§4` single-path guard, the set corpus-read, config, error edges, and the frontmatter description. No lens output yet — this task makes `/status --mine` resolve and read a set, then (until Task 3) fall through to the default aggregate stub.

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`

- [ ] **Step 1: Extend §1 argument parsing**

In `SKILL.md`, find the `--copy-as-slack` bullet that ends §1 (anchor on its last line):

```
  mode flags. See step 5's *Slack mrkdwn rendering* sub-section for the rendering
  rules.
```

Insert immediately after it (before `## 2. Resolve the target ticket`):

```markdown
- **Scope (multi-ticket).** A scope selector switches `status` from a single ticket to a
  multi-ticket read: `--mine`, `--sprint`, `--jql "<JQL>"`, or **two or more**
  `project_key_pattern` keys in the arguments. Multi-ticket mode activates **iff** a scope
  flag is present or 2+ keys are passed — a single key, or an epic key, keeps the existing
  single-ticket / epic-rollup behavior verbatim. `--board <id|name>` is **reserved for a
  later phase**: if passed, say it is not yet supported and stop (do not silently fall back).
- **Query lens (multi-ticket only).** `--blocked` or `--standup` selects *what to surface*
  across the scope; with neither, the default is the portfolio aggregate (§7). Query lenses
  compose with the `--for-*` audience lens, which still selects altitude. A query lens in
  single-ticket mode is an error — name the multi-ticket scopes and stop. Two query lenses
  at once is an error.
- **`--since <token>` (only with `--standup`).** `<token>` ∈ `<N>d` (e.g. `1d`, `2d`) or
  `last-working-day` (the default). If passed without `--standup`, ignore it with a one-line
  note.

The multi-ticket default audience is `self`, like the single-ticket default. `--blocked`,
`--standup`, and the aggregate all honor an explicit `--for-*`; `--debt`/`--risk` will read
naturally at `--for-eng`/`exec` when they land in Phase B.
```

- [ ] **Step 2: Guard §4 so multi-ticket mode bypasses the single read**

Find the §4 heading and its first line:

```
## 4. Read the ticket (strict [CTX])

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments per
```

Insert a guard line between the heading and that paragraph:

```markdown
## 4. Read the ticket (strict [CTX])

**Multi-ticket mode (§2a) bypasses this section.** §4/§4a/§4b below are the single-ticket
and epic paths; when a scope set was resolved, skip straight to §4c.

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments per
```

- [ ] **Step 3: Add §2a scope resolution**

Find the end of §2 (anchor on its last bullet):

```
- **Nothing resolves:** ask for a key once (no nag); stop.
```

Insert after it (before `## 3. Resolve the Atlassian site`):

```markdown
### 2a. Resolve a multi-ticket scope (when scope mode is active)

When §1 detected a scope selector or 2+ keys, **skip §2's single-target resolution** and
resolve a *set* of keys. Resolve the Atlassian site first (§3 — needed to run JQL), then
build the list via `searchJiraIssuesUsingJql`, requesting `summary,issuetype,status`:

| Scope | JQL |
|-------|-----|
| explicit keys (2+) | `key IN (KEY-1, KEY-2, …) ORDER BY updated DESC` |
| `--mine` | `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC` |
| `--sprint` | `assignee = currentUser() AND sprint IN openSprints() ORDER BY updated DESC` |
| `--jql "<q>"` | the user's `<q>` verbatim; append `ORDER BY updated DESC` only if `<q>` has no `ORDER BY` |

**Cap the set** at `status.multi_fanout_cap` (default 25). If the JQL matched more, take the
first N in `updated DESC` order and **surface the truncation** in the render
(`showing N of M — narrow with --jql`); never silently drop. Edge cases:

- **Zero matches** → say so plainly and stop (e.g. `--mine matched no open tickets`).
- **Exactly one match** → read it as a single ticket (§4); a one-ticket set needs no aggregate.
- **JQL error** (bad `--jql`, unknown field) → surface the error verbatim and stop; no retry loop.
```

- [ ] **Step 4: Add §4c set corpus-read**

Find the end of §4b (anchor on its last line):

```
Child reads are independent; one child's 404 / permission error is isolated — count it as
unreadable and continue with the rest.
```

Insert after it (before `## 5. Render for the selected mode`):

```markdown
### 4c. Read the scope set (multi-ticket path)

Runs when §2a resolved a set. For each key, `getJiraIssue` **requesting comments** and
extract its latest compliant `[CTX]` per the strict READ rules in `bitacora:jira-comment-format`
— identical classification to §4b: **reporting** (has a compliant `[CTX]`, its latest is
authoritative), **no-`[CTX]`**, or **malformed**. For each reporting ticket also capture its
latest-`[CTX]` `created` timestamp from comment metadata (needed by `--blocked` staleness and
`--standup` windowing). Reads are independent — one key's 404 / permission error is isolated;
count it **unreadable** and continue. Carry the no-`[CTX]` / malformed / unreadable tallies
into every §7 render as the coverage line, exactly like §4b's excluded-count discipline.
```

- [ ] **Step 5: Add multi-ticket error edges**

Find this bullet in `## Error / edge behavior`:

```
- **No ticket resolved:** say so; suggest passing a key.
```

Insert after it:

```markdown
- **Scope matched zero tickets (multi-ticket):** say which scope and that it matched nothing;
  suggest narrowing or a different scope. No retry loop.
- **All reporting tickets have no `[CTX]` (multi-ticket):** render the coverage line and the
  per-ticket Status/title list for orientation; suggest `/bitacora:handoff` on them. Nothing
  to aggregate or filter.
- **`--board` passed:** not yet supported (Phase B); say so and stop.
- **Bad `--jql` / unknown field:** surface the JQL error verbatim; stop. No retry loop.
```

- [ ] **Step 6: Add the config key**

Find this line in the `status:` config block:

```
  epic_default_mode: exec    # lens for an epic target when no --for-* flag is given
```

Insert after it:

```
  multi_fanout_cap: 25       # max tickets read per multi-ticket scope; truncation is surfaced, never silent
```

- [ ] **Step 7: Update the skill frontmatter description**

Find the frontmatter `description:` (line 3) and replace it:

Old:
```
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary across five lenses — --for-self (terse recall), --for-eng (technical handoff), --for-ops (deploy/operational), --for-pm (plain-language stakeholder status), --for-exec (business/risk/cost). Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
```

New:
```
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary across five lenses (--for-self/eng/ops/pm/exec), roll up an epic across its children, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) through a query lens (--blocked, --standup) or the default portfolio aggregate. Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
```

- [ ] **Step 8: Re-read the edited sections for consistency**

Read §1, §2a, §4 guard, §4c, the error edges, and the config block back. Verify: section numbers referenced (§2a, §3, §4c, §7) all exist; `status.multi_fanout_cap` is the same name in §2a and config; activation rule (scope flag OR 2+ keys) is stated identically in §1 and §2a. No automated test for prose — this read-back is the check.

- [ ] **Step 9: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): multi-ticket scope resolution + corpus read (#83)"
```

---

## Task 3: Default portfolio aggregate over a scope

Reuses the epic Aggregate signals + Aggregate render, retargeted from "an epic's children" to "the resolved set." Adds §7 (the multi-ticket render section) with the default branch + its fixture.

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`
- Create: `plugins/bitacora/skills/session-status/examples/multi-aggregate.txt`

- [ ] **Step 1: Write the expected-output fixture first**

Create `plugins/bitacora/skills/session-status/examples/multi-aggregate.txt` (the shared 4-ticket scenario, `--for-self` default — self aggregate = Health line + By-ticket list + coverage):

```
Scope: --mine — 4 tickets (3 reporting, 1 no [CTX])

Health: at risk — AUTH-12 blocked on an external API contract; DATA-77 carries an open drift risk
By ticket:
- AUTH-12 "OAuth token refresh" — In Progress (confidence: medium)
- DATA-77 "Feature store migration" — In Progress (confidence: high)
- UI-30 "Settings page redesign" — In Review
Not yet reporting: PERF-9
```

- [ ] **Step 2: Add the §7 section header + default-aggregate branch**

In `SKILL.md`, find `## Error / edge behavior` and insert this **before** it (so §7 sits between §6 and the error section):

```markdown
## 7. Multi-ticket render (query lenses)

Runs only on the multi-ticket path (§2a + §4c). The **query lens** (§1) selects the pivot;
the `--for-*` **audience lens** still selects altitude. Facts only — the same no-invention
rule as §5. Every render carries a **coverage** line —
`N tickets (M reporting, K no [CTX], J malformed, U unreadable)`, dropping any zero terms —
plus any `showing N of M — narrow with --jql` truncation note from §2a.

### Default (no query flag) — portfolio aggregate

Compute the **Aggregate signals** exactly as the epic path does (health, confidence
distribution, risk concentration, dependency graph, cost rollup, coverage), but over the
resolved set instead of an epic's children, and render them with the **Aggregate render**
template for the chosen lens (default `self`). Only two things differ from the epic path:
the header names the **scope** rather than an epic, and there is no parent-epic link.

Header form by scope: `Scope: --mine`, `Scope: --sprint`, `Scope: <N> keys`, or
`Scope: custom JQL` — followed by ` — <coverage>`. See `examples/multi-aggregate.txt`
(the `--for-self` aggregate over a 4-ticket `--mine` scope).
```

- [ ] **Step 3: Verify the fixture matches the prose**

Read `examples/multi-aggregate.txt` and the self Aggregate render rule (§5 "**self** — terse: `Health` line + the `By child` list only") together. Confirm the fixture shows exactly Health + By-ticket + the `Not yet reporting` coverage tail, and the header uses `Scope: --mine — <coverage>`. Adjust the fixture if they diverge.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/skills/session-status/examples/multi-aggregate.txt
git commit -m "feat(status): default portfolio aggregate over a multi-ticket scope (#83)"
```

---

## Task 4: `--blocked` lens

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`
- Create: `plugins/bitacora/skills/session-status/examples/multi-blocked.txt`

- [ ] **Step 1: Write the expected-output fixture first**

Create `plugins/bitacora/skills/session-status/examples/multi-blocked.txt` (`--blocked`, default `self`; only AUTH-12 is blocked in the shared scenario):

```
Blocked — 4 tickets (3 reporting, 1 no [CTX])

- AUTH-12 "OAuth token refresh" — In Progress · stale 2d
    Blocked on: API contract for `/token/refresh` not finalized
    Waiting on: PLATFORM-4 (contract sign-off)
Clear: 2 of 3 reporting have no blockers/deps.
```

- [ ] **Step 2: Add the `--blocked` branch to §7**

In `SKILL.md`, find the end of the §7 default-aggregate branch (anchor on the line):

```
Header form by scope: `Scope: --mine`, `Scope: --sprint`, `Scope: <N> keys`, or
`Scope: custom JQL` — followed by ` — <coverage>`. See `examples/multi-aggregate.txt`
(the `--for-self` aggregate over a 4-ticket `--mine` scope).
```

Insert after it:

```markdown
### --blocked — what's stuck

Filter the set to tickets whose latest `[CTX]` carries a `Blockers:` **or** `Dependencies:`
section. Sort **most-stale first** (oldest latest-`[CTX]` `created`). Omit every ticket with
neither section. `stale <Nd>` = whole days between that ticket's latest-`[CTX]` `created` and
now. Render in the chosen lens (default `self`):

```
Blocked — <coverage>

- <KEY> "<title>" — <Jira status> · stale <Nd>
    Blocked on: <Blockers bullets>
    Waiting on: <Dependencies bullets — who/what>          (omit this line if no Dependencies)
- …
Clear: <count> of <M reporting> have no blockers/deps.
```

If **no** ticket in the set is blocked, print `Nothing blocked across <coverage>.` and stop.
`--for-pm`/`--for-exec` strip PR/commit hashes and frame `Waiting on:` as an ask; the other
lenses keep references. See `examples/multi-blocked.txt`.
```

- [ ] **Step 3: Verify fixture ↔ prose**

Confirm the fixture's shape matches the template: coverage header, one block per blocked ticket with `stale <Nd>`, `Blocked on:` / `Waiting on:`, and the `Clear:` tail. The identifier `/token/refresh` is backticked per the format skill's identifier rule.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/skills/session-status/examples/multi-blocked.txt
git commit -m "feat(status): --blocked query lens (#83)"
```

---

## Task 5: `--standup` lens (consumes since-window.sh)

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`
- Create: `plugins/bitacora/skills/session-status/examples/multi-standup.txt`

- [ ] **Step 1: Write the expected-output fixture first**

Create `plugins/bitacora/skills/session-status/examples/multi-standup.txt` (`--standup --since 1d`, default `self`; only DATA-77 moved within 1 day):

```
Standup — since 1d · 4 tickets (3 reporting, 1 no [CTX])

Moved:
- DATA-77 "Feature store migration" — In Progress
    Did: cut over the read path to the new store; backfill verified
    Next: enable dual-write, monitor lag
    ⚠ drift PSI could exceed threshold under May traffic
No movement: AUTH-12, UI-30
```

- [ ] **Step 2: Add the `--standup` branch to §7**

In `SKILL.md`, find the end of the §7 `--blocked` branch (anchor on the line):

```
`--for-pm`/`--for-exec` strip PR/commit hashes and frame `Waiting on:` as an ask; the other
lenses keep references. See `examples/multi-blocked.txt`.
```

Insert after it:

```markdown
### --standup — what moved in the window

Resolve the window cutoff with the helper (deterministic, pure-arithmetic UTC):

```bash
cutoff=$("${CLAUDE_PLUGIN_ROOT}/scripts/since-window.sh" "<token>")
# <token> defaults to last-working-day; also accepts <N>d (1d, 2d, …).
# Prints a UTC epoch; a [CTX] whose `created` epoch is >= cutoff is "in the window".
```

(From the repo root the helper is `plugins/bitacora/scripts/since-window.sh`.) A reporting
ticket **moved** if its latest compliant `[CTX]` has `created >= cutoff`. Render in the
chosen lens (default `self`):

```
Standup — since <token> · <coverage>

Moved:
- <KEY> "<title>" — <Jira status>
    Did: <one line from that [CTX]'s Done / Status change>
    Next: <first Next bullet>
    ⚠ <Risk or Blockers one-liner>                         (only if present)
- …
No movement: <KEY, KEY, …>   (reporting tickets whose latest [CTX] predates the cutoff; omit if none)
```

If nothing moved, print `No [CTX] activity since <token> across <coverage>.` The window is
UTC-day-aligned for `last-working-day` (a deliberate v1 simplification — a Monday run picks
up Friday + weekend); `--since 2d` widens it when a teammate's day boundary differs. See
`examples/multi-standup.txt`.
```

- [ ] **Step 3: Verify fixture ↔ prose and the helper invocation**

Confirm the fixture matches the template (`Moved:` blocks with Did/Next/optional ⚠, plus `No movement:` tail). Sanity-check the helper call resolves: `bash plugins/bitacora/scripts/since-window.sh 1d 1704801600` prints `1704715200`.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md plugins/bitacora/skills/session-status/examples/multi-standup.txt
git commit -m "feat(status): --standup query lens over the since-window (#83)"
```

---

## Task 6: Command surface + README docs

**Files:**
- Modify: `plugins/bitacora/commands/status.md`
- Modify: `README.md`

- [ ] **Step 1: Update the command body**

In `plugins/bitacora/commands/status.md`, find the paragraph ending:

```
Add `--copy-as-slack` to re-render the summary as Slack
`mrkdwn` and always copy it to the clipboard (skips the usual offer prompt).
```

Insert after it (before `Arguments: $ARGUMENTS`):

```markdown

For a **multi-ticket** read, pass a scope instead of one key — `--mine`, `--sprint`,
`--jql "<JQL>"`, or two or more keys — and optionally a query lens: `--blocked` (what's
stuck) or `--standup [--since 1d|2d|last-working-day]` (what moved). With no query lens, a
multi-ticket scope renders a portfolio aggregate. The `--for-*` audience lens still applies.
```

- [ ] **Step 2: Update the command frontmatter description**

In `plugins/bitacora/commands/status.md`, replace the frontmatter `description:`:

Old:
```
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary (--for-self/--for-eng/--for-ops/--for-pm/--for-exec). Read-only; prints and offers a clipboard copy.
```

New:
```
description: Synthesize one ticket's [CTX] (--for-self/eng/ops/pm/exec), roll up an epic, or read a multi-ticket scope (--mine/--sprint/--jql/2+ keys) via --blocked / --standup / aggregate. Read-only; prints and offers a clipboard copy.
```

- [ ] **Step 3: Update the README command-table row**

In `README.md`, find the `/bitacora:status` row of the commands table and replace it:

Old:
```
| `/bitacora:status` | Synthesize a ticket's latest `[CTX]` into an audience-tailored summary — PM (`--for-pm`), engineer (`--for-eng`), or self (`--for-self`, default). Read-only: prints the summary and offers a clipboard copy. |
```

New:
```
| `/bitacora:status` | Synthesize a ticket's latest `[CTX]` into an audience-tailored summary (`--for-self`/`-eng`/`-ops`/`-pm`/`-exec`), or roll up an epic. Point it at a **multi-ticket scope** (`--mine`, `--sprint`, `--jql`, or 2+ keys) for a portfolio aggregate or a query lens — `--blocked` (what's stuck) or `--standup` (what moved). Read-only: prints and offers a clipboard copy. |
```

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/commands/status.md README.md
git commit -m "docs(status): document multi-ticket scopes and query lenses (#83)"
```

---

## Task 7: Manual-acceptance checklist entries

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

- [ ] **Step 1: Append the multi-ticket acceptance block**

At the end of `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, append:

```markdown

## Multi-ticket `/status` (Phase A)

- [ ] **M1 — `--mine` aggregate:** `/bitacora:status --mine` with ≥2 assigned tickets. →
      Portfolio aggregate in the `self` lens; coverage line `N tickets (M reporting, …)`;
      no-`[CTX]` tickets land in `Not yet reporting`, never dropped.
- [ ] **M2 — explicit keys:** `/bitacora:status PROJ-1 PROJ-2`. → Multi-ticket mode (2+ keys),
      not single-ticket. `/bitacora:status PROJ-1` alone still renders one ticket.
- [ ] **M3 — `--blocked`:** `/bitacora:status --mine --blocked`. → Only tickets with
      `Blockers:`/`Dependencies:`, most-stale first, `stale Nd` correct; `Nothing blocked …`
      when none qualify.
- [ ] **M4 — `--standup`:** `/bitacora:status --mine --standup --since 1d`. → Only tickets
      whose latest `[CTX]` is within 1 day under `Moved:`; the rest under `No movement:`;
      `last-working-day` default picks up Friday on a Monday run.
- [ ] **M5 — cap disclosure:** A scope matching more than `multi_fanout_cap` (default 25). →
      `showing N of M — narrow with --jql`; no silent truncation.
- [ ] **M6 — empty + single + board:** `--mine` matching zero → plain "matched nothing";
      a scope resolving to exactly one → single-ticket render; `--board X` → "not yet
      supported" and stop.
- [ ] **M7 — audience compose:** `/bitacora:status --mine --blocked --for-exec`. → `--blocked`
      content rendered at exec altitude (PR/commit hashes stripped, asks framed).
- [ ] **M8 — backward compat:** `/bitacora:status EPIC-1` still rolls up the epic; a bare
      single key is unchanged from pre-Phase-A behavior.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs(status): multi-ticket manual-acceptance checklist (#83)"
```

---

## Self-review

**Spec coverage** — every spec section maps to a task:
- Layer 1 scope resolution (`--mine`/`--sprint`/`--jql`/keys, cap, "N of M") → Task 2 §2a.
- Layer 2 corpus read (strict, exclusion + no-context buckets) → Task 2 §4c.
- Layer 3 default aggregate → Task 3; `--blocked` → Task 4; `--standup` → Task 5.
- Layer 4 render (audience compose) → covered in each lens branch + M7.
- `since-window.sh` (the only executable unit) → Task 1, fully TDD'd + CI-wired.
- Strict discipline / honest coverage (D4) → §4c + every §7 coverage line + M1.
- Capped fan-out (D5) → §2a + M5. Read-only (D6) → no write path added anywhere. Phase A only (D7) → `--debt`/`--risk`/`--deps`/`--board` explicitly rejected/deferred (§1, error edges, M6). Skill-size (D8) → multi-ticket pipeline isolated in §2a/§4c/§7, single-ticket path untouched.
- Config (`multi_fanout_cap`) → Task 2 Step 6. Testing (golden fixtures + manual acceptance) → Tasks 3–5 fixtures + Task 7.
- Out-of-scope guards (no posting, no forecasting, no new command) → nothing in the plan adds them; `--board`/Phase-B lenses are explicitly deferred.

**Placeholder scan** — no TBD/TODO; every code/prose/fixture step carries its full content.

**Name consistency** — `status.multi_fanout_cap` identical in §2a and config; `since-window.sh` signature (`<token> [now_epoch]`, prints cutoff epoch, exit 2 on bad token) identical across Task 1 script, test, and the §7 `--standup` invocation; activation rule ("scope flag OR 2+ keys") stated identically in §1 and §2a; the shared 4-ticket scenario is consistent across the three fixtures (AUTH-12 blocked/2d, DATA-77 moved-today, UI-30 5d, PERF-9 no-`[CTX]`).

**Open questions from the spec** (settle during/after Phase A, not blockers): `--standup` "moved" is `[CTX]`-only (not Jira status transitions); default audience stays `self` for all lenses; `searchJiraIssuesUsingJql` comment-fetch fidelity — if it can't return comment bodies in one call, §4c's per-ticket `getJiraIssue` fallback already covers it and sets the practical cap.
