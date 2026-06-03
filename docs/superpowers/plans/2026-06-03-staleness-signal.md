# Staleness Signal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flag when a ticket's latest `[CTX]` is *behind* the ticket's own activity (drift), warning at `/resume` rehydration and marking it in `/status` renders.

**Architecture:** A pure, unit-testable shell helper (`staleness-check.sh`) decides `fresh` vs `stale Nd` from two epoch timestamps (`[CTX].created`, ticket `updated`) and a grace window. The `session-resume` and `session-status` skills extract those timestamps (both already fetch them, or nearly), call the helper, and surface the verdict. Stateless; mirrors `collision-check.sh` / `since-window.sh`.

**Tech Stack:** Bash (pure integer/UTC arithmetic, `set -uo pipefail`), GitHub Actions (`shellcheck` + matrix shell tests), Markdown skill prose, Atlassian MCP (`getJiraIssue`).

**Design doc:** `docs/superpowers/specs/2026-06-03-staleness-signal-design.md`

---

## File Structure

- **Create** `plugins/bitacora/scripts/staleness-check.sh` — decision helper. In: `--ctx-epoch`, `--updated-epoch`, `--grace`. Out: `fresh` / `stale <D>d`; exit 2 on bad args.
- **Create** `plugins/bitacora/scripts/test-staleness-check.sh` — deterministic fixture suite, CI-wired.
- **Modify** `.github/workflows/test.yml` — add a `staleness-check` step to the `shell-tests` job.
- **Modify** `plugins/bitacora/skills/jira-comment-format/SKILL.md` — add the shared `staleness_grace` config key.
- **Modify** `plugins/bitacora/skills/session-resume/SKILL.md` — §3 (fetch `updated`), §4 (stale banner).
- **Modify** `plugins/bitacora/skills/session-status/SKILL.md` — §4 + §4c (fetch `updated`), §5 (single-ticket `Freshness:` line), §7 (`⚠ behind Nd` index marker).
- **Modify** `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` — acceptance cases S1–S5.

---

## Task 1: `staleness-check.sh` decision helper (TDD)

**Files:**
- Create: `plugins/bitacora/scripts/staleness-check.sh`
- Test: `plugins/bitacora/scripts/test-staleness-check.sh`

- [ ] **Step 1: Write the failing test**

Create `plugins/bitacora/scripts/test-staleness-check.sh`:

```bash
#!/usr/bin/env bash
# Deterministic tests for staleness-check.sh. Fixed reference timestamps; no wall clock.
#   CTX = 2024-01-09 12:00:00 UTC = 1704801600
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SC="$DIR/staleness-check.sh"
fail=0

check() {  # desc, expected_stdout, args...
  local desc="$1" expected="$2"; shift 2
  local out code
  out="$(bash "$SC" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == 0 ]]; then
    echo "PASS: $desc → $out"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' (0)"; fail=1
  fi
}
check_err() {  # desc, args...
  local desc="$1"; shift
  local out code
  out="$(bash "$SC" "$@" 2>/dev/null)"; code=$?
  if (( code == 2 )); then echo "PASS: $desc → exit 2"
  else echo "FAIL: $desc → exit $code (expected 2)"; fail=1; fi
}

CTX=1704801600
D1=86400     # 1 day
D2=172800    # 2 days (the default grace)

check "updated == ctx → fresh"              fresh      --ctx-epoch "$CTX" --updated-epoch "$CTX"
check "updated < ctx (skew) → fresh"        fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX-3600))"
check "drift 1d within 2d grace → fresh"    fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX+D1))"
check "drift exactly 2d boundary → fresh"   fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX+D2))"
check "drift 2d+1s → stale 2d"              "stale 2d" --ctx-epoch "$CTX" --updated-epoch "$((CTX+D2+1))"
check "drift 4d → stale 4d"                 "stale 4d" --ctx-epoch "$CTX" --updated-epoch "$((CTX+4*D1))"
check "grace 12h, drift 1d → stale 1d"      "stale 1d" --ctx-epoch "$CTX" --updated-epoch "$((CTX+D1))" --grace 12h
check "grace 7d, drift 4d → fresh"          fresh      --ctx-epoch "$CTX" --updated-epoch "$((CTX+4*D1))" --grace 7d

check_err "missing --ctx-epoch"    --updated-epoch "$((CTX+D2+1))"
check_err "non-numeric --updated"  --ctx-epoch "$CTX" --updated-epoch abc
check_err "bad grace token"        --ctx-epoch "$CTX" --updated-epoch "$((CTX+D2+1))" --grace 2x

exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/bitacora/scripts/test-staleness-check.sh`
Expected: every line `FAIL` (exit 127 — the helper does not exist yet), script exits non-zero.

