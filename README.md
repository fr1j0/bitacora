# Bitácora

> **bit·ácora** — Spanish for "ship's logbook." The structured journal kept aboard a ship to record position, decisions, and observations across long voyages.
>
> *Also: the only word for "logbook" that contains the smallest unit of information.*

**Every bit of context, logged.**

Bitácora is a Claude Code plugin that turns Jira into a shared external memory layer for engineering teams. It captures structured handoffs across sessions, sharpens vague PM tickets, runs timeboxed spikes, surfaces what to work on next, and keeps a context-window meter visible so you know when to clear and resume cleanly.

**Status:** *Alpha — in active development. API may change. Use at your own risk; pin to a commit you trust.*

---

## What it does

Bitácora is a small plugin layered on top of three foundation pieces that already exist in the Claude Code ecosystem:

- **[Superpowers](https://github.com/obra/superpowers)** — workflow discipline (brainstorm → plan → TDD → review)
- **claude-mem** (or **Remember**) — local session memory across context clears
- **Atlassian Rovo MCP** — Jira and Confluence primitives

What Bitácora adds on top is the *Jira-aware workflow layer*: opinionated commands for handing off, sharpening, spiking, picking, and reporting work — plus a comment-format discipline that lets agents read each other's structured updates across sessions and team members.

## Commands

| Command | What it does |
|---------|--------------|
| `/bit:handoff` | Wrap up a session cleanly. Writes a structured `[CTX]` comment to the active Jira ticket plus a local handoff for next-session continuity. |
| `/bit:improve` | Sharpen a vague or technically weak PM-authored ticket. Surfaces clarifying questions, then produces a structured rewrite that preserves the original intent. |
| `/bit:status` | Synthesize a ticket's current state into a human-readable summary. Audience modes for PM (`--for-pm`), engineer (`--for-eng`), and self (`--for-self`). |
| `/bit:spike` | Create a timeboxed exploratory spike ticket with a mandatory recommendation at conclusion. |
| `/bit:next` | Smart morning ticket picker. Reads your boards, categorizes by pickup cost, and surfaces reasoning for each candidate. |

Plus a custom **statusLine** showing real-time context window utilization with progressive UX (calm → amber → red → critical-shift) so you know when to handoff before quality degrades.

## Why this exists

The short version: long Claude Code sessions degrade. The context window fills up, attention spreads, decisions drift. The honest move is to clear and resume — but resuming cleanly requires a structured handoff somewhere. And if you do that handoff in Jira (where work already lives), in a format other agents can read, you get something better than personal memory: a shared external memory layer for the whole team.

The longer version: a previous tool that solved part of this problem turned out to be a scam — abandoned project, suspicious auto-update, crypto rug pull. Bitácora is the structural answer to that failure mode: public source, no auto-update, no telemetry, plain files in directories you can grep.

## Architecture

Bitácora is intentionally small. It composes with existing tools rather than replacing them.

```
                ┌──────────────────────────────────┐
                │             Bitácora             │
                │  /bit:handoff   /bit:improve     │
                │  /bit:status    /bit:spike       │
                │  /bit:next      + statusLine     │
                │  [CTX] comment format discipline │
                └────────┬─────────────────────────┘
                         │ layers on top of
        ┌────────────────┼─────────────────┬────────────────┐
        ▼                ▼                 ▼                ▼
  ┌───────────┐    ┌────────────┐   ┌──────────────┐  ┌───────────┐
  │ Superpowers│   │ claude-mem │   │ Atlassian    │  │ Claude    │
  │ (workflow) │   │ (memory)   │   │ Rovo MCP     │  │ Code      │
  └───────────┘    └────────────┘   │ (Jira)       │  │ (host)    │
                                    └──────────────┘  └───────────┘
```

You'll want all four installed for Bitácora to be fully useful.

## Installation

*Coming once Phase 1 is validated through personal use. For now, this is a design with a repo.*

Once published:

```
/plugin marketplace add <owner>/bitacora
/plugin install bitacora@bitacora
```

Prerequisites:

- Superpowers installed via the Anthropic marketplace
- claude-mem or Remember installed for local memory
- Atlassian MCP configured with read/write access to your team's Jira instance

## The `[CTX]` comment format

Bitácora writes Jira comments in a strict structured format so other agents (and humans) can parse them reliably:

```
[CTX] Status update — 2026-05-27

Status: In Progress
Done:
  - OAuth provider client implemented
  - Callback handler happy path complete
Decisions:
  - PKCE flow over implicit (more secure for SPAs)
Next:
  - Token refresh implementation
Blockers:
  None
```

Agents reading the ticket for `/bit:status` synthesis, `/bit:handoff` resume, or cross-ticket queries use only `[CTX]`-prefixed comments. Free-form human discussion is ignored for state extraction (but still read for requirements understanding by `/bit:improve`).

This creates a virtuous loop: the more team members adopt the format, the more useful the shared memory layer becomes. See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](docs/JIRA_AGENT_COMMENT_FORMAT.md) for the full spec.

## Philosophy and safety

These aren't features. They're structural commitments — the answer to the kind of supply-chain failure that prompted this project.

- **Public source.** Read every line. No black boxes.
- **No auto-update.** Plugin updates happen only when you explicitly run `/plugin install` again. No version you didn't choose will land on your machine.
- **No telemetry.** Bitácora does not phone home. No analytics, no usage tracking, no third-party reporting.
- **Pin to a commit if you want.** Fork and lock to a specific revision for full reproducibility.
- **Confirm before writing.** Bitácora never writes to Jira without showing you the draft first. There is no "trust mode" that bypasses this.

## What Bitácora is not

- *Not a workflow methodology.* That's Superpowers' job.
- *Not a memory system.* That's claude-mem (or Remember).
- *Not a Jira client.* That's the Atlassian MCP.
- *Not a context compressor.* That's Context Mode if you need it.
- *Not a replacement for your judgment.* Every Jira write is confirmation-gated; you decide what goes up.

Bitácora is the *glue* — the opinionated workflow layer that ties these tools into a coherent, team-aware ticket lifecycle.

## Contributing

Currently in alpha. Issues and design discussion are welcome via GitHub Issues. Pull requests may not be accepted until Phase 1 stabilizes; once it does, contribution guidelines will appear in `CONTRIBUTING.md`.

If you want to use Bitácora during alpha, fork it and pin to whatever commit you've audited. That's the safest path while the API is still settling.

## License

To be determined — likely MIT or Apache 2.0. The intent is permissive, allowing commercial and private use, with the understanding that the *project itself* will not auto-update users into surprises.

## About the name

*Bitácora* comes from the Spanish *bitácula*, from the Latin *habitaculum* — "a dwelling place." Originally it referred to the wooden housing on a ship's deck that held the compass, and by extension to the captain's logbook kept inside it.

It has no etymological relationship to the English word "bit."

But it's a coincidence too good not to use.

---

*Bitácora. Every bit of context, logged.*
