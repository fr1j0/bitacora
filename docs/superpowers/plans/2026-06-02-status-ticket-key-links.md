# Linkify Ticket Keys in Multi-Ticket `/status` Renders — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the leading ticket key of each per-ticket **index entry** in the multi-ticket / aggregate `/bitacora:status` renders a clickable markdown link to the Jira ticket.

**Architecture:** Pure prose + fixture change to the `session-status` skill — no executable code. The render templates (§7 multi-ticket lenses + §5 Aggregate render) gain a single "Ticket-key links" rule; the five rendered-output fixtures move to the linked form; the fixture-contract test gains a deterministic "index keys linked" assertion. Index entries only — inline mentions stay bare.

**Tech Stack:** Markdown skill prose, bash (`test-multi-status-fixtures.sh`), GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-06-02-status-ticket-key-links-design.md`
**Issue:** #87

---

## File structure

| File | Change |
|------|--------|
| `plugins/bitacora/scripts/test-multi-status-fixtures.sh` | Add "index key linked" + "tail stays bare" assertions; add the two epic fixtures. |
| `plugins/bitacora/skills/session-status/examples/multi-aggregate.txt` | Link the 3 `By ticket:` entries. |
| `plugins/bitacora/skills/session-status/examples/multi-blocked.txt` | Link the 1 `--blocked` entry. |
| `plugins/bitacora/skills/session-status/examples/multi-standup.txt` | Link the 1 `Moved:` entry. |
| `plugins/bitacora/skills/session-status/examples/epic-exec.txt` | Link the 3 `By child:` entries. |
| `plugins/bitacora/skills/session-status/examples/epic-eng.txt` | Link the 3 `By child:` entries. |
| `plugins/bitacora/skills/session-status/SKILL.md` | Add the canonical Ticket-key links rule + update 4 template lines + §5 pointer + Slack bullet. |
| `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md` | Add M9 (live clickable + Slack form). |

**Sites in fixtures:** the epic fixtures already use `https://acme.atlassian.net` (header URL) — their `By child:` links use the **same** host. The `multi-*.txt` fixtures have no header URL; their links use `https://example.atlassian.net`. The contract test is host-agnostic (greps for `[KEY](` + `/browse/KEY)`).

---

## Task 1: Contract test + fixtures (red → green)

**Files:**
- Modify: `plugins/bitacora/scripts/test-multi-status-fixtures.sh`
- Modify: the 5 `examples/*.txt` fixtures listed above

- [ ] **Step 1: Add the link assertions to the test (RED first)**

In `plugins/bitacora/scripts/test-multi-status-fixtures.sh`, find this block (the fixture path vars near the top):

```bash
AGG="$EX/multi-aggregate.txt"
BLK="$EX/multi-blocked.txt"
STD="$EX/multi-standup.txt"
```

Replace it with (adds the two epic fixtures):

```bash
AGG="$EX/multi-aggregate.txt"
BLK="$EX/multi-blocked.txt"
STD="$EX/multi-standup.txt"
EPE="$EX/epic-exec.txt"
EPG="$EX/epic-eng.txt"
```

Then find the final `since-window smoke` block, which ends with:

```bash
if "$SW" 1d 1704801600 >/dev/null 2>&1 && "$SW" last-working-day 1704801600 >/dev/null 2>&1; then
  pass "since-window.sh resolves 1d and last-working-day"
else
  bad "since-window.sh smoke failed"
fi

exit $fail
```

Insert the following **before** that block (so the link checks run, then the smoke check, then exit):

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

- [ ] **Step 2: Run the test, verify it FAILS**

Run: `bash plugins/bitacora/scripts/test-multi-status-fixtures.sh`
Expected: FAIL lines for the `check_linked` assertions (fixtures are still bare) — e.g. `FAIL: aggregate links AUTH-12 index entry (key AUTH-12 not linked in multi-aggregate.txt)`. Non-zero exit.

- [ ] **Step 3: Link the `multi-aggregate.txt` entries**

In `plugins/bitacora/skills/session-status/examples/multi-aggregate.txt`, replace the three `By ticket:` lines:

```
- AUTH-12 "OAuth token refresh" — In Progress (confidence: medium)
- DATA-77 "Feature store migration" — In Progress (confidence: high)
- UI-30 "Settings page redesign" — In Review
```

with:

```
- [AUTH-12](https://example.atlassian.net/browse/AUTH-12) "OAuth token refresh" — In Progress (confidence: medium)
- [DATA-77](https://example.atlassian.net/browse/DATA-77) "Feature store migration" — In Progress (confidence: high)
- [UI-30](https://example.atlassian.net/browse/UI-30) "Settings page redesign" — In Review
```

(Leave the `Health:` line and `Not yet reporting: PERF-9` tail unchanged — bare.)

- [ ] **Step 4: Link the `multi-blocked.txt` entry**

Replace:

```
- AUTH-12 "OAuth token refresh" — In Progress · stale 2d
```

with:

