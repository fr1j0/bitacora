<div align="center">

# Bitácora

**Every bit of context, logged.**

*Structured session handoffs, logged to Jira — so context survives context clears, sessions, and teammates.*

[![Status](https://img.shields.io/badge/status-alpha-orange?style=for-the-badge)](#)
[![Release](https://img.shields.io/github/v/release/fr1j0/bitacora?style=for-the-badge&label=release)](https://github.com/fr1j0/bitacora/releases/latest)
[![Tests](https://img.shields.io/github/actions/workflow/status/fr1j0/bitacora/test.yml?style=for-the-badge&label=tests)](https://github.com/fr1j0/bitacora/actions/workflows/test.yml)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-D97757?style=for-the-badge&logo=claude&logoColor=white)](https://claude.com/claude-code)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)

</div>

> **bit·ácora** — Spanish for "ship's logbook": the structured journal kept aboard a ship to record position, decisions, and observations across long voyages.

Bitácora is a Claude Code plugin that turns Jira into a shared external memory layer for engineering teams — capturing structured handoffs across sessions and rehydrating them on resume, so context survives context clears. Phase 1 ships the full read/write loop: `handoff`, `resume`, `status`, a morning `next` picker, an `improve` rewriter for vague tickets, `help`, an opt-in statusLine context meter, and the `[CTX]` comment-format discipline.

> [!WARNING]
> **Alpha — in active development.** The API may change. Use at your own risk; pin to a commit you've audited.

---

## At a glance

- **What** — a Claude Code plugin that uses Jira as a *shared, structured memory layer* across sessions and teammates.
- **How** — a strict `[CTX]` comment format plus opinionated commands for handoff, resume, status, morning ticket picking, and corpus-grounded ticket sharpening.
- **Today** — Phase 1 complete, plus **v0.5.1**: `handoff` (with **collision detection** — warns before burying a teammate's recent `[CTX]`), `resume` and `status` (now with a **staleness signal** — flag a `[CTX]` that's fallen behind the ticket's activity), `status` for single-ticket reads, `digest` for epic rollup and **multi-ticket** scopes — `--mine`/`--sprint`/`--jql` with `--blocked`/`--standup` lenses; keys linked when copied for Slack), `next`, `improve`, `help`, the `[CTX]` format, and an opt-in statusLine context meter.
- **Safety** — public source, no auto-update, no telemetry, and every Jira write is confirmation-gated.

## What it does

Bitácora is a small plugin that builds on the Claude Code ecosystem:

- **Atlassian Rovo MCP** — the Jira and Confluence primitives Bitácora reads and writes through *(required)*
- **Remember** (or a claude-mem-compatible plugin) — local session memory across context clears *(optional companion)*

What Bitácora adds on top is the *Jira-aware workflow layer*: opinionated commands for handing off, resuming, reporting status, picking work, and sharpening vague tickets — plus a comment-format discipline that lets agents read each other's structured updates across sessions and team members.

## What lives where — status vs. scratch

Bitácora's job is **status** — the durable, ticket-level narrative a teammate would care about: where the work stands, the decisions behind it, and what's next. That belongs in Jira, on the ticket, in the open. That's what `[CTX]` comments are. `/bitacora:improve` extends the same principle to the ticket itself — sharpening a vague description or title is durable, shared, in-the-open work too, just on Jira fields instead of comments.

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

All commands below are **Phase 1 — shipped.**

| Command | What it does |
|---------|--------------|
| `/bitacora:handoff` | Wrap up a session cleanly. Writes a structured `[CTX]` comment to each touched Jira ticket plus a local handoff for next-session continuity. |
| `/bitacora:help` | Print the Bitácora command reference. |
| `/bitacora:resume` | Rehydrate a fresh session from a ticket's latest `[CTX]` — pull its `Status` / `Decisions` / `Next` back into context after a `/clear`, closing the handoff loop from Jira (not just local Remember). |
| `/bitacora:status` | Synthesize ONE ticket's latest `[CTX]` into an audience-tailored summary (`--for-self`/`-eng`/`-ops`/`-pm`/`-exec`). Epics render as a single node (their own `[CTX]`, not a rollup). Read-only: prints and offers a clipboard copy. |
| `/bitacora:digest` | Aggregate `[CTX]` read — roll up an epic across its children, or read a multi-ticket scope (`--mine`, `--sprint`, `--jql`, or 2+ keys) for a cross-ticket digest or a query lens — `--blocked` (what's stuck) or `--standup` (what moved). Read-only: prints and offers a clipboard copy. |
| `/bitacora:next` | Morning ticket picker. Reads the tickets assigned to you, categorizes by pickup cost (Continue / Ready / Quick wins + a Needs-attention tail), annotates each with a `[CTX]`-grounded reason-to-pick, recommends one, and chains into `/bitacora:resume <KEY>`. Read-only. |
| `/bitacora:improve` | Sharpen a ticket — corpus-grounded structured rewrite (Story / Bug / Epic / Subtask aware) with a snapshot to an `[ARCHIVE]` Jira comment before any field edit. Read + write; description by default, title opt-in per invocation. |

> Shipped commands also have a shorter, opt-in `/bit:` alias (e.g. `/bit:handoff`, `/bit:help`) — see the [plugin README](plugins/bitacora/README.md).

✅ **statusLine** *(opt-in)* — a single-line context-window meter that bolds red at ≥85% so you know when to `/bitacora:handoff` then `/clear` + `/bitacora:resume`. Also shows the active ticket and a `✎ handoff pending` marker. Opt-in setup in the [plugin README](plugins/bitacora/README.md#optional-the-statusline).

## Why this exists

The short version: long Claude Code sessions degrade. The context window fills up, attention spreads, decisions drift. The honest move is to clear and resume — but resuming cleanly requires a structured handoff somewhere. And if you do that handoff in Jira (where work already lives), in a format other agents can read, you get something better than personal memory: a shared external memory layer for the whole team.

The longer version: a tool you trust with your workflow should be one you can fully inspect and control. Bitácora is built on that principle — public source, no auto-update, no telemetry, just plain files in directories you can grep. You always know exactly what it does, and nothing changes unless you change it.

## Architecture

Bitácora is intentionally small. It composes with existing tools rather than replacing them.

```
  Bitácora — commands + the [CTX] comment-format discipline
                          │
                          │  layers on top of
                          ▼
  ┌────────────────────────┬────────────────────────┐
  │   Atlassian Rovo MCP   │      Claude Code       │
  │   (Jira read/write)    │         (host)         │
  └────────────────────────┴────────────────────────┘

  Optional companion · local scratch layer:
      Remember / claude-mem / memory MCP — the between-sessions notes
```

At minimum you need the **Atlassian Rovo MCP** (so Bitácora can read and write Jira) and **Claude Code** itself. **Remember** is optional but recommended — it's where the high-frequency scratch lives, separate from the ticket-level status Bitácora owns (see [What lives where](#what-lives-where--status-vs-scratch)).

## Installation

Submit each command **separately** in Claude Code — pasting all four in one prompt will be read as a single argument and fail.

**1. Add the marketplace.**

```
/plugin marketplace add fr1j0/bitacora
```

> `Successfully added marketplace: bitacora`

**2. Install the plugin.**

```
/plugin install bitacora@bitacora
```

> `✓ Installed bitacora. Run /reload-plugins to apply.`

**3. Reload to register commands and hooks.**

```
/reload-plugins
```

> `Reloaded: N plugins · M skills · …`

**4. Verify.**

```
/bitacora:help
```

> Prints the Bitácora command reference.

The two opt-in surfaces — the [statusLine](plugins/bitacora/README.md#optional-the-statusline) and the [`/bit:` aliases](plugins/bitacora/README.md#optional-the-shorter-bit-alias) — are documented inline in the plugin README; pick them up when you want them.

**Prerequisites**

- `git`, `jq`, and `bash` 3.2+ on `PATH`. `jq` is required by the handoff guardrail hook; without it the guard fails open with a one-line stderr note rather than silently disabling.
- Atlassian Rovo MCP configured with read/write access to your team's Jira instance *(optional — handoff runs local-only without it, drafting comments to screen instead of writing them)*.
- The [Remember](https://github.com/anthropics/claude-code/tree/main/plugins/remember) plugin or another local memory tool *(optional — for the between-sessions scratch Bitácora delegates rather than manages)*.

**Pinning to a specific revision.** The marketplace points at `main`. To pin to an audited revision, check out a tagged release — the latest is [`v0.5.1`](https://github.com/fr1j0/bitacora/releases/tag/v0.5.1) — or fork the repo and `marketplace add <your-fork>`, or `git clone` and install as a `directory` source (see Claude Code's plugin docs).

**Troubleshooting — `/bitacora:help` says "Not logged in" after `/login`.** The in-session `/login` writes the auth token to disk but doesn't always refresh the running Claude Code process's in-memory auth state — most likely on a freshly bootstrapped profile where Claude Code prompted for login *during* the session. Restart the session: Ctrl+C, re-run `claude` (or `HOME=/whatever claude` if you're testing in an isolated profile), then `/bitacora:help` should work. Sessions that were already logged-in before the install are unaffected.

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

Agents reading the ticket for `/bitacora:resume`, `/bitacora:status`, `/bitacora:digest`, `/bitacora:next`, or cross-ticket queries use only `[CTX]`-prefixed comments — free-form human discussion is ignored for state extraction. (`/bitacora:improve` and `/bitacora:handoff`'s continuity-read are the lenient exceptions: they read everything, because requirements and prior-handoff context often live in human discussion.)

This creates a virtuous loop: the more team members adopt the format, the more useful the shared memory layer becomes. See [`docs/JIRA_AGENT_COMMENT_FORMAT.md`](docs/JIRA_AGENT_COMMENT_FORMAT.md) for the full spec.

## Philosophy and safety

> [!NOTE]
> These aren't features — they're structural commitments, baked in from the start so you can trust the tool with your workflow.

- **Public source.** Read every line. No black boxes.
- **No auto-update.** Plugin updates happen only when you explicitly run `/plugin install` again. No version you didn't choose will land on your machine.
- **No telemetry.** Bitácora does not phone home. No analytics, no usage tracking, no third-party reporting.
- **Pin to a commit if you want.** Fork and lock to a specific revision for full reproducibility.
- **Confirm before writing.** Bitácora never writes to Jira without showing you the draft first. There is no "trust mode" that bypasses this.

## What Bitácora is not

- *Not a memory system.* That's Remember (or claude-mem).
- *Not a Jira client.* That's the Atlassian MCP.
- *Not a context compressor.* It doesn't shrink your live context window — it helps you hand off cleanly and resume, so you can afford to `/clear`.
- *Not a replacement for your judgment.* Every Jira write is confirmation-gated; you decide what goes up.

Bitácora is the *glue* — the opinionated workflow layer that ties these tools into a coherent, team-aware ticket lifecycle.

## Contributing

Currently in alpha. Issues and design discussion are welcome via GitHub Issues — every change starts as an issue. See [CONTRIBUTING.md](CONTRIBUTING.md) for the issue-first flow, branch naming, and maintainer guardrails.

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
