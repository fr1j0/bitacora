# Bitácora — usage notes for regulated / banking domains

Bitácora is a context-capture and recall layer, not a system of record. The notes below cover the three places where that distinction matters most in environments with formal change-control or audit expectations.

## 1. `/improve` on formally controlled requirement tickets

The `/improve` rewrite **replaces** the ticket description in place. Be deliberate: once the rewrite lands, the new description is what downstream QA, audit, or regulator-facing processes will read.

- The `[ARCHIVE]` snapshot covers recovery + audit trail — the pre-edit description is preserved verbatim in a comment posted *before* the field edit, so every rewrite is reversible by copy-paste.
- The current description is the requirement of record.
- For tickets that go through formal review (BA-approved requirements, regulatory scope, customer commitments), treat `/improve` like an edit by hand: prefer the `--title`-only scope unless you're authoritatively changing the requirement, and share the rewrite for review before accepting at the gate.

For ordinary engineering tickets (tech debt, refactors, bug repros, dev-discovered work), use it freely — the rewrite is the engineer's working interpretation, and the archive lets anyone roll it back.

## 2. `/status` is recall, not source of truth

`/bitacora:status` synthesises a ticket's latest `[CTX]` into an audience-tailored summary. Treat the output as a **memory jog that points back to the source**, not as an independently-derived statement of fact.

- For financial calculations, risk numbers, position values, performance figures, or anything else load-bearing for a downstream decision, read the underlying ticket, the `[CTX]` comment trail, and the code or data they cite.
- The `--for-pm` mode is especially prone to abstracting specifics. Read it as a starting point for a conversation, not as a numeric handoff.
- The `[CTX]` corpus that `/status` reads is authored by engineers in handoff flows; its job is to help you recall the state you wrote, not to re-derive the state from primary data.

## 3. The `Decisions:` line is load-bearing

When you draft a `[CTX]` at handoff, the `Decisions:` line carries the highest value — and it's the one you can't reconstruct from the diff a month later.

- `Done:` is recoverable from `git log` and the PR.
- `Next:` is short and almost always re-derivable from current state.
- `Decisions:` captures **why** you chose what you chose — the trade-off you made, the alternative you rejected, the constraint that forced the call.

In a regulated environment this is the line auditors will care about and the line your future-self will care about. Write it like you're explaining the choice to someone in eight months who hasn't seen the conversation. Cite the constraint (comment number, Slack thread, regulator rule) when one exists.

---

These three norms are conventions, not enforcement. The plugin doesn't gate any of them. If your team adopts stricter rules, document them in your repo's `CONTRIBUTING.md` or a project-local `.bitacora.yml` — Bitácora reads project-local overrides where available (see the skill configuration sections in the [plugin README](plugins/bitacora/README.md)).
