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

## What lives where — status vs. scratch

Bitácora's job is **status** — the durable, ticket-level narrative a teammate would care about: where the work stands, the decisions behind it, and what's next. That belongs in Jira, on the ticket, in the open. That's what `[CTX]` comments are.

What Bitácora deliberately *doesn't* manage is the **high-frequency scratch** between sessions — the running breadcrumbs, the small "just did X" notes, the granular working state that turns over every few minutes. That data is local, personal, and churny, and it has its own tools:

- **Remember** — local session memory across context clears (the `.remember/` buffer)
- **claude-mem** — a Remember-compatible alternative
- Any **memory MCP server**, or Claude Code's built-in `CLAUDE.md` memory

Two altitudes: Jira holds the milestones the team needs; your local memory tool holds the minute-to-minute scratch only you need. Bitácora owns the first and stays out of the second — which is why Remember is *optional*, not required.

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

🚧 **`[CTX]` commit anchor** *(idea)* — an optional anchor line tying a `[CTX]` comment to the commit/PR it reflects, so resume and debugging can ground state in real code: verify "done" against the diff, or bisect a regression from a known-good point. Uses a PR-relative form (e.g. `PR #17 @ 4a29459`) to survive squash-merges.

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

At minimum you need the **Atlassian Rovo MCP** (so Bitácora can read and write Jira) and **Claude Code** itself. **Remember** is optional but recommended — it's where the high-frequency scratch lives, separate from the ticket-level status Bitácora owns (see [What lives where](#what-lives-where--status-vs-scratch)).

## Installation

*Coming once Phase 1 is validated through personal use. For now, this is a design with a repo.*

Once published:

```
/plugin marketplace add <owner>/bitacora
/plugin install bitacora@bitacora
```

Prerequisites:

- Atlassian MCP configured with read/write access to your team's Jira instance *(required)*
- Remember, claude-mem, or another local memory tool *(optional — for the between-sessions scratch Bitácora doesn't manage)*

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
