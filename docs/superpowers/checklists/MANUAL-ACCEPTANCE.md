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
