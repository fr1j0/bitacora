# Ticket-Key Links → `--copy-as-slack`-Only (v0.4.1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move ticket-key linking in the multi-ticket / aggregate `/status` renders from every printed render to the `--copy-as-slack` output only; printed renders show bare keys again.

**Architecture:** Inverts the v0.4.0 (#88) linking. Prose + fixtures + test, no executable code. Printed-render templates revert to bare `<KEY>`; the §7 rule and the Slack subsection say links are Slack-only; the 5 default fixtures revert to bare and a new `multi-aggregate-slack.txt` captures the Slack-linked form; the contract test swaps its printed-link assertions for a printed-bare guard + a Slack-link assertion.

**Tech Stack:** Markdown skill prose, bash (`test-multi-status-fixtures.sh`), GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-06-03-status-links-slack-only-design.md` · **Issue:** #90 · **Ships as:** v0.4.1

---

## File structure

| File | Change |
|------|--------|
| `plugins/bitacora/scripts/test-multi-status-fixtures.sh` | Add `SLK` var; replace §8/§9 link block with a printed-bare guard + Slack-link assertions. |
| `examples/multi-aggregate.txt`, `multi-blocked.txt`, `multi-standup.txt`, `epic-exec.txt`, `epic-eng.txt` | Revert index entries to **bare** keys. |
| `examples/multi-aggregate-slack.txt` | **New** — the `--copy-as-slack` digest with `<url|KEY>` index links. |
| `plugins/bitacora/skills/session-status/SKILL.md` | Invert §7 rule; revert 4 templates + §5 pointer to bare; update Slack bullet. |
| `CHANGELOG.md` | New **v0.4.1** entry. |
| `README.md`, `MANUAL-ACCEPTANCE.md` | Reword the v0.4.0 links mention / M9. |
| `.claude-plugin/marketplace.json`, `plugins/bitacora/.claude-plugin/plugin.json` | Version `0.4.0 → 0.4.1`. |

---

## Task 1: Test + fixtures (red → green)

**Files:** `plugins/bitacora/scripts/test-multi-status-fixtures.sh`; the 5 default fixtures; new `examples/multi-aggregate-slack.txt`.

- [ ] **Step 1: Add the `SLK` fixture var**

In `test-multi-status-fixtures.sh`, find:
```bash
EPG="$EX/epic-eng.txt"
```
Replace with:
```bash
EPG="$EX/epic-eng.txt"
SLK="$EX/multi-aggregate-slack.txt"
```

- [ ] **Step 2: Replace the §8/§9 link block (RED first)**

Find this exact block (the `# 8.` helper + 11 calls + the `# 9.` guards):
```bash
# 8. ticket-key links — each per-ticket INDEX entry leads with a [KEY](…/browse/KEY) link
check_linked() {  # file, key, label
  if grep -Fq -- "[$2](" "$1" && grep -Fq -- "/browse/$2)" "$1"; then pass "$3"
  else bad "$3 (key $2 not linked in $(basename "$1"))"; fi
}
check_linked "$AGG" "AUTH-12" "aggregate links AUTH-12 index entry"
check_linked "$AGG" "DATA-77" "aggregate links DATA-77 index entry"
check_linked "$AGG" "UI-30"   "aggregate links UI-30 index entry"
check_linked "$BLK" "AUTH-12" "blocked links AUTH-12 entry"
check_linked "$STD" "DATA-77" "standup links DATA-77 Moved entry"
check_linked "$EPE" "CHECKOUT-101" "epic-exec links CHECKOUT-101"
check_linked "$EPE" "CHECKOUT-102" "epic-exec links CHECKOUT-102"
check_linked "$EPE" "CHECKOUT-103" "epic-exec links CHECKOUT-103"
check_linked "$EPG" "CHECKOUT-101" "epic-eng links CHECKOUT-101"
check_linked "$EPG" "CHECKOUT-102" "epic-eng links CHECKOUT-102"
check_linked "$EPG" "CHECKOUT-103" "epic-eng links CHECKOUT-103"

# 9. index-only — tail / inline keys stay bare (guards the design decision)
check_hasnot "$AGG" "[PERF-9](" "aggregate leaves Not-yet-reporting PERF-9 bare"
check_hasnot "$STD" "[AUTH-12](" "standup leaves No-movement AUTH-12 bare"
check_hasnot "$STD" "[UI-30](" "standup leaves No-movement UI-30 bare"
```
Replace it with:
```bash
# 8. printed renders are BARE — links live only in the --copy-as-slack output (D1)
for f in "$AGG" "$BLK" "$STD" "$EPE" "$EPG"; do
  check_hasnot "$f" "](http" "printed render keeps bare keys ($(basename "$f"))"
done

# 9. --copy-as-slack output Slack-links the index keys as <…/browse/KEY|KEY> (D2); inline/tail bare (D3)
check_slack() {  # file, key, label
  if grep -Fq -- "/browse/$2|$2>" "$1"; then pass "$3"
  else bad "$3 (key $2 not Slack-linked in $(basename "$1"))"; fi
}
check_slack "$SLK" "AUTH-12" "slack digest Slack-links AUTH-12"
check_slack "$SLK" "DATA-77" "slack digest Slack-links DATA-77"
check_slack "$SLK" "UI-30"   "slack digest Slack-links UI-30"
check_hasnot "$SLK" "/browse/PERF-9|" "slack digest leaves Not-yet-reporting PERF-9 bare"
```

- [ ] **Step 3: Run, verify it FAILS**

Run: `bash plugins/bitacora/scripts/test-multi-status-fixtures.sh`
Expected: FAIL — §8 printed-bare guards fail (default fixtures still carry `](http` links) AND §9 Slack checks fail (`multi-aggregate-slack.txt` doesn't exist yet). Non-zero exit.

- [ ] **Step 4: Revert `multi-aggregate.txt` to bare**

Replace:
```
- [AUTH-12](https://example.atlassian.net/browse/AUTH-12) "OAuth token refresh" — In Progress (confidence: medium)
- [DATA-77](https://example.atlassian.net/browse/DATA-77) "Feature store migration" — In Progress (confidence: high)
- [UI-30](https://example.atlassian.net/browse/UI-30) "Settings page redesign" — In Review
```
with:
```
- AUTH-12 "OAuth token refresh" — In Progress (confidence: medium)
- DATA-77 "Feature store migration" — In Progress (confidence: high)
- UI-30 "Settings page redesign" — In Review
```

- [ ] **Step 5: Revert `multi-blocked.txt` to bare**

Replace:
```
- [AUTH-12](https://example.atlassian.net/browse/AUTH-12) "OAuth token refresh" — In Progress · stale 2d
```
with:
```
- AUTH-12 "OAuth token refresh" — In Progress · stale 2d
```

- [ ] **Step 6: Revert `multi-standup.txt` to bare**

Replace:
```
- [DATA-77](https://example.atlassian.net/browse/DATA-77) "Feature store migration" — In Progress
```
with:
```
- DATA-77 "Feature store migration" — In Progress
```

- [ ] **Step 7: Revert `epic-exec.txt` to bare**

Replace:
```
- [CHECKOUT-101](https://acme.atlassian.net/browse/CHECKOUT-101) "Serving cluster migration" — on track (high)
- [CHECKOUT-102](https://acme.atlassian.net/browse/CHECKOUT-102) "Ranking model v3" — in progress (medium)
- [CHECKOUT-103](https://acme.atlassian.net/browse/CHECKOUT-103) "Checkout summary panel" — at risk (low)
```
with:
```
- CHECKOUT-101 "Serving cluster migration" — on track (high)
- CHECKOUT-102 "Ranking model v3" — in progress (medium)
- CHECKOUT-103 "Checkout summary panel" — at risk (low)
```

- [ ] **Step 8: Revert `epic-eng.txt` to bare**

Replace:
```
- [CHECKOUT-101](https://acme.atlassian.net/browse/CHECKOUT-101) "Serving cluster migration" — In Progress; next: prod canary 24h, then 100% traffic; risk: —
- [CHECKOUT-102](https://acme.atlassian.net/browse/CHECKOUT-102) "Ranking model v3" — In Progress; next: shadow eval, then promote behind a flag; risk: drift PSI under peak
- [CHECKOUT-103](https://acme.atlassian.net/browse/CHECKOUT-103) "Checkout summary panel" — In Progress; next: truncation pass + design QA; risk: overflow on narrow viewports
```
with:
```
- CHECKOUT-101 "Serving cluster migration" — In Progress; next: prod canary 24h, then 100% traffic; risk: —
- CHECKOUT-102 "Ranking model v3" — In Progress; next: shadow eval, then promote behind a flag; risk: drift PSI under peak
- CHECKOUT-103 "Checkout summary panel" — In Progress; next: truncation pass + design QA; risk: overflow on narrow viewports
```

- [ ] **Step 9: Create `examples/multi-aggregate-slack.txt`**

Create `plugins/bitacora/skills/session-status/examples/multi-aggregate-slack.txt` with EXACTLY this content (the `--copy-as-slack` digest of the same 4-ticket scenario; Slack `mrkdwn` — `•` bullets U+2022, `<url|label>` links on index keys, inline/tail keys bare):
```
Scope: --mine — 4 tickets (3 reporting, 1 no [CTX])

Health: at risk — AUTH-12 blocked on an external API contract; DATA-77 carries an open drift risk
By ticket:
• <https://example.atlassian.net/browse/AUTH-12|AUTH-12> "OAuth token refresh" — In Progress (confidence: medium)
• <https://example.atlassian.net/browse/DATA-77|DATA-77> "Feature store migration" — In Progress (confidence: high)
• <https://example.atlassian.net/browse/UI-30|UI-30> "Settings page redesign" — In Review
Not yet reporting: PERF-9
```

- [ ] **Step 10: Run (PASS) + shellcheck**

Run:
```bash
bash plugins/bitacora/scripts/test-multi-status-fixtures.sh
shellcheck --severity=warning plugins/bitacora/scripts/test-multi-status-fixtures.sh
```
Expected: every line PASS, exit 0; shellcheck clean. (`EPE`/`EPG` stay used by the §8 loop; `SLK` used by §9.)

- [ ] **Step 11: Commit**

```bash
git add plugins/bitacora/scripts/test-multi-status-fixtures.sh plugins/bitacora/skills/session-status/examples/
git commit -m "test(status): printed renders bare; Slack fixture for linked form (#90)"
git rev-parse HEAD
```

---

## Task 2: SKILL.md — invert the rule, revert templates

**Files:** `plugins/bitacora/skills/session-status/SKILL.md`. No automated test; verify by read-back (Step 6). Use Edit with exact anchors.

- [ ] **Step 1: Invert the §7 Ticket-key links rule**

Find:
```
**Ticket-key links.** In every per-ticket **index entry** — the `By ticket:` / `By child:`
lists (rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup`
`Moved:` entries — render the entry's **leading key** as a link:
`[KEY](https://<site>/browse/KEY)`, where `<site>` is the Atlassian site resolved in §3.
Inline mentions of a key elsewhere — in `Health:`, `Top risks:`, `Dependencies:` edges, and
the `Not yet reporting:` / `No movement:` tails — stay **bare** (one clean link per ticket,
not 3–4). Under `--copy-as-slack`, use the Slack form `<https://<site>/browse/KEY|KEY>`
(see step 5's *Slack mrkdwn rendering*).
```
Replace with:
```
**Ticket-key links (Slack only).** Printed renders show **bare** keys. Only under
`--copy-as-slack` does each per-ticket **index entry** — the `By ticket:` / `By child:` lists
(rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup` `Moved:`
entries — render its **leading key** as a Slack link `<https://<site>/browse/KEY|KEY>`, where
`<site>` is the Atlassian site resolved in §3. Even in Slack, inline mentions (`Health:`,
`Top risks:`, `Dependencies:` edges) and the `Not yet reporting:` / `No movement:` tails stay
bare. See step 5's *Slack mrkdwn rendering*.
```

- [ ] **Step 2: Revert the `--blocked` template entry to bare**

Find:
```
- [<KEY>](https://<site>/browse/<KEY>) "<title>" — <Jira status> · stale <Nd>
```
Replace with:
```
- <KEY> "<title>" — <Jira status> · stale <Nd>
```

- [ ] **Step 3: Revert the `--standup` Moved template entry to bare**

Find:
```
- [<KEY>](https://<site>/browse/<KEY>) "<title>" — <Jira status>
```
Replace with:
```
- <KEY> "<title>" — <Jira status>
```

- [ ] **Step 4: Revert the §5 exec By-child template to bare**

Find:
```
- [<CHILD-KEY>](https://<site>/browse/<CHILD-KEY>) "<title>" — plain status (confidence)
```
Replace with:
```
- <CHILD-KEY "<title>" — plain status (confidence)>
```

- [ ] **Step 5: Revert the §5 eng By-child template to bare**

Find:
```
- [<CHILD-KEY>](https://<site>/browse/<CHILD-KEY>) "<title>" — Status; next: <first Next bullet>; risk: <Risk if any, else —>
```
Replace with:
```
- <CHILD-KEY "<title>" — Status; next: <first Next bullet>; risk: <Risk if any, else —>>
```

- [ ] **Step 6: Revert the §5 Aggregate-render pointer**

Find:
```
**Ticket-key links:** render each `By child:` / `By ticket:` entry's leading key as a link per
§7's *Ticket-key links* rule (the digest reuses these templates, so the rule is defined there).
Keys named inline in `Top risks:` / `Dependencies:` stay bare.
```
Replace with:
```
**Ticket-key links:** `By child:` / `By ticket:` entry keys print **bare**; they become Slack
links only under `--copy-as-slack`, per §7's *Ticket-key links (Slack only)* rule.
```

- [ ] **Step 7: Update the Slack subsection bullet**

Find:
```
- **Ticket-key links in index entries** (the multi-ticket / aggregate `By ticket:` / `By child:`
  / `--blocked` / `--standup` `Moved:` lists): `<https://<site>/browse/KEY|KEY>` instead of
  `[KEY](url)`.
```
Replace with:
```
- **Ticket-key links in index entries** (the multi-ticket / aggregate `By ticket:` / `By child:`
  / `--blocked` / `--standup` `Moved:` lists): render the leading key as
  `<https://<site>/browse/KEY|KEY>`. This is the **only** place keys are linked — printed
  renders leave them bare. Inline / tail keys stay bare even here.
```

- [ ] **Step 8: Read-back consistency check**

Confirm: the §7 rule, the §5 pointer, and the Slack bullet all agree — printed = bare, Slack = `<…|KEY>`, index-only, inline/tail bare. The four templates are bare `<KEY>` / `<CHILD-KEY …>`. No automated test; this read-back is the check. Each `Find` matched exactly once.

- [ ] **Step 9: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): ticket-key links are --copy-as-slack-only; printed renders bare (#90)"
git rev-parse HEAD
```

---

## Task 3: Docs + version bump (v0.4.1)

**Files:** `CHANGELOG.md`, `README.md`, `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, `.claude-plugin/marketplace.json`, `plugins/bitacora/.claude-plugin/plugin.json`.

- [ ] **Step 1: Add the v0.4.1 CHANGELOG entry**

In `CHANGELOG.md`, find:
```
## [v0.4.0] — 2026-06-02 · Multi-ticket `/status` — cross-ticket reads
```
Insert IMMEDIATELY BEFORE it:
```
## [v0.4.1] — 2026-06-03 · Ticket-key links are Slack-only

### Changed

- **Ticket-key links now appear only in `--copy-as-slack` output.** Printed `/bitacora:status`
  renders (digest, `--blocked`, `--standup`, epic rollup, every `--for-*` lens) show **bare**
  ticket keys again — the inline markdown links added in v0.4.0 were visual noise in a dense
  terminal glance. When you copy for Slack, each per-ticket index entry's key still renders as a
  `<https://<site>/browse/KEY|KEY>` link; inline / tail keys stay bare in both.
  ([#90](https://github.com/fr1j0/bitacora/issues/90))

```

- [ ] **Step 2: Reword the README "Today" line**

In `README.md`, find:
```
- **Today** — Phase 1 complete, plus **v0.4.0**: `handoff`, `resume`, `status` (single-ticket, epic rollup, and **multi-ticket** scopes — `--mine`/`--sprint`/`--jql` with `--blocked`/`--standup` lenses, keys rendered as links), `next`, `improve`, `help`, the `[CTX]` format, and an opt-in statusLine context meter.
```
Replace with:
```
- **Today** — Phase 1 complete, plus **v0.4.1**: `handoff`, `resume`, `status` (single-ticket, epic rollup, and **multi-ticket** scopes — `--mine`/`--sprint`/`--jql` with `--blocked`/`--standup` lenses; keys linked when copied for Slack), `next`, `improve`, `help`, the `[CTX]` format, and an opt-in statusLine context meter.
```

- [ ] **Step 3: Reword M9**

In `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`, find:
```
- [ ] **M9 — ticket-key links:** run a multi-ticket digest (or `--blocked` / `--standup` /
      epic rollup). → Each per-ticket index entry's leading key (`By ticket:` / `By child:` /
      `--blocked` / `--standup` `Moved:`) is a **clickable link** to the right ticket; inline keys
      (`Health`, `Top risks`, `Dependencies`, `No movement:`, `Not yet reporting:`) stay bare.
      With `--copy-as-slack`, the copied text uses `<url|KEY>` form.
```
Replace with:
```
- [ ] **M9 — ticket-key links (Slack-only):** run a multi-ticket digest (or `--blocked` /
      `--standup` / epic rollup). → The **printed** render shows **bare** keys (no inline links).
      Re-run with `--copy-as-slack`. → The copied Slack text renders each per-ticket index entry's
      key as `<url|KEY>`; inline / tail keys stay bare.
```

- [ ] **Step 4: Bump the versions**

In `.claude-plugin/marketplace.json`, find `      "version": "0.4.0",` and replace with `      "version": "0.4.1",`.
In `plugins/bitacora/.claude-plugin/plugin.json`, find `  "version": "0.4.0",` and replace with `  "version": "0.4.1",`.

- [ ] **Step 5: Validate + commit**

```bash
jq -e '.plugins[0].version=="0.4.1"' .claude-plugin/marketplace.json >/dev/null && jq -e '.version=="0.4.1"' plugins/bitacora/.claude-plugin/plugin.json >/dev/null && echo "versions 0.4.1 OK"
git add CHANGELOG.md README.md docs/superpowers/checklists/MANUAL-ACCEPTANCE.md .claude-plugin/marketplace.json plugins/bitacora/.claude-plugin/plugin.json
git commit -m "chore(release): v0.4.1 — ticket-key links Slack-only; docs + version bump (#90)"
git rev-parse HEAD
```

---

## Self-review

**Spec coverage:** D1 (printed bare) → Task 1 fixture reverts + Task 2 template reverts + §8 printed-bare guard. D2 (Slack `<url|KEY>`) → Task 1 Slack fixture + §9 assertion + Task 2 §7 rule/Slack bullet. D3 (index-only, inline/tail bare even in Slack) → Slack fixture leaves PERF-9 bare + §9 `check_hasnot` + rule wording. D4 (single-ticket URL lines untouched) → no single-ticket template edited. D5 (Slack fixture for coverage) → Task 1 Step 9 + §9. Version/docs → Task 3.

**Placeholder scan:** none — every step has exact anchor + replacement.

**Consistency:** the four reverted templates restore the exact pre-#88 bare forms (exec/eng keep their original outer-`<…>` placeholder wrapper). `SLK` defined before use; `check_slack`/`check_hasnot` defined before use; `EPE`/`EPG` stay referenced by the §8 loop (no shellcheck unused-var). The Slack fixture's `<…/browse/KEY|KEY>` matches the §9 `grep -F "/browse/KEY|KEY>"` assertion and the §7 rule's Slack form. The v0.4.0 CHANGELOG entry (and its "render as links" bullet) is left intact as history; v0.4.1 records the change.