- [ ] **Step 3: Write the helper**

Create `plugins/bitacora/scripts/staleness-check.sh`:

```bash
#!/usr/bin/env bash
# staleness-check.sh — decide whether a ticket's latest [CTX] is "behind" the
# ticket's own activity (Bitácora staleness signal). Pure arithmetic on UTC epoch
# seconds; no Jira calls — the caller (session-resume / session-status) extracts the
# timestamps and passes them in.
#
# Usage:
#   staleness-check.sh --ctx-epoch <N> --updated-epoch <N> [--grace <token>]
#
#   --ctx-epoch     creation time (epoch s) of the ticket's latest compliant [CTX].
#   --updated-epoch the ticket's `updated` time (epoch s) from the Jira API.
#   --grace         drift tolerance as <N>h | <N>d (default 2d).
#
# Output : "fresh", or "stale <D>d" where D = floor((updated - ctx) / 86400). exit 0.
# Errors : missing/invalid args -> one-line reason on stderr, exit 2.
#
# Stale iff: updated > ctx AND (updated - ctx) > grace. Magnitude D is whole days of
# drift. updated <= ctx (the [CTX] is the latest activity, or clock skew) -> fresh.
set -uo pipefail

ctx="" updated="" grace="2d"

while (( $# )); do
  case "$1" in
    --ctx-epoch)     ctx="${2:-}"; shift 2 ;;
    --updated-epoch) updated="${2:-}"; shift 2 ;;
    --grace)         grace="${2:-}"; shift 2 ;;
    *) echo "staleness-check: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ "$ctx" =~ ^[0-9]+$ ]]     || { echo "staleness-check: --ctx-epoch must be epoch seconds" >&2; exit 2; }
[[ "$updated" =~ ^[0-9]+$ ]] || { echo "staleness-check: --updated-epoch must be epoch seconds" >&2; exit 2; }

# Resolve the grace token (<N>h | <N>d) to seconds.
case "$grace" in
  *h) unit=3600;  n="${grace%h}" ;;
  *d) unit=86400; n="${grace%d}" ;;
  *)  echo "staleness-check: bad --grace '$grace' (expected <N>h or <N>d)" >&2; exit 2 ;;
esac
if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )); then
  grace_sec=$(( n * unit ))
else
  echo "staleness-check: bad --grace '$grace' (expected <N>h or <N>d)" >&2; exit 2
fi

if (( updated <= ctx )); then echo fresh; exit 0; fi
drift=$(( updated - ctx ))
if (( drift > grace_sec )); then
  echo "stale $(( drift / 86400 ))d"
else
  echo fresh
fi
exit 0
```

Then make both executable:

```bash
chmod +x plugins/bitacora/scripts/staleness-check.sh plugins/bitacora/scripts/test-staleness-check.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/bitacora/scripts/test-staleness-check.sh`
Expected: every line `PASS:` (11 cases), script exits 0.

- [ ] **Step 5: Lint with shellcheck**

Run: `shellcheck --severity=warning plugins/bitacora/scripts/staleness-check.sh plugins/bitacora/scripts/test-staleness-check.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/scripts/staleness-check.sh plugins/bitacora/scripts/test-staleness-check.sh
git commit -m "feat(staleness): staleness-check.sh drift helper + fixture suite"
```

---

## Task 2: Wire the helper test into CI

**Files:**
- Modify: `.github/workflows/test.yml` (the `shell-tests` job step list)

