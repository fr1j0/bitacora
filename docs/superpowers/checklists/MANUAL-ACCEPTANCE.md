# Bitácora Phase 1 — Manual Acceptance Checklist

Run during dogfooding. Requires the `remember` plugin, the Atlassian Rovo MCP, and a real
Jira project. Install locally first: `/plugin marketplace add <path-to-this-repo>` then
`/plugin install bitacora@bitacora`.

- [ ] **A1 — canonical:** On a ticket-named branch, do real work, run `/bitacora:handoff`,
      approve, exit, start a fresh session. → Remember resumes the scratch with a correct
      restatement; the ticket shows a clean `[CTX]` comment.
- [ ] **A2 — no ticket:** From a branch with no ticket key and no ticket mentions, run
      handoff. → Local-only consolidated scratch, no Jira nag.
- [ ] **A3 — explicit args:** `/bitacora:handoff PROJ-1 PROJ-2`. → Exactly that ticket set
      is used.
- [ ] **A4 — MCP unavailable:** Disconnect/deny the Atlassian MCP, run handoff. → Jira half
      skipped gracefully, local completes, reason reported, no retry loop.
- [ ] **A5 — bad ticket key:** Force a non-existent key. → Error surfaced for that ticket,
      others unaffected, no crash.
- [ ] **A6 — malformed prior `[CTX]`:** Put a malformed `[CTX]` on the ticket first. →
      Lenient continuity-read still produces a sensible draft.
- [ ] **A7 — cancel:** Cancel at the gate. → Nothing written.
- [ ] **A8 — Remember fails:** Simulate a Remember failure. → Scratch printed to screen,
      Jira writes still offered.
- [ ] **A9 — multi-ticket:** Work on PROJ-1 (branch A), switch to PROJ-2 (branch B), mention
      PROJ-3, run handoff. → All three reconstructed and attributed (1→A, 2→B,
      3→current/mentioned); a `[CTX]` drafted per ticket; one consolidated scratch.
- [ ] **A10 — skip + isolation:** Three tickets; "skip 3"; make [2] 404 on write. → [1]
      writes ✓, [2] reports ✗ with retry offer, [3] dropped; scratch writes ✓ regardless.
- [ ] **`/bit:` alias:** After copying the alias file, `/bit:handoff` runs the same flow.

## Multi-ticket `/digest` (Phase A)

> **Two test layers.** The deterministic *mechanical* contract — coverage math, blocked-only
> selection, `--standup` window membership, and the `portfolio`→`digest` terminology — is
> auto-checked in CI by `plugins/bitacora/scripts/test-digest-fixtures.sh` against the
> committed `examples/multi-*.txt`. The items below are the **render** half: live LLM output
> across lenses against a real Jira, which can't be unit-tested.

- [ ] **M1 — `--mine` digest:** `/bitacora:digest --mine` with ≥2 assigned tickets. →
      Cross-ticket digest in the `self` lens; coverage line `N tickets (M reporting, …)`;
      no-`[CTX]` tickets land in `Not yet reporting`, never dropped.
- [ ] **M2 — explicit keys:** `/bitacora:digest PROJ-1 PROJ-2`. → Multi-ticket mode (2+ keys),
      not single-ticket. `/bitacora:status PROJ-1` alone still renders one ticket.
- [ ] **M3 — `--blocked`:** `/bitacora:digest --mine --blocked`. → Only tickets with
      `Blockers:`/`Dependencies:`, most-stale first, `stale Nd` correct; `Nothing blocked …`
      when none qualify.
- [x] **M4 — `--standup` (day buckets):** `/bitacora:digest --mine --standup --since 1d`. →
      In-window `[CTX]` grouped into a past bucket then `Today`, past-first; the past header
      reads `Yesterday` (midweek), a weekday name when the prior worked day isn't yesterday
      (e.g. a weekend gap), or `Earlier`
      for a wide multi-day window. A ticket touched on both days appears in both buckets with
      each day's `Did`/`Next`. Non-movers fall under `No movement:`. A Monday
      `last-working-day` run files Friday's work under the `Friday` header.
- [ ] **M5 — cap disclosure:** A scope matching more than `multi_fanout_cap` (default 25). →
      `showing N of M — narrow with --jql`; no silent truncation.
- [ ] **M6 — empty + single + board:** `/bitacora:digest --mine` matching zero → plain "matched nothing";
      a scope resolving to exactly one → single-ticket render; `--board X` → "not
      supported — use `--jql`" and stop.
- [ ] **M7 — audience compose:** `/bitacora:digest --mine --blocked --for-exec`. → `--blocked`
      content rendered at exec altitude (PR/commit hashes stripped, asks framed).
- [ ] **M8 — routing:** `/bitacora:digest EPIC-1` rolls up the epic across its children;
      `/bitacora:status EPIC-1` renders the epic's own `[CTX]` as a single node (no rollup).
      A bare single non-epic key: `/bitacora:status PROJ-1` renders one ticket unchanged.
- [ ] **M9 — ticket-key links (Slack-only):** run `/bitacora:digest --mine` (or `--blocked` /
      `--standup` / epic rollup via `/bitacora:digest EPIC-1`). → The **printed** render shows
      **bare** keys (no inline links). Re-run with `--copy-as-slack`. → The copied Slack text
      renders each per-ticket index entry's key as `<url|KEY>`; inline / tail keys stay bare.