```
- [AUTH-12](https://example.atlassian.net/browse/AUTH-12) "OAuth token refresh" — In Progress · stale 2d
```

(Leave `Blocked on:` / `Waiting on: PLATFORM-4` / `Clear:` unchanged — bare.)

- [ ] **Step 5: Link the `multi-standup.txt` Moved entry**

Replace:

```
- DATA-77 "Feature store migration" — In Progress
```

with:

```
- [DATA-77](https://example.atlassian.net/browse/DATA-77) "Feature store migration" — In Progress
```

(Leave `No movement: AUTH-12, UI-30` unchanged — bare.)

- [ ] **Step 6: Link the `epic-exec.txt` By-child entries** (same `acme` host as its header URL)

Replace:

```
- CHECKOUT-101 "Serving cluster migration" — on track (high)
- CHECKOUT-102 "Ranking model v3" — in progress (medium)
- CHECKOUT-103 "Checkout summary panel" — at risk (low)
```

with:

```
- [CHECKOUT-101](https://acme.atlassian.net/browse/CHECKOUT-101) "Serving cluster migration" — on track (high)
- [CHECKOUT-102](https://acme.atlassian.net/browse/CHECKOUT-102) "Ranking model v3" — in progress (medium)
- [CHECKOUT-103](https://acme.atlassian.net/browse/CHECKOUT-103) "Checkout summary panel" — at risk (low)
```

(Leave `Top risks:` and `Dependencies:` lines — which also name CHECKOUT keys — bare.)

- [ ] **Step 7: Link the `epic-eng.txt` By-child entries** (same `acme` host)

Replace:

```
- CHECKOUT-101 "Serving cluster migration" — In Progress; next: prod canary 24h, then 100% traffic; risk: —
- CHECKOUT-102 "Ranking model v3" — In Progress; next: shadow eval, then promote behind a flag; risk: drift PSI under peak
- CHECKOUT-103 "Checkout summary panel" — In Progress; next: truncation pass + design QA; risk: overflow on narrow viewports
```

with:

```
- [CHECKOUT-101](https://acme.atlassian.net/browse/CHECKOUT-101) "Serving cluster migration" — In Progress; next: prod canary 24h, then 100% traffic; risk: —
- [CHECKOUT-102](https://acme.atlassian.net/browse/CHECKOUT-102) "Ranking model v3" — In Progress; next: shadow eval, then promote behind a flag; risk: drift PSI under peak
- [CHECKOUT-103](https://acme.atlassian.net/browse/CHECKOUT-103) "Checkout summary panel" — In Progress; next: truncation pass + design QA; risk: overflow on narrow viewports
```

(Leave `Dependency graph:` and `Open risks / blockers:` lines bare.)

- [ ] **Step 8: Run the test, verify it PASSES; shellcheck**

Run:
```bash
bash plugins/bitacora/scripts/test-multi-status-fixtures.sh
shellcheck --severity=warning plugins/bitacora/scripts/test-multi-status-fixtures.sh
```
Expected: every line `PASS`, exit 0; shellcheck clean. (The existing key-universe check still passes — `example.atlassian.net` / `acme.atlassian.net` contain no uppercase `ABC-123` token, and each linked key resolves to an allowed key.)

- [ ] **Step 9: Commit**

```bash
git add plugins/bitacora/scripts/test-multi-status-fixtures.sh plugins/bitacora/skills/session-status/examples/
git commit -m "test(status): assert linked index keys; link fixture entries (#87)"
```

---

## Task 2: SKILL.md render rule + template updates

**Files:**
- Modify: `plugins/bitacora/skills/session-status/SKILL.md`

No automated test (prose); verification is a read-back (Step 8). Use the Edit tool with the exact anchors below.

- [ ] **Step 1: Add the canonical "Ticket-key links" rule to the §7 intro**

Find:

```
plus any `showing N of M — narrow with --jql` truncation note from §2a.
```

Insert immediately after it:

