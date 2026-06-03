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

## Multi-ticket `/status` (Phase A)

> **Two test layers.** The deterministic *mechanical* contract — coverage math, blocked-only
> selection, `--standup` window membership, and the `portfolio`→`digest` terminology — is
> auto-checked in CI by `plugins/bitacora/scripts/test-multi-status-fixtures.sh` against the
> committed `examples/multi-*.txt`. The items below are the **render** half: live LLM output
> across lenses against a real Jira, which can't be unit-tested.

- [ ] **M1 — `--mine` digest:** `/bitacora:status --mine` with ≥2 assigned tickets. →
      Cross-ticket digest in the `self` lens; coverage line `N tickets (M reporting, …)`;
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
- [ ] **M9 — ticket-key links (Slack-only):** run a multi-ticket digest (or `--blocked` /
      `--standup` / epic rollup). → The **printed** render shows **bare** keys (no inline links).
      Re-run with `--copy-as-slack`. → The copied Slack text renders each per-ticket index entry's
      key as `<url|KEY>`; inline / tail keys stay bare.

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