- [ ] **M10 — parked-debt ledger:** Run `/bitacora:digest --mine` (or 2+ keys) and
      `/bitacora:digest EPIC-1` over scopes where at least one ticket's latest `[CTX]`
      carries a `[debt]`-tagged `Decisions:` bullet. → The aggregate shows the ledger
      (exec `Debt:` business framing, eng `Parked debt:` with the follow-up key, self
      terse tail), grouped by ticket; **only real `[debt]` tags** appear (no invention)
      and follow-up links are correct. The `Concentrated:` risk flag fires only when 2+
      tickets genuinely share a surface — never on an inferred theme. `--for-pm` /
      `--for-ops` omit the section; a scope with no `[debt]` tags renders no debt
      section at all.

## Collision detection on `/handoff` (v1)

> **What's already hard-verified (no manual step needed):** the fire/no-fire *decision* is
> unit-tested in `plugins/bitacora/scripts/test-collision-check.sh`, and the *comment
> plumbing* (each `getJiraIssue` comment exposes `author.accountId` + `created`, in the same
> accountId format `atlassianUserInfo` returns) was confirmed live by **identity inversion** —
> feeding a real `[CTX]`'s author/timestamp to the helper with a mismatched `--me` fires
> `collision`, with the real `--me` returns `clear`. accountIds are opaque strings to the
> helper, so "someone else" is just "an id that isn't mine."
>
> The cases below are the **live-render half** (the LLM extracting authors/timestamps and
> driving the gate), which can't be unit-tested.

**Solo testing without a second Atlassian account — the dry-run convention.** A real
`/handoff` will never fire the gate for a single user (step 2 resolves `--me` from
`atlassianUserInfo` = you = the author of your own `[CTX]`, so it always returns `clear`).
To exercise C1–C3 alone, **ask the agent to dry-run / simulate a collision** — e.g.
*"simulate a teammate collision on TESTING-22 and show the handoff gate."* The agent treats
an existing (or hypothetical) `[CTX]` as authored by a named hypothetical teammate, runs the
real decision helper, renders the actual `⚠ collision` gate and the **merge** re-draft, and
**writes nothing**. This eyeballs the render/merge UX; the decision + plumbing it sits on top
of are already hard-verified above. (A true two-author end-to-end run still needs a second
account or teammate; do it opportunistically when one is available.)

- [ ] **C1 — fires (takeover):** Dry-run a teammate `[CTX]` (within 48h) on a ticket you have
      never `[CTX]`-ed. → The gate shows `⚠ collision` with the teammate author, age, and
      Status/Next excerpt; the three actions are offered. (Live two-author equivalent: have a
      second account post the `[CTX]`, then run `/bitacora:handoff`.)
- [ ] **C2 — merge:** On a C1 dry-run, choose **merge**. → Your `[CTX]` is re-drafted carrying
      the teammate's Status/Next forward; the merged draft is re-shown before writing; on a
      live write it does not erase their context.
- [ ] **C3 — proceed / skip:** On a C1 dry-run, choose **proceed** → draft writes as-is (live);
      choose **skip** → that ticket is not written; other tickets in the same handoff are
      unaffected either way.
- [ ] **C4 — no fire (solo / stale / mine-newest):** (a) All `[CTX]` on the ticket are
      yours → no flag. (b) The teammate's `[CTX]` is older than 48h → no flag. (c) You
      posted a `[CTX]` after the teammate's → no flag.
- [ ] **C5 — lenient skip:** Disconnect/deny the Atlassian MCP (or use a ticket whose read
      fails), run handoff. → No collision flag, no error about the check; handoff proceeds
      exactly as the no-check path.
- [ ] **C6 — self-collision:** Run `/bitacora:handoff` on a ticket whose newest `[CTX]` is your own
      and < 2h old → the gate shows `⚠ recent self-handoff` with `[append]` / `[skip]`;
      `append` writes the new `[CTX]`, `skip` does not. A handoff hours later (outside
      `self_handoff_window`) shows no marker. Teammate `⚠ collision` is unaffected.

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
- [ ] **S4 — /digest multi-ticket marker:** `/bitacora:digest --mine` (or 2+ keys) including at
      least one stale ticket. → That ticket's `By ticket:` entry is suffixed ` · ⚠ behind <N>d`;
      fresh tickets in the same digest carry no marker. Confirms it composes with `--blocked` /
      `--standup` / `--for-*` without changing their selection.
- [ ] **S5 — no [CTX] / grace override:** A ticket with no `[CTX]` shows neither banner nor
      marker (it's "no context", not stale). Set `staleness_grace: 12h` in `.bitacora.yml` and
      re-run S1/S3 → tickets with ≥12h drift now flag.

## Command routing guards

- [ ] **G1 — status rejects multi:** `/bitacora:status --mine --standup` → prints
      "Multi-ticket reads now live in /bitacora:digest" with the flags echoed; no render.
- [ ] **G2 — digest rejects a single key / status epic-as-node:** `/bitacora:digest AT-1234`
      (a non-epic key) → "That's a single ticket — use /bitacora:status AT-1234"; no render.
      `/bitacora:status AT-EPIC` (an epic) → renders the epic's own [CTX] as one node (or the
      no-[CTX] line + a /bitacora:digest pointer).

## `next` — cli family (GitHub Issues)

- [ ] **next (github):** in a GitHub-Issues repo with ≥1 issue assigned to you, run
  `/bit:next`. Expect a categorized shortlist of *this repo's* issues — never a Jira
  project's tickets, never an unscoped query.

## Release hygiene

- [ ] **README demo still truthful:** if this release changed user-visible
      `/bitacora:handoff` or `/bitacora:resume` output, edit the scenario in
      `demo/generate.py` and re-run `demo/build.sh` so `demo/bitacora-demo.gif`
      matches what ships.