- [ ] **Step 1: Add the test step**

In `.github/workflows/test.yml`, inside the `shell-tests` job's `steps:` list, add a step immediately after the `Run collision-check tests` step:

```yaml
      - name: Run staleness-check tests
        run: bash plugins/bitacora/scripts/test-staleness-check.sh
```

- [ ] **Step 2: Verify the step command runs locally**

Run: `bash plugins/bitacora/scripts/test-staleness-check.sh`
Expected: all `PASS`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: run staleness-check fixture suite"
```

---

## Task 3: Add the shared `staleness_grace` config key

**Files:**
- Modify: `plugins/bitacora/skills/jira-comment-format/SKILL.md` (the `## Configuration` YAML block)

Doc-only; verification is re-reading. `staleness_grace` is shared by `/resume` and `/status`, so it lives top-level beside `project_key_pattern`.

- [ ] **Step 1: Add the key**

In `plugins/bitacora/skills/jira-comment-format/SKILL.md`, find:

```yaml
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"   # top-level; shared by detection + JQL. DEFAULT only.
```

Add a line directly below it so it reads:

```yaml
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"   # top-level; shared by detection + JQL. DEFAULT only.
staleness_grace: 2d                          # top-level; drift tolerance (<N>h | <N>d) before a ticket's latest [CTX] is "behind" its `updated`. Used by /resume + /status.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/bitacora/skills/jira-comment-format/SKILL.md
git commit -m "feat(staleness): shared staleness_grace config key (default 2d)"
```

---

## Task 4: `/resume` — fetch `updated` and render the stale banner

**Files:**
- Modify: `plugins/bitacora/skills/session-resume/SKILL.md` (§3 read, §4 synthesize)

Doc-only; verification is re-reading + the manual cases in Task 6.

- [ ] **Step 1: Request the `updated` field in §3**

In `## 3. Read the ticket`, find:

```
`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments
using **strict** compliance per the READ rules in `bitacora:jira-comment-format`
```

Replace with:

```
`getJiraIssue` for the resolved key, **requesting comments** and the ticket's `updated`
field (top-level; needed by the staleness banner in §4). Extract `[CTX]` comments
using **strict** compliance per the READ rules in `bitacora:jira-comment-format`
```

- [ ] **Step 2: Add the staleness banner to §4**

In `## 4. Synthesize the briefing`, find this paragraph (just after the briefing-shape code block):

```
The `Last touched:` line is computed from the latest compliant `[CTX]`'s own `created`
timestamp (from the Jira API; never hand-typed). If the ticket has zero `[CTX]`
comments, the line reads `Last touched: never (no [CTX] yet)` instead of a date.
```

Insert the following new paragraph immediately **after** it:

````
**Staleness banner (drift check).** Using the latest compliant `[CTX]`'s `created` epoch
(already computed for `Last touched:`) and the ticket's `updated` epoch from §3, call the
decision helper with the shared `staleness_grace` (default `2d`, from the
`bitacora:jira-comment-format` Configuration):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/staleness-check.sh" \
  --ctx-epoch "<latest-ctx-created-epoch>" \
  --updated-epoch "<ticket-updated-epoch>" \
  --grace "<staleness_grace>"
# stdout: "fresh" or "stale <N>d"
```

If it returns `stale Nd`, prepend a one-line banner to the briefing, directly under the
header line (before `Last touched:`):

```
⚠ This context may be behind — the ticket was updated <N>d after this [CTX];
  re-check the ticket before relying on it.
```

Advisory only — never blocks the briefing. Skip the check entirely when the ticket has
zero `[CTX]` (the `Last touched: never` path) or the `updated` field is missing.
````

- [ ] **Step 3: Re-read §3 and §4**

Read `## 3` and `## 4` of `plugins/bitacora/skills/session-resume/SKILL.md` and confirm: the helper path is `${CLAUDE_PLUGIN_ROOT}/scripts/staleness-check.sh`, the flags are `--ctx-epoch` / `--updated-epoch` / `--grace` (matching Task 1), and the banner is prepended (not appended).

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/skills/session-resume/SKILL.md
git commit -m "feat(staleness): /resume warns when rehydrating behind-context"
```

---

## Task 5: `/status` — fetch `updated`, single-ticket `Freshness:` line, multi-ticket marker

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md` (§4, §4c, §5, §7)

