# Parked-Debt Rollup in the Digest Aggregate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close #85 by adding a *Parked debt* section to the digest aggregate (zero new flags), deepening Risk concentration with a recurrence flag, and retiring the four won't-do Phase B features (`--debt`/`--risk`/`--deps` flags, `--board`, saved-scope config).

**Architecture:** Bitácora is a prompt-as-code plugin — the "implementation" is `plugins/bitacora/skills/session-digest/SKILL.md` (the behavior spec the LLM executes), guarded by a deterministic fixture-contract lint (`plugins/bitacora/scripts/test-digest-fixtures.sh`) over committed example renders. Changes land in three layers: SKILL.md §5/§6 (signal + render), the `examples/` fixtures + lint (mechanical contract, TDD: assertions first), and `MANUAL-ACCEPTANCE.md` (live-render half).

**Tech Stack:** Markdown skill files, bash fixture lint (grep-based, no LLM, no Jira), git/gh.

**Design:** `docs/superpowers/specs/2026-06-09-digest-debt-rollup-design.md` (D1–D6). Branch: `feature/85-digest-debt-rollup` (already checked out, spec committed).

**Open question settled (spec §Open questions):** debt ledger lines are **grouped by ticket, in `By ticket:` / `By child:` order** (matches the aggregate's existing ordering).

---

### Task 1: §5 aggregate signals — Parked debt + risk-recurrence flag

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/SKILL.md:130-136` (§5 bullet list)

- [ ] **Step 1: Deepen the Risk concentration bullet (D3)**

In `plugins/bitacora/skills/session-digest/SKILL.md`, replace:

```markdown
- **Risk concentration** — the tickets carrying `Risk:` or `Blockers:`, listed risk-bearing first,
  one line each. Empty if none.
```

with:

```markdown
- **Risk concentration** — the tickets carrying `Risk:` or `Blockers:`, listed risk-bearing first,
  one line each. When the same surface or dependency recurs across 2+ tickets, flag it as
  **concentrated** — name the recurring surface once and list the tickets sharing it
  (`Concentrated: <surface> recurs across KEY-A + KEY-B`). Recurrence is evidence-based:
  only flag a surface the bullets actually share; never infer a theme. Empty if none.
```

- [ ] **Step 2: Add the Parked debt signal (D1/D2/D5)**

In the same §5 list, immediately after the **Dependency graph** bullet (before **Cost rollup**), insert:

```markdown
- **Parked debt** — every `[debt]`-tagged `Decisions:` bullet across the reporting tickets,
  grouped by ticket in `By ticket:` / `By child:` order — one ledger line each:
  `KEY · the deferred decision · follow-up KEY (only when the bullet names one)`. Empty if
  none. No new data is read — this is a pivot on the `[debt]` tags the strict read already
  captures. Same **no-invention** rule: only `[debt]` tags that actually exist; never
  synthesize a debt item.
```

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-digest/SKILL.md
git commit -m "feat(digest): §5 parked-debt aggregate signal + risk-recurrence flag (#85)"
```

---

### Task 2: §6 render — debt slots per lens, Slack rule

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/SKILL.md:160-200` (Aggregate render templates), `:308-333` (Slack block)

- [ ] **Step 1: Add the `Debt:` block to the `--for-exec` template**

In the `--for-exec` code block, between the `Dependencies:` block and the `Cost:` line, insert:

```
Debt:                                        (omit if none)
- <CHILD-KEY: parked tradeoff carried forward, business framing (+ follow-up KEY if named)>
```

- [ ] **Step 2: Add the `Parked debt:` block to the `--for-eng` template**

In the `--for-eng` code block, between the `Open risks / blockers:` block and the `Excluded:` line, insert:

```
Parked debt:                                 (omit if none)
- <CHILD-KEY · deferred decision — follow-up KEY if the bullet names one>
```

- [ ] **Step 3: Rewrite the `self` bullet and add the lens-slot rule**

Replace:

```markdown
- **self** — terse: `Health` line + the `By child` list (plus the `Not yet reporting:` / coverage tail — never drop no-`[CTX]` tickets).
```

with:

```markdown
- **self** — terse: `Health` line + the `By child` list, then a terse `Parked debt:` tail
  (one ledger line per `[debt]` item — your own parked debt; omit when empty), plus the
  `Not yet reporting:` / coverage tail — never drop no-`[CTX]` tickets.
```

Then, after the ops/pm/self bullet list (before the "All five keep the coverage figure…" line), add:

```markdown
**Parked debt is an oversight signal** — it renders only in `--for-exec` (`Debt:`, business
framing), `--for-eng` (`Parked debt:`, technical, with the follow-up key), and `--for-self`
(terse tail). `--for-pm` / `--for-ops` omit it (not their altitude). An empty ledger omits
the section entirely, like `Top risks:`. The recurrence-flagged risk lines render wherever
the lens's existing risk section already renders (`Top risks:` in exec, `Open risks /
blockers:` in eng) — the flag is a phrasing addition, not a new slot.
```

- [ ] **Step 4: Keep debt-ledger keys bare in Slack**

In the *Ticket-key links (Slack only)* paragraph, replace:

```markdown
Even in Slack, inline mentions (`Health:`, `Top risks:`, `Dependencies:` edges) and the
`Not yet reporting:` / `No movement:` tails stay bare.
```

with:

```markdown
Even in Slack, inline mentions (`Health:`, `Top risks:`, `Dependencies:` edges, the
`Debt:` / `Parked debt:` ledger lines) and the `Not yet reporting:` / `No movement:` tails
stay bare.
```

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-digest/SKILL.md
git commit -m "feat(digest): §6 debt render slots — exec/eng/self; pm/ops omit (#85)"
```

---

### Task 3: Retire the Phase-B forward references (D3/D4 closures)

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/SKILL.md:29-31` (§1 `--board`), `:52-54` (§1 Phase-B sentence), `:375` (error behavior)

- [ ] **Step 1: §1 — `--board` is won't-do, not "later phase"**

Replace:

```markdown
  passed — a single epic key keeps the epic-rollup behavior. `--board <id|name>` is
  **reserved for a later phase**: if passed, say it is not yet supported and stop (do not
  silently fall back).
```

with:

```markdown
  passed — a single epic key keeps the epic-rollup behavior. `--board <id|name>` is
  **not supported** (a board is a saved JQL — use `--jql`): if passed, say exactly that
  and stop (do not silently fall back).
```

- [ ] **Step 2: §1 — drop the `--debt`/`--risk` Phase-B promise**

Replace:

```markdown
The multi-ticket default audience is `self`. `--blocked`, `--standup`, and the aggregate all
honor an explicit `--for-*`; `--debt`/`--risk` will read naturally at `--for-eng`/`exec` when
they land in Phase B.
```

with:

```markdown
The multi-ticket default audience is `self`. `--blocked`, `--standup`, and the aggregate all
honor an explicit `--for-*`. There is no `--debt` / `--risk` / `--deps` query lens — parked
debt is an aggregate **section** (§5), and the risk / dependency views are the aggregate's
existing Risk-concentration and Dependency-graph signals.
```

- [ ] **Step 3: Error-behavior bullet**

Replace:

```markdown
- **`--board` passed:** not yet supported (Phase B); say so and stop.
```

with:

```markdown
- **`--board` passed:** not supported (a board is a saved JQL — use `--jql`); say so and stop.
```

- [ ] **Step 4: Verify no stale references remain**

Run: `grep -n -e "Phase B" -e "reserved for a later phase" plugins/bitacora/skills/session-digest/SKILL.md`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-digest/SKILL.md
git commit -m "feat(digest): retire Phase-B forward references — --board/--debt/--risk/--deps won't-do (#85)"
```

---

### Task 4: Lint first (TDD) — debt-ledger + recurrence assertions, expected to FAIL

**Files:**
- Modify: `plugins/bitacora/scripts/test-digest-fixtures.sh`

- [ ] **Step 1: Update scenario constants**

Replace lines 14–16 (the scenario-constants comment) with:

```bash
# Scenario constants (change here if the fixtures' scenario changes):
#   reporting: AUTH-12, DATA-77, UI-30   no-[CTX]: PERF-9   external dep: PLATFORM-4
#   debt: DATA-77 carries a [debt] decision with follow-up DATA-81 (multi scenario);
#         CHECKOUT-101 carries one with follow-up CHECKOUT-104 (epic scenario)
#   recurrence: "peak traffic" recurs across CHECKOUT-101 + CHECKOUT-102 (epic scenario)
#   negative: multi-aggregate-nodebt.txt is a 2-ticket no-debt scope (section omitted)
#   coverage:  "4 tickets (3 reporting, 1 no [CTX])"
```

Then after the `SLK=` line add, and extend `ALLOWED`:

```bash
NDB="$EX/multi-aggregate-nodebt.txt"
```

```bash
ALLOWED="AUTH-12 DATA-77 UI-30 PERF-9 PLATFORM-4 DATA-81"
```

- [ ] **Step 2: Fold the new fixture into the existing guards**

Section `# 0`: change the loop to `for f in "$AGG" "$BLK" "$STD" "$NDB"; do`.
Section `# 2` (terminology): change the loop to `for f in "$AGG" "$BLK" "$STD" "$NDB"; do`.
Section `# 3` (key universe): change the loop to `for f in "$AGG" "$BLK" "$STD" "$NDB"; do`.
Leave section `# 1` (coverage consistency) on the original three — the negative fixture is a different (2-ticket) scope.

- [ ] **Step 3: Add the debt + recurrence sections before `exit $fail`**

```bash
# 10. parked-debt ledger (D1/D5) — aggregate-only pivot on existing [debt] tags
check_has    "$AGG" "Parked debt:"      "aggregate (self) renders the Parked debt tail"
check_has    "$AGG" "follow-up DATA-81" "debt line carries the named follow-up"
check_has    "$SLK" "Parked debt:"      "slack render keeps the Parked debt section"
check_hasnot "$SLK" "/browse/DATA-81|"  "slack leaves debt-ledger keys bare (inline, not index)"
check_has    "$EPE" "Debt:"             "epic exec renders the Debt line"
check_has    "$EPG" "Parked debt:"      "epic eng renders the Parked debt line"
check_has    "$EPG" "CHECKOUT-104"      "epic eng debt line names the follow-up"
check_hasnot "$NDB" "Debt:"             "no-debt scenario omits the debt section entirely"
check_hasnot "$BLK" "Parked debt:"      "--blocked does not grow a debt section"
check_hasnot "$STD" "Parked debt:"      "--standup does not grow a debt section"

# 11. risk-concentration recurrence flag (D3) — surface named once, tickets listed
check_has "$EPE" "Concentrated: peak traffic recurs across CHECKOUT-101 + CHECKOUT-102" "exec flags the concentrated surface"
check_has "$EPG" "Concentrated: peak traffic recurs across CHECKOUT-101 + CHECKOUT-102" "eng flags the concentrated surface"
```

- [ ] **Step 4: Run to verify the new assertions FAIL (fixtures not yet updated)**

Run: `bash plugins/bitacora/scripts/test-digest-fixtures.sh; echo "exit=$?"`
Expected: `FAIL` lines for every new section-10/11 `check_has` (and `fixture missing: …multi-aggregate-nodebt.txt`), all pre-existing checks still `PASS`, `exit=1`.

Do **not** commit yet — the lint and fixtures land together in Task 5 so CI never sees a red intermediate commit.

---

### Task 5: Extend the fixtures, lint goes green

**Files:**
- Modify: `plugins/bitacora/skills/session-digest/examples/multi-aggregate.txt`
- Modify: `plugins/bitacora/skills/session-digest/examples/multi-aggregate-slack.txt`
- Modify: `plugins/bitacora/skills/session-digest/examples/epic-exec.txt`
- Modify: `plugins/bitacora/skills/session-digest/examples/epic-eng.txt`
- Create: `plugins/bitacora/skills/session-digest/examples/multi-aggregate-nodebt.txt`

- [ ] **Step 1: `multi-aggregate.txt` — add the self-lens debt tail**

Insert between the `By ticket:` block and `Not yet reporting: PERF-9`:

```
Parked debt:
- DATA-77 · dual-write to the legacy store kept through the migration — cutover cleanup deferred · follow-up DATA-81
```

- [ ] **Step 2: `multi-aggregate-slack.txt` — same section, mrkdwn bullet, key bare**

Insert between the `By ticket:` block and `Not yet reporting: PERF-9`:

```
Parked debt:
• DATA-77 · dual-write to the legacy store kept through the migration — cutover cleanup deferred · follow-up DATA-81
```

(Note: `DATA-77` / `DATA-81` stay **bare** here — ledger lines are inline mentions, not index entries.)

- [ ] **Step 3: `epic-exec.txt` — concentrated risk + `Debt:` block**

Replace the `Top risks:` block with:

```
Top risks:
- CHECKOUT-103: checkout layout overflows on narrow viewports, unresolved before release
- CHECKOUT-102: model drift could exceed threshold under peak traffic (mitigated by the soak)
- CHECKOUT-101: serving capacity headroom under peak traffic unverified until the canary completes
- Concentrated: peak traffic recurs across CHECKOUT-101 + CHECKOUT-102
```

Insert between the `Dependencies:` block and the `Cost:` line:

```
Debt:
- CHECKOUT-101: legacy REST serving path kept alive behind a flag — decommission parked (follow-up CHECKOUT-104)
```

- [ ] **Step 4: `epic-eng.txt` — recurrence in By child + Open risks, `Parked debt:` block**

Replace the `CHECKOUT-101` `By child:` line with:

```
- CHECKOUT-101 "Serving cluster migration" — In Progress; next: prod canary 24h, then 100% traffic; risk: capacity headroom under peak traffic
```

Replace the `Open risks / blockers:` block with:

```
Open risks / blockers:
- CHECKOUT-102: drift PSI could exceed threshold under peak traffic (mitigated by the soak)
- CHECKOUT-103: layout overflow on narrow viewports before release
- CHECKOUT-101: serving capacity headroom under peak traffic unverified until the canary completes
- Concentrated: peak traffic recurs across CHECKOUT-101 + CHECKOUT-102
```

Insert between the `Open risks / blockers:` block and the `Excluded:` line:

```
Parked debt:
- CHECKOUT-101 · legacy REST serving path kept behind a flag — decommission deferred · follow-up CHECKOUT-104
```

- [ ] **Step 5: Create `multi-aggregate-nodebt.txt` (negative — section omitted)**

Full file content:

```
Scope: 2 keys — 2 tickets (1 reporting, 1 no [CTX])

Health: on track — UI-30 in review, no open risks or blockers
By ticket:
- UI-30 "Settings page redesign" — In Review
Not yet reporting: PERF-9
```

- [ ] **Step 6: Run the lint to verify ALL checks pass**

Run: `bash plugins/bitacora/scripts/test-digest-fixtures.sh; echo "exit=$?"`
Expected: every line `PASS`, `exit=0`.

- [ ] **Step 7: Commit lint + fixtures together**

```bash
git add plugins/bitacora/scripts/test-digest-fixtures.sh plugins/bitacora/skills/session-digest/examples/
git commit -m "test(digest): debt-ledger + recurrence fixture contract; extend fixtures (#85)"
```

---

### Task 6: Manual-acceptance checklist — M10, M6 wording

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md:53-57` (M6), end of the `/digest` section (new M10)

- [ ] **Step 1: M6 — match the new `--board` message**

Replace:

```markdown
- [ ] **M6 — empty + single + board:** `/bitacora:digest --mine` matching zero → plain "matched nothing";
      a scope resolving to exactly one → single-ticket render; `--board X` → "not yet
      supported" and stop.
```

with:

```markdown
- [ ] **M6 — empty + single + board:** `/bitacora:digest --mine` matching zero → plain "matched nothing";
      a scope resolving to exactly one → single-ticket render; `--board X` → "not
      supported — use `--jql`" and stop.
```

- [ ] **Step 2: Add M10 after M9**

```markdown
- [ ] **M10 — parked-debt ledger:** Run `/bitacora:digest --mine` (or 2+ keys) and
      `/bitacora:digest EPIC-1` over scopes where at least one ticket's latest `[CTX]`
      carries a `[debt]`-tagged `Decisions:` bullet. → The aggregate shows the ledger
      (exec `Debt:` business framing, eng `Parked debt:` with the follow-up key, self
      terse tail), grouped by ticket; **only real `[debt]` tags** appear (no invention)
      and follow-up links are correct. The `Concentrated:` risk flag fires only when 2+
      tickets genuinely share a surface — never on an inferred theme. `--for-pm` /
      `--for-ops` omit the section; a scope with no `[debt]` tags renders no debt
      section at all.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs(acceptance): M10 parked-debt ledger; M6 --board wording (#85)"
```

---

### Task 7: Full verification + PR

**Files:** none new.

- [ ] **Step 1: Run the whole deterministic suite**

Run: `for t in plugins/bitacora/scripts/test-*.sh; do echo "== $t"; bash "$t" >/dev/null 2>&1 && echo OK || echo FAILED; done`
Expected: every script `OK` (the digest lint plus the collision/staleness/window suites — confirms no cross-suite regression).

Then run the digest lint once more verbosely: `bash plugins/bitacora/scripts/test-digest-fixtures.sh`
Expected: all `PASS`, exit 0.

- [ ] **Step 2: Review the branch**

Run: `git log --oneline main..HEAD && git diff main --stat`
Expected: the spec commit + 5 implementation commits; changes confined to `SKILL.md`, `examples/`, `test-digest-fixtures.sh`, `MANUAL-ACCEPTANCE.md`, this plan.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feature/85-digest-debt-rollup
gh pr create --title "feat(digest): parked-debt rollup in the aggregate — closes #85 (re-scoped, no new flags)" --body "$(cat <<'EOF'
Closes #85 per the approved re-scope (docs/superpowers/specs/2026-06-09-digest-debt-rollup-design.md).

## What ships
- **Parked debt** aggregate signal (§5): every `[debt]`-tagged `Decisions:` bullet across the scope → one ledger, grouped by ticket, follow-up key carried when named. Computed in the shared signals, so epic rollup and multi-ticket scope both get it (D2). Zero new flags (D1).
- **Risk concentration recurrence flag** (§5/D3): `Concentrated: <surface> recurs across KEY-A + KEY-B` when 2+ tickets share a surface — evidence-based, never inferred.
- **Render slots** (§6): exec `Debt:` (business framing), eng `Parked debt:` (with follow-up), self terse tail; pm/ops omit; empty ledger omits the section. Slack render keeps ledger keys bare (inline, not index).

## Closed as won't-do (from #85's original five)
- `--debt` / `--risk` / `--deps` query lenses — covered by the aggregate sections (D1/D3)
- `--board` — a board is a saved JQL; `--jql` covers it (D4). Skill + M6 wording updated from "not yet supported (Phase B)" to "not supported".
- Saved-scope config (`digest.default_board` / `digest.default_jql`) — dropped (D4)

## Tests
- `test-digest-fixtures.sh`: +12 assertions (debt ledger in aggregate/slack/epic renders, bare Slack ledger keys, recurrence flag, no-debt negative fixture, query lenses unchanged); full suite green.
- `MANUAL-ACCEPTANCE.md`: new M10 (live-render honesty: real `[debt]` tags only, correct follow-ups, concentration only on genuinely shared surfaces).
EOF
)"
```

Expected: PR opens against `main`. Do **not** self-apply labels (`ready-for-dev` is already on #85, owner-applied; the issue-gate check resolves from the `Closes #85` reference).

---

## Out of scope for this plan

- **Release** (version bump + CHANGELOG + tag) — separate release PR per the runbook, after this PR merges and review clears.
- Promoting debt to a `--debt` lens (D1 — revisit only if dogfooding shows the inline ledger swamps the digest).

## Self-review notes

- **Spec coverage:** D1/D2/D5 → Tasks 1–2; D3 → Tasks 1, 2, 5; D4 → Task 3; spec §Testing (fixtures, lint, manual item) → Tasks 4–6; spec §3 render slots table → Task 2; spec §4 Slack → Task 2 Step 4 + Task 5 Step 2. Open question (ordering) settled in header.
- **Negative check:** implemented as a dedicated `multi-aggregate-nodebt.txt` fixture (true empty-ledger omission) plus `--blocked`/`--standup` non-growth checks.
- **Type consistency:** ledger line shape `KEY · decision · follow-up KEY` used identically in §5 (Task 1), eng template (Task 2), and all fixtures (Task 5); the exec lens intentionally uses `KEY: prose (follow-up KEY)` business framing per the spec's render-slot table.
