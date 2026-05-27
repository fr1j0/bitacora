<div align="center">

# Bitácora

**Every bit of context, logged.**

*Structured session handoffs, logged to Jira — so context survives context clears, sessions, and teammates.*

[![Status](https://img.shields.io/badge/status-alpha-orange?style=for-the-badge)](#)
[![Tests](https://img.shields.io/github/actions/workflow/status/fr1j0/bitacora/test.yml?style=for-the-badge&label=tests)](https://github.com/fr1j0/bitacora/actions/workflows/test.yml)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-D97757?style=for-the-badge&logo=claude&logoColor=white)](https://claude.com/claude-code)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)

</div>

> **bit·ácora** — Spanish for "ship's logbook": the structured journal kept aboard a ship to record position, decisions, and observations across long voyages.

Bitácora is a Claude Code plugin that turns Jira into a shared external memory layer for engineering teams. It captures structured handoffs across sessions, sharpens vague PM tickets, runs timeboxed spikes, surfaces what to work on next, and keeps a context-window meter visible so you know when to clear and resume cleanly.

> [!WARNING]
> **Alpha — in active development.** The API may change. Use at your own risk; pin to a commit you've audited.

---

## At a glance

- **What** — a Claude Code plugin that uses Jira as a *shared, structured memory layer* across sessions and teammates.
- **How** — a strict `[CTX]` comment format plus opinionated commands for handoff, sharpening, spikes, picking, and status.
- **Today** — Phase 1 ships `/bitacora:handoff` + the `[CTX]` format. Everything else is on the roadmap below.
- **Safety** — public source, no auto-update, no telemetry, and every Jira write is confirmation-gated.

## What it does

Bitácora is a small plugin layered on top of two foundation pieces that already exist in the Claude Code ecosystem:

- **Remember** (or a claude-mem-compatible plugin) — local session memory across context clears
- **Atlassian Rovo MCP** — Jira and Confluence primitives

What Bitácora adds on top is the *Jira-aware workflow layer*: opinionated commands for handing off, sharpening, spiking, picking, and reporting work — plus a comment-format discipline that lets agents read each other's structured updates across sessions and team members.

## Commands

The flagship command — wrap up a session cleanly:

```bash
/bitacora:handoff
```

Writes a structured `[CTX]` comment to each touched Jira ticket, plus a local handoff for next-session continuity.

| Command | Status | What it does |
|---------|--------|--------------|
| `/bitacora:handoff` | ✅ **Phase 1** | Wrap up a session cleanly. Writes a structured `[CTX]` comment to each touched Jira ticket plus a local handoff for next-session continuity. |
| `/bitacora:help` | ✅ **Phase 1** | Print the Bitácora command reference — shipped commands and the planned roadmap. |
| `/bitacora:resume` | ✅ **Phase 1** | Rehydrate a fresh session from a ticket's latest `[CTX]` — pull its `Status` / `Decisions` / `Next` back into context after a `/clear`, closing the handoff loop from Jira (not just local Remember). |
| `/bitacora:improve` | 🚧 Planned | Sharpen a vague or technically weak ticket *your branch is based on*. Surfaces clarifying questions, then produces a structured rewrite that preserves the original intent. |
| `/bitacora:status` | 🚧 Planned | Synthesize a ticket's current state into a human-readable summary. Audience modes for PM (`--for-pm`), engineer (`--for-eng`), and self (`--for-self`). |
| `/bitacora:spike` | 🚧 Planned | Create a timeboxed exploratory spike ticket with a mandatory recommendation at conclusion. |
| `/bitacora:next` | 🚧 Planned | Smart morning ticket picker. Reads your boards, categorizes by pickup cost, and surfaces reasoning for each candidate. |

> Shipped commands also have a shorter, opt-in `/bit:` alias (e.g. `/bit:handoff`, `/bit:help`) — see the [plugin README](plugins/bitacora/README.md).

🚧 **statusLine** *(planned)* — a context-window meter with progressive UX (calm → amber → red → critical) so you know when to hand off before quality degrades.

## Why this exists

The short version: long Claude Code sessions degrade. The context window fills up, attention spreads, decisions drift. The honest move is to clear and resume — but resuming cleanly requires a structured handoff somewhere. And if you do that handoff in Jira (where work already lives), in a format other agents can read, you get something better than personal memory: a shared external memory layer for the whole team.

The longer version: a previous tool that solved part of this problem turned out to be a scam — abandoned project, suspicious auto-update, crypto rug pull. Bitácora is the structural answer to that failure mode: public source, no auto-update, no telemetry, plain files in directories you can grep.

## Architecture

Bitácora is intentionally small. It composes with existing tools rather than replacing them.

```
  Bitácora — commands + the [CTX] comment-format discipline
                          │
                          │  layers on top of
                          ▼
  ┌──────────────┬──────────────┬──────────────┐
  │   Remember   │  Atlassian   │ Claude Code  │
  │  (optional)  │   Rovo MCP   │   (host)     │
  └──────────────┴──────────────┴──────────────┘
```

You'll want all three installed for Bitácora to be fully useful.

## Installation

*Coming once Phase 1 is validated through personal use. For now, this is a design with a repo.*

Once published:

```
/plugin marketplace add <owner>/bitacora
/plugin install bitacora@bitacora
```

Prerequisites:

- Remember (or a claude-mem-compatible plugin) installed for local memory
- Atlassian MCP configured with read/write access to your team's Jira instance

## The `[CTX]` comment format

Bitácora writes Jira comments in a strict structured format so other agents (and humans) can parse them reliably:

```
[CTX] Status update

Status: In Progress

Done:

- OAuth provider client implemented
- Callback handler happy path complete

Decisions:

- PKCE flow over implicit (more secure for SPAs)

Next:

- Token refresh implementation
```

No hand-typed date — the comment's own timestamp is authoritative. A blank line separates every section so the labels render as headings, not as part of the previous bullet.

Agents reading the ticket for `/bitacora:status` synthesis, `/bitacora:handoff` resume, or cross-ticket queries use only `[CTX]`-prefixed comments. Free-form human discussion is ignored for state extraction (but still read for requirements understanding by `/bitacora:improve`).

This creates a virtuous loop: the more team members adopt the format, the more useful the shared memory layer becomes. See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](docs/JIRA_AGENT_COMMENT_FORMAT.md) for the full spec.

## Philosophy and safety

> [!NOTE]
> These aren't features — they're structural commitments. The answer to the kind of supply-chain failure that prompted this project.

- **Public source.** Read every line. No black boxes.
- **No auto-update.** Plugin updates happen only when you explicitly run `/plugin install` again. No version you didn't choose will land on your machine.
- **No telemetry.** Bitácora does not phone home. No analytics, no usage tracking, no third-party reporting.
- **Pin to a commit if you want.** Fork and lock to a specific revision for full reproducibility.
- **Confirm before writing.** Bitácora never writes to Jira without showing you the draft first. There is no "trust mode" that bypasses this.

## What Bitácora is not

- *Not a memory system.* That's Remember (or claude-mem).
- *Not a Jira client.* That's the Atlassian MCP.
- *Not a context compressor.* That's Context Mode if you need it.
- *Not a replacement for your judgment.* Every Jira write is confirmation-gated; you decide what goes up.

Bitácora is the *glue* — the opinionated workflow layer that ties these tools into a coherent, team-aware ticket lifecycle.

## Contributing

Currently in alpha. Issues and design discussion are welcome via GitHub Issues. Pull requests may not be accepted until Phase 1 stabilizes; once it does, contribution guidelines will appear in `CONTRIBUTING.md`.

If you want to use Bitácora during alpha, fork it and pin to whatever commit you've audited. That's the safest path while the API is still settling.

## License

[MIT](LICENSE) — permissive, allowing commercial and private use. The one commitment beyond MIT's terms: the *project itself* will not auto-update users into surprises.

## About the name

*Bitácora* comes from the Spanish *bitácula*, from the Latin *habitaculum* — "a dwelling place." Originally it referred to the wooden housing on a ship's deck that held the compass, and by extension to the captain's logbook kept inside it.

It has no etymological relationship to the English word "bit." But it's a coincidence too good not to use.

---

<div align="center">

*Bitácora. Every bit of context, logged.*

</div>