Doc-only; verification is re-reading + the manual cases in Task 6.

- [ ] **Step 1: Capture `updated` in the single-ticket read (§4)**

In `## 4. Read the ticket (strict [CTX])`, find this bullet:

```
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
```

Insert a new bullet immediately **after** it:

```
- Also capture the ticket's `updated` timestamp (top-level field; request it alongside
  comments) — needed by the staleness `Freshness:` line in §5.
```

- [ ] **Step 2: Capture `updated` in the multi-ticket read (§4c)**

In `### 4c. Read the scope set (multi-ticket path)`, find:

```
authoritative), **no-`[CTX]`**, or **malformed**. For each reporting ticket also capture its
latest-`[CTX]` `created` timestamp from comment metadata (needed by `--blocked` staleness and
`--standup` windowing).
```

Replace with:

```
authoritative), **no-`[CTX]`**, or **malformed**. For each reporting ticket also capture its
latest-`[CTX]` `created` timestamp from comment metadata (needed by `--blocked` staleness and
`--standup` windowing) and the ticket's `updated` timestamp (needed by the staleness marker
in §7).
```

- [ ] **Step 3: Add the single-ticket `Freshness:` subsection (§5)**

In `## 5. Render for the selected mode`, find this paragraph (the lens-degradation note, just before the `### --for-self` heading):

```
A lens **degrades gracefully**: if the `[CTX]` lacks a section the lens would lead with, omit it silently (a UI ticket under `--for-ops` simply has no `Deploy/Ops:` to show).
```

Insert the following new subsection immediately **after** it (before `### --for-self`):

````
### Freshness (all single-ticket lenses)