```markdown

**Ticket-key links.** In every per-ticket **index entry** — the `By ticket:` / `By child:`
lists (rendered via §5's *Aggregate render*), the `--blocked` entries, and the `--standup`
`Moved:` entries — render the entry's **leading key** as a link:
`[KEY](https://<site>/browse/KEY)`, where `<site>` is the Atlassian site resolved in §3.
Inline mentions of a key elsewhere — in `Health:`, `Top risks:`, `Dependencies:` edges, and
the `Not yet reporting:` / `No movement:` tails — stay **bare** (one clean link per ticket,
not 3–4). Under `--copy-as-slack`, use the Slack form `<https://<site>/browse/KEY|KEY>`
(see step 5's *Slack mrkdwn rendering*).
```

- [ ] **Step 2: Link the `--blocked` template entry**

Find:

```
- <KEY> "<title>" — <Jira status> · stale <Nd>
```

Replace with:

```
- [<KEY>](https://<site>/browse/<KEY>) "<title>" — <Jira status> · stale <Nd>
```

- [ ] **Step 3: Link the `--standup` `Moved:` template entry**

Find (the line is unique — the Moved entry):

```
- <KEY> "<title>" — <Jira status>
```

Replace with:

```
- [<KEY>](https://<site>/browse/<KEY>) "<title>" — <Jira status>
```

- [ ] **Step 4: Link the §5 Aggregate render `--for-exec` By-child template**

Find:

```
- <CHILD-KEY "<title>" — plain status (confidence)>
```

Replace with:

```
- [<CHILD-KEY>](https://<site>/browse/<CHILD-KEY>) "<title>" — plain status (confidence)
```

- [ ] **Step 5: Link the §5 Aggregate render `--for-eng` By-child template**

Find:

```
- <CHILD-KEY "<title>" — Status; next: <first Next bullet>; risk: <Risk if any, else —>>
```

Replace with:

```
- [<CHILD-KEY>](https://<site>/browse/<CHILD-KEY>) "<title>" — Status; next: <first Next bullet>; risk: <Risk if any, else —>
```

- [ ] **Step 6: Add the §5 Aggregate render pointer**

Find:

```
wins. Lenses degrade gracefully: omit any signal that is empty (no risks → no `Top risks:` block).
```

Insert immediately after it:

```markdown

**Ticket-key links:** render each `By child:` entry's leading key as a link per §7's
*Ticket-key links* rule (the digest reuses these templates, so the rule is defined there).
Keys named inline in `Top risks:` / `Dependencies:` stay bare.
```

- [ ] **Step 7: Add the Slack `mrkdwn` bullet**

Find:

```
  `*PROJ-1234* — <https://site/browse/PROJ-1234|OAuth callback handling>`
```

Insert immediately after it (a new bullet in the same list):

```markdown
- **Ticket-key links in index entries** (the multi-ticket / aggregate `By ticket:` / `By child:`
  / `--blocked` / `--standup` `Moved:` lists): `<https://<site>/browse/KEY|KEY>` instead of
  `[KEY](url)`.
```

- [ ] **Step 8: Read-back consistency check**

Read the edited regions. Verify: the §7 rule, the four template lines (`--blocked`, `--standup`, exec By-child, eng By-child), the §5 pointer, and the Slack bullet all agree on the form `[KEY](https://<site>/browse/KEY)` (Slack `<…|KEY>`); the bare exceptions (Health / Top risks / Dependencies / tails) are named identically in the §7 rule and the §5 pointer. No automated test for prose — this read-back is the check.

- [ ] **Step 9: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): link ticket keys in multi-ticket index entries (#87)"
```

---

## Task 3: Manual-acceptance item

**Files:**
- Modify: `docs/superpowers/checklists/MANUAL-ACCEPTANCE.md`

- [ ] **Step 1: Append M9 after M8**

Find:

```
- [ ] **M8 — backward compat:** `/bitacora:status EPIC-1` still rolls up the epic; a bare
      single key is unchanged from pre-Phase-A behavior.
```

Insert immediately after it:

```markdown
- [ ] **M9 — ticket-key links:** run a multi-ticket digest (or `--blocked` / `--standup` /
      epic rollup). → Each `By ticket:` / `By child:` / entry key is a **clickable link** to the
      right ticket; inline keys (`Health`, `Top risks`, `Dependencies`, `No movement:`,
      `Not yet reporting:`) stay bare. With `--copy-as-slack`, the copied text uses
      `<url|KEY>` form.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/checklists/MANUAL-ACCEPTANCE.md
git commit -m "docs(status): M9 manual-acceptance for ticket-key links (#87)"
```

---

## Self-review

**Spec coverage:**
- Index-only linking of `By ticket:` / `By child:` / `--blocked` / `--standup` `Moved:` (D1, D5) → Task 1 fixtures + Task 2 templates/rule.
- Markdown form + Slack form (D2) → Task 2 §7 rule + Slack bullet; fixtures use markdown form.
- Site reused from §3 (D3) → stated in the §7 rule; no new lookup introduced.
- Single-ticket renders unchanged (D4) → no §5 single-ticket template touched; only the *Aggregate render* sub-templates + §7.
- Tests (fixtures + contract assertion + M9) → Task 1 (incl. epic fixtures) + Task 3.
- Inline / tail keys stay bare → Task 1 Step-9 `check_hasnot` guards + Task 2 rule wording.

**Placeholder scan:** none — every step carries exact anchor + replacement text.

**Consistency:** the link form `[KEY](https://<site>/browse/KEY)` (Slack `<https://<site>/browse/KEY|KEY>`) is identical across the §7 rule, all four template edits, the §5 pointer, and the Slack bullet. Fixture hosts are deliberate: `acme` for the epic fixtures (matches their existing header URL), `example` for the `multi-*` fixtures; the contract test is host-agnostic. `check_linked` / `check_hasnot` are defined before use (`check_hasnot` already exists in the test from the prior task; `check_linked` is added in Task 1 Step 1).