Independent of the audience lens, run the drift check on the resolved ticket using the
latest compliant `[CTX]`'s `created` epoch and the ticket's `updated` epoch (from §4), with
the shared `staleness_grace` (default `2d`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/staleness-check.sh" \
  --ctx-epoch "<latest-ctx-created-epoch>" \
  --updated-epoch "<ticket-updated-epoch>" \
  --grace "<staleness_grace>"
```

If it returns `stale Nd`, append one line to the render (after the lens's body):

```
Freshness: behind <N>d (ticket updated after the latest [CTX])
```

Omit the line entirely when `fresh` (no positive-state noise), when the ticket has no
compliant `[CTX]`, or when `updated` is missing. This is read-only and advisory.
````

- [ ] **Step 4: Add the multi-ticket staleness marker (§7)**

In `## 7. Multi-ticket render (query lenses)`, find the **Ticket-key links (Slack only)** paragraph:

```
**Ticket-key links (Slack only).** Printed renders show **bare** keys. Only under
`--copy-as-slack` does each per-ticket **index entry** — the `By ticket:` / `By child:` lists
(rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup` `Moved:`
entries — render its **leading key** as a Slack link `<https://<site>/browse/KEY|KEY>`, where
`<site>` is the Atlassian site resolved in §3. Even in Slack, inline mentions (`Health:`,
`Top risks:`, `Dependencies:` edges) and the `Not yet reporting:` / `No movement:` tails stay
bare. See step 5's *Slack mrkdwn rendering*.
```

Insert the following new paragraph immediately **after** it:

````
**Staleness marker.** For each **reporting** ticket, run the drift check (§5's *Freshness*
helper call) using its latest-`[CTX]` `created` and its `updated` (both captured in §4c). When
it returns `stale Nd`, suffix that ticket's per-index entry — `By ticket:` / `By child:`,
`--blocked` entries, `--standup` `Moved:` entries — with ` · ⚠ behind <N>d`, after any status
and after the Slack key-link. Fresh / no-`[CTX]` tickets get no marker. The marker is
orthogonal to the query lens: it never changes `--blocked` / `--standup` selection, only
annotates the entries a lens already shows.
````

- [ ] **Step 5: Re-read the four edited sections**

Read §4, §4c, §5 (the new *Freshness* subsection), and §7 of `plugins/bitacora/skills/session-status/SKILL.md`. Confirm: the helper path and flags match Task 1, the single-ticket line reads `Freshness: behind <N>d`, the multi-ticket suffix reads `· ⚠ behind <N>d`, and both omit on `fresh` / no-`[CTX]`.

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(staleness): /status freshness line (single) + behind-Nd marker (multi)"
```

---

## Task 6: Manual-acceptance cases

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

- [ ] **Step 1: Append a staleness section**

At the end of `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, add:

```markdown
## Staleness signal (v1)

> Trivially solo-testable — it's your own `[CTX]` vs the ticket's `updated`. The drift math
> is unit-tested in `plugins/bitacora/scripts/test-staleness-check.sh`; the cases below are
> the live-render half.

- [ ] **S1 — /resume banner fires:** On a ticket with a compliant `[CTX]`, edit the ticket
      (change status / add a comment) so its `updated` is ≥ 2d after that `[CTX]`'s `created`
      (or use a ticket where that's already true). Run `/bitacora:resume <KEY>`. → A
      `⚠ This context may be behind …` banner appears under the header, before `Last touched:`.
- [ ] **S2 — /resume fresh, no banner:** On a ticket whose latest `[CTX]` is its most recent
      activity (or drift < 2d), run `/bitacora:resume <KEY>`. → No banner; briefing unchanged.
- [ ] **S3 — /status single-ticket line:** `/bitacora:status <KEY>` on an S1-style ticket. →
      A `Freshness: behind <N>d` line under the summary. On an S2-style ticket → no such line.
- [ ] **S4 — /status multi-ticket marker:** `/bitacora:status --mine` (or 2+ keys) including at
      least one stale ticket. → That ticket's `By ticket:` entry is suffixed ` · ⚠ behind <N>d`;
      fresh tickets in the same digest carry no marker. Confirms it composes with `--blocked` /
      `--standup` / `--for-*` without changing their selection.
- [ ] **S5 — no [CTX] / grace override:** A ticket with no `[CTX]` shows neither banner nor
      marker (it's "no context", not stale). Set `staleness_grace: 12h` in `.bitacora.yml` and
      re-run S1/S3 → tickets with ≥12h drift now flag.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs: manual-acceptance cases for the staleness signal (S1–S5)"
```

---

## Self-Review

**Spec coverage:**
- Drift signal (`updated − created > grace`, grace default 2d, magnitude floored days) → Task 1 helper + tests.
- `fresh` when no drift / `updated ≤ created` → Task 1 (cases 1–4).
- Shared `staleness_grace` config (top-level in jira-comment-format) → Task 3.
- `/resume` banner, fetch `updated`, prepend under header, skip when no `[CTX]` → Task 4.
- `/status` single-ticket `Freshness:` line → Task 5 step 3; multi-ticket `⚠ behind Nd` marker composing with lenses → Task 5 step 4; fetch `updated` (single + multi) → Task 5 steps 1–2.
- Edge cases (no `[CTX]`, `updated ≤ created`, missing `updated`) → Task 1 + the skip clauses in Tasks 4/5; manual S2/S5.
- Testable helper mirroring `since-window.sh` + CI wiring → Tasks 1 & 2.
- Solo-testable manual cases → Task 6.
- Deferrals (`/next`, statusline) → not implemented, by design.

**Placeholder scan:** none — every code/test/YAML block is complete; every command states expected output.

**Type/name consistency:** flag names (`--ctx-epoch`, `--updated-epoch`, `--grace`), outputs (`fresh` / `stale <D>d`), exit codes (0 / 2), helper path (`${CLAUDE_PLUGIN_ROOT}/scripts/staleness-check.sh`), config key (`staleness_grace`, default `2d`), and the human phrasings (`behind <N>d`, `Freshness:`, `· ⚠ behind <N>d`) are identical across the helper, the test, the CI step, and both skills.
