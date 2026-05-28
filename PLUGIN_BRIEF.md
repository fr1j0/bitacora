# Bitácora — Jira-Aware Workflow Plugin for Claude Code

> [!IMPORTANT]
> **Historical document — pre-ship design brief (drafted 2026-05-27).**
>
> This brief documents the **original design intent**. Several claims have since diverged from what shipped:
>
> - **Phase 2** (`/improve-ticket`) was dropped on 2026-05-27, then revived as `/bitacora:improve` (PR #45). The Phase 2 section below has been updated inline to reflect the revival, but the working name `/improve-ticket` is used throughout that block.
> - **Phase 3** (`/status`) shipped as `/bitacora:status` (PR #26, audience-tailored: `--for-pm` / `--for-eng` / `--for-self`).
> - **Phase 4** (`/spike`) was **dropped** (PR #29). Out of scope; do not propose rebuilding.
> - **Phase 5** (`/what-next`) shipped as `/bitacora:next` (PR #42).
> - **Phase 6** (statusLine) shipped (PR #30) — opt-in, with a `✎ handoff pending` segment.
> - The [Repository layout](#repository-layout) sketch (the directory tree near the top) is the *original* design — the actual layout has diverged: no `agents/` directory, skills live as `skills/<name>/SKILL.md` directories, and several files have been added or renamed.
> - The [CTX] example block under [Cross-cutting: agent-comment format discipline](#cross-cutting-agent-comment-format-discipline) shows a date in the header (`[CTX] Status update — <YYYY-MM-DD>`). The **shipped format forbids dates** in headers — the Jira comment's own `created` timestamp is authoritative.
> - The strict/lenient compliance table in the same section labels `/handoff` resume-read as **strict**. The shipped skill (`plugins/bitacora/skills/jira-comment-format/SKILL.md`) defines it as **lenient** — that table row contradicts the operational source of truth and should not be trusted.
>
> **For the shipped surface, see** [`README.md`](README.md) (intro + commands), [`plugins/bitacora/README.md`](plugins/bitacora/README.md) (plugin docs), and the skill files under `plugins/bitacora/skills/*/SKILL.md` (operational source of truth). The skill files always win on any disagreement.
>
> Treat the rest of this document as the design narrative that produced the shipped artifacts. Do not implement claims here without cross-checking the README and skills.

---

> **Brand name:** Bitácora (with accent, for human-facing surfaces)
> **Technical identifier:** `bitacora` (lowercase, ASCII, for repo names, package slugs, shell commands)
>
> Supersedes the earlier `PROJECT_BRIEF.md`. The architecture has changed significantly after surveying the Claude Code ecosystem.

## Why the name

*Bitácora* is the Spanish word for a captain's logbook — historically the structured journal kept aboard a ship to record position, decisions, observations, and events across long voyages. The plugin does exactly that for engineering work: maintains a structured logbook across sessions, tickets, and team members, so progress is preserved even when context windows clear and sessions end. The name is descriptive of the actual function, not metaphorical decoration.

## Context

I'm a software engineer on the Max 20x plan. My daily Claude Code work is feature development on existing projects, bug fixes, code review, and extending existing functionality. Every task is tracked in Jira; my agent already updates Jira tickets with status and changes as part of normal flow.

Previously I used a third-party orchestration tool called "GSD." It turned out to be a scam — crypto rug pull, abandoned project, suspicious auto-update mechanism added late in its lifecycle. I deleted it the moment I saw the auto-update attempt. That experience shapes the safety constraints in this brief: nothing auto-updates, all source is in a private repo I control, no telemetry, no third-party trust beyond what I can audit.

This plugin starts solo in a private GitHub repo. It may later be opened up to colleagues, so the architecture is share-friendly even though distribution is personal at first.

## Architectural decision: extend, don't replace

After surveying the Claude Code ecosystem, the right approach is **not** to build a full orchestration layer from scratch. Several existing plugins already solve the foundational problems well:

| Layer | Existing tool | What it provides |
|-------|---------------|------------------|
| Workflow discipline | **Superpowers** | brainstorm → plan → TDD → subagent dev → review. Open source, ~170K stars, official Anthropic marketplace, maintained by Jesse Vincent (obra). |
| Local session memory | **Remember** (installed/verified) | Cross-session memory persistence. Handles handoff/resume across degrading sessions. (claude-mem is not installed in this environment; Bitácora targets Remember.) |
| Jira/Confluence primitives | **Atlassian Rovo MCP** | Already connected. Read/write tickets, comments, search via JQL. |
| Code review | **pr-review-toolkit** or small custom review skill | Reviewing teammate PRs |

What this custom plugin contributes is the **opinionated Jira-aware workflow layer** that no existing plugin packages. Specifically:

1. **`/handoff`** — clean session wrap-up tied to Jira
2. **`/improve-ticket`** — sharpen vague PM-authored tickets
3. **`/status`** — human-readable ticket synthesis for PMs, teammates, or self after a gap
4. **`/spike`** — timeboxed exploration with mandatory conclusions
5. **`/what-next`** — smart ticket picker with categorization and reasoning
6. **statusLine** — context-window meter with progressive UX
7. **Standardized agent-comment format** — discipline used across all of the above (with compliance rules for reading)

These six commands plus the cross-cutting comment discipline form a coherent ticket-lifecycle suite. Each command earns its place independently, and the build order is structured so that stopping after any phase still leaves a useful plugin.

## Why this plugin makes sense

Most of the engineering work in scope (features on existing projects, bug fixes, extensions) fits Superpowers' methodology cleanly. The gap is around *Jira as a workflow surface* — picking tickets, sharpening them, exploring ideas, writing structured updates back. The team already does much of this manually; the plugin formalizes and amplifies it.

The longer-term ambition: if the team adopts the comment-format conventions, Jira becomes a shared external memory layer that any team member's agent can read to bootstrap context. New hires onboard self-serve; "cover this while I'm out" works without handoff meetings; cross-engineer redundancy drops. That value compounds with team adoption, but the plugin is useful solo from day one.

## Repository layout

```
plugin-repo/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   └── bitacora/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── README.md
│       ├── commands/
│       │   ├── handoff.md
│       │   ├── improve-ticket.md
│       │   ├── status.md
│       │   ├── spike.md
│       │   └── what-next.md
│       ├── agents/
│       │   ├── ticket-improver.md
│       │   ├── status-synthesizer.md
│       │   ├── spike-runner.md
│       │   └── ticket-ranker.md
│       ├── skills/
│       │   └── jira-comment-format.md
│       ├── hooks/
│       │   └── (lifecycle hooks as needed)
│       ├── templates/
│       │   ├── handoff.md
│       │   ├── jira-update.md
│       │   ├── status-output.md
│       │   └── spike-conclusion.md
│       └── statusline/
│           └── statusline.sh
└── docs/
    └── JIRA_AGENT_COMMENT_FORMAT.md
```

---

## Command specifications

### `/handoff`

**Purpose:** Clean session wrap-up when context starts degrading (statusLine in amber/red) or at any natural phase boundary. Writes a structured Jira comment with formal status, plus a local handoff with the gritty mid-task detail.

**Flow:**

1. User invokes `/handoff` (typically when statusLine hits ~70–80%, or after completing a logical chunk).
2. Agent identifies the active Jira ticket (from session context, recent ticket reads, or asks if ambiguous).
3. Agent writes **two** outputs:
   - A formal Jira comment in the standard `[CTX]` format (status, decisions, next, blockers)
   - A local handoff file via claude-mem/Remember capturing mid-task scratch (exploration notes, dead ends, fragile-codebase warnings, things-not-for-public-comment)
4. User confirms before either is committed.
5. Once confirmed, both are written and the user can `/clear` or exit cleanly.

**Resume flow** (handled by claude-mem/Remember on next session): SessionStart hook pulls the latest local handoff and injects it; agent restates understanding at first response; user confirms or corrects before continuing.

**Key design rules:**

- Two writes, not one. Jira ≠ scratch. Don't collapse them.
- Always show drafts and require confirmation before writing to Jira.
- Jira comment is outcome-oriented (*what changed and why*), not process-oriented (*how I figured it out*). This is the single biggest token-saving discipline.

---

### `/improve-ticket <TICKET-ID>`

**Purpose:** Take a vague, technically weak, or poorly documented Jira ticket (typically PM-authored) and produce a sharper version with proper acceptance criteria, technical context, and surfaced ambiguities.

**Flow:**

```
/improve-ticket PROJ-1234

Reading ticket... done.
Original is 47 words, missing acceptance criteria and technical context.

3 questions before rewriting:

1. "users want this faster" — do we have a target metric,
   or is this qualitative?
2. "should work on mobile" — responsive web, PWA, or
   native? The codebase has all three.
3. Linked Slack thread mentions Sarah's caching idea — in
   scope or follow-up?

Reply with answers or "skip" to proceed without.
```

After clarifying questions, agent produces a structured rewrite that **preserves the PM's original text as a section** ("Business context") and adds:

- **Acceptance criteria** — testable, specific
- **Technical notes** — constraints, gotchas, affected modules
- **Out of scope** — explicit non-goals
- **Open questions** — anything still unresolved
- **Effort estimate** — rough

Agent shows diff, user tweaks, then writes back to Jira with a `[CTX] Ticket sharpened by agent` comment for the audit trail.

**Key design rules:**

- **Never silently rewrite.** Always surface clarifying questions first, show diff before write.
- **Preserve the PM's original text** as a named section. Don't erase their entry point to the ticket.
- **Don't strip "wrong" information** — flag it as a question. The PM may have context the agent doesn't see.
- Leave audit-trail comment so changes are traceable.

---

### `/status <TICKET-ID>`

**Purpose:** Human-readable synthesis of a ticket's current state, for PMs asking "where is this?", teammates covering for you, or yourself after a gap. Closes the loop on the Jira-as-shared-memory pattern by making the `[CTX]` corpus consumable.

**Flow:**

1. Agent reads the ticket: description, all `[CTX]` comments in order, status field, recent activity timeline.
2. Optionally pulls linked Confluence pages and related tickets (blockers, blocked-by, child tickets).
3. Synthesizes into a format appropriate for the asker — outcomes over process, decisions over implementation, risks and ETA where relevant.
4. Outputs for reading, pasting into Slack, or posting back as a Jira comment (with explicit confirmation).

**Output mockup:**

```
PROJ-1234 — OAuth callback handling

Status:    In Progress (started 4 days ago)
Assignee:  You
ETA:       1-2 more days, based on remaining scope

━━━ What's been done ━━━

  • OAuth provider client implemented and tested
  • Callback handler ~80% complete (happy path working)
  • Integration tests for success cases passing

━━━ What's left ━━━

  • Token refresh implementation
  • Error path handling (expired tokens, invalid state)
  • Concurrent refresh edge case

━━━ Key decisions ━━━

  • PKCE flow (not legacy implicit) — more secure, standard for SPAs
  • Tokens in HTTPOnly cookies (not localStorage) — better XSS resistance
  • Silent refresh on 401, no proactive refresh

━━━ Blockers ━━━

  None currently. Earlier blocker on API contract resolved Tuesday.

━━━ Risks worth flagging ━━━

  • Token refresh may interact with existing session middleware;
    might require coordination with PROJ-1298.

Last meaningful update: 2 hours ago.

Note: 4 comments not in [CTX] format were excluded from this 
synthesis (3 discussion comments, 1 reaction). Run with 
--include-all to see them.
```

**Audience modes:**

- `/status PROJ-1234` — default, balanced for either audience
- `/status PROJ-1234 --for-pm` — outcomes only, no technical detail, ETAs prominent
- `/status PROJ-1234 --for-eng` — technical depth, blockers' technical roots, dependencies
- `/status PROJ-1234 --for-self` — first-person, includes mid-task scratch from local claude-mem state

**Extensions for v2:**

- `/status --epic EPIC-123` — rolls up child ticket statuses into an epic-level summary
- `/status --my-sprint` — what I'm supposed to deliver this sprint and where each piece is
- `/status PROJ-1234 "why is this blocked?"` — focused question against the ticket's history

**Key design rules:**

- **Skip non-compliant comments** for synthesis (see comment compliance rules below). State extraction must come from `[CTX]` comments only; non-compliant comments are surfaced as a count, not synthesized.
- **Never fabricate ETAs.** If data doesn't support a confident estimate, say so explicitly (`ETA: insufficient data — last update was 8 days ago`).
- **Never auto-post to Jira.** Default to draft-and-show. PM-facing comments need engineer review — they'll be read as your words.
- **Surface data gaps honestly.** If there are no recent `[CTX]` comments, the output should say "no agent-written context updates in the last N days; this synthesis is based on git activity and the original description."

**Delivery paths:**

This is a Claude Code slash command, so the PM doesn't run it directly. Typical flows:

1. PM asks the engineer, engineer runs `/status`, pastes the output.
2. Engineer posts the output as a Jira comment with a `[STATUS]` prefix (distinct from `[CTX]` updates) so it's visible to everyone going forward.
3. Recurring cadence — Friday afternoon, engineer runs `/status` on all active tickets, drops to Slack or a Confluence dashboard.

A future direction worth flagging but out of scope for v1: webhook integration where a PM mentioning `@agent` in a Jira comment triggers an auto-status reply. Requires Jira Automation infrastructure beyond the plugin's surface.

---

### `/spike <description>`

**Purpose:** Frictionless creation of timeboxed exploratory tickets for unvalidated ideas, with enforced conclusions to prevent procrastination patterns.

**Flow:**

1. Agent creates a spike ticket in Jira (proper issue type if team has one, otherwise `[SPIKE]` prefix in title).
2. Generates structured spike template:
   - Question being investigated
   - Approach (how will it be evaluated?)
   - Success/failure criteria
   - Timebox (default 2–4 hours, configurable)
   - Output expectations (recommendation, not artifact)
3. Optionally launches a Claude Code session scoped to the spike.
4. Session emphasizes throwaway code, no TDD, no production quality bar.
5. At session end, **enforced conclusion template**:

```
SPIKE CONCLUSION — PROJ-XXXX

Question:        [restated]
What I tried:    [approaches taken]
What I found:    [findings]

RECOMMENDATION:  ⚪ build  ⚪ don't build  ⚪ build with caveats
                 [MANDATORY — pick one]

If "build":     rough effort, key risks, suggested implementation ticket
If "don't":     why, what would have to change, alternatives considered
```

6. If recommendation is "build," offer to generate the implementation ticket inline.

**Key design rules:**

- **Mandatory recommendation field.** The single most important detail. Without it, spikes become a procrastination vector ("just run another spike").
- **Throwaway-friendly framing.** Skill prompt explicitly states code is disposable; deliverable is a recommendation.
- **Convert to commit when ready.** Spike → implementation ticket transition is one confirmation away.

---

### `/what-next`

**Purpose:** Smart morning ticket picker that reads the user's Jira boards and produces a ranked, categorized shortlist with reasoning.

**Flow:**

1. Agent pulls relevant tickets from Jira boards via MCP (configurable scope: my tickets / my team / specific board).
2. Reads ticket metadata, comments, status, recent activity.
3. Categorizes:
   - **Continue where you left off** — recently touched, lowest pickup cost
   - **Ready to start** — properly specced, unblocked, ranked by impact
   - **Quick wins** — small estimated effort, completes cleanly
   - **Blocked, worth nudging** — old enough that a ping is warranted
   - **Stale, consider closing** — surface for cleanup, not work
4. For each ticket, produces a one-phrase **reason-to-pick** annotation.
5. Renders in the format below.
6. User picks via `/pick PROJ-XXXX` or refines with `/what-next` again.

**UI mockup:**

```
Picked up 47 tickets from your boards. Here's today's shortlist:

━━━ Continue where you left off ━━━

→ PROJ-1234  OAuth callback handling                 [In Progress]
  Started 2d ago · 3 commits · auth subsystem
  Last handoff: "callback wired, next is token refresh"
  Est. 2-3h to complete · Pickup cost: low
  ★ Recommended — near completion, lowest context cost

━━━ Ready to start ━━━

  PROJ-1287  Migrate user prefs to new schema       [Ready]  P1
  Spec finalized · Blocks PROJ-1290, PROJ-1291
  Design: confluence/eng/prefs-migration
  Est. 4-6h · If completed today, unblocks Sarah + Tom

  PROJ-1311  Fix flaky auth integration test         [Ready]  P2
  Reproduces 30% of CI runs · likely race in mock setup
  Est. 1-2h · Quick win candidate

━━━ Blocked, worth nudging ━━━

  PROJ-1298  Refactor session middleware             [Blocked]
  Waiting on @sarah · API contract review · 6d silent
  → consider pinging or pulling in a sync

━━━ Stale (consider closing) ━━━

  PROJ-1156  Dark mode preference toggle             [Open]
  Last activity 47d ago · no current discussion
  → archive, deprioritize, or pull forward

Pick one with /pick PROJ-1234, or /next for a different cut.
```

**Key design rules:**

- **Reason-to-pick on every line.** Without it, this is just a list; with it, it's a decision aid.
- **Recommendation arrow on top item** — strong visual nudge without overruling.
- **Stale section for cleanup, not selection** — keeps the picker signal-rich.
- **Two-option footer** (pick / refine). Three would be too many.

**Extensions to consider after v1:**

- `/what-next 90min` — energy/time-matched filtering
- `/what-next --boring` vs `--interesting` — mode-based filtering
- `/what-next --why-not` — surface next-5 candidates with reasoning for visibility

---

### statusLine

**Purpose:** Always-visible peripheral cue showing context window utilization, so I know *when* to `/handoff` or `/context` without having to think about it.

**Design principles:**

- *Glanceable* — readable in under half a second
- *Stable* — doesn't jitter
- *Progressive* — calm at low context, more insistent as it fills
- *Redundant cues* — never rely on color alone
- *Width-aware* — degrades gracefully on narrow terminals

**Calm-state design (Variant C, "floor-aware"):**

```
opus-4.7 · 23%  ▒▒▓▓░░░░░░  floor:16K  work:31K  free:153K
```

- `▒` shading = baseline overhead (system prompt + tools + skills)
- `▓` shading = actual session work
- `░` = free space
- Distinguishes baseline overhead from session work — critical because a 23% reading where most is floor feels different from one where most is your work.

**Critical-state design (Variant E shape-shift):**

```
⚠ opus-4.7 · 87%  ▓▓▓▓▓▓▓▓▓░  174K/200K  → /handoff now
```

- Shape change at ≥85% is itself the signal
- Embedded advice tells the user what to do

**Threshold and color palette:**

| Range | Color | Status | Behavior |
|-------|-------|--------|----------|
| 0–50% | green | `ok` | calm display (Variant C) |
| 50–75% | amber | `warn` | same shape, color shift |
| 75–85% | orange/red | `high` | same shape, color shift |
| 85%+ | bright red | `critical` | shape changes to Variant E |

**Implementation notes:**

- statusLine runs continuously — script must be fast. Use `jq` for JSON parsing, avoid heavier processes.
- Before writing the script for real, run a no-op statusLine that just dumps stdin to a log, trigger Claude Code, and inspect the actual session JSON. Field names change between versions; write against what your installed version actually emits, not blog-post screenshots.
- Test on multiple terminal themes (Solarized, Dracula, default). Avoid pure red/green; assume varied contrast.

**Task-awareness (optional add-on):**

If pulling active Jira ticket from a local state file maintained by `/handoff` and `/what-next`, can show:

```
PROJ-1234 · opus-4.7 · 23%  ▒▒▓▓░░░░░░  1h12m
```

---

### Cross-cutting: agent-comment format discipline

**Why this matters:** This is the highest-leverage single intervention in the whole plugin. If team adoption ever happens, the comment format is what turns Jira from "ad-hoc dumping ground" into "shared external memory layer that any agent can read."

**The format spec (lives in `docs/JIRA_AGENT_COMMENT_FORMAT.md`):**

Every agent-written comment uses a `[CTX]` prefix and one of these structures depending on context:

**Status update (most common):**

```
[CTX] Status update — <YYYY-MM-DD>

Status: <state>
Done:
  - <bullet>
  - <bullet>
Decisions:
  - <bullet, with rationale>
Next:
  - <bullet>
Blockers:
  - <bullet> (if any)
```

**Ticket sharpening (from `/improve-ticket`):**

```
[CTX] Ticket sharpened by agent — <YYYY-MM-DD>

Sections added: acceptance criteria, technical notes, out of scope
Original PM description preserved as "Business context" section.
Open questions surfaced inline.
```

**Spike conclusion (from `/spike`):**

```
[CTX] Spike concluded — <YYYY-MM-DD>

Question: <restated>
Recommendation: <build | don't build | build with caveats>
Summary: <2-3 sentences>
Full conclusion: <link to handoff or Confluence page>
```

**Rules (hard, not soft):**

- **Outcome-oriented**, not process-oriented. *What changed and why*, not *how I figured it out*.
- **No verbose play-by-play**, no code diffs in comments (link to PR), no exploration scratch (that goes in local handoff).
- **No mid-task speculation** ("maybe we should try X?") — those go in local handoff. Comments are for stable claims.
- **One comment per logical update**, not one per Claude turn.

**Read-side compliance rules (when agents extract state from comments):**

Strict skipping applies for *state-extraction* operations. Non-strict (read everything) applies for *requirements-understanding* operations.

| Operation | Mode | Why |
|-----------|------|-----|
| `/status` synthesis | strict — `[CTX]` only | Non-compliant comments are noise; mixing them produces inconsistent synthesis. |
| `/handoff` resume read | strict — `[CTX]` only | Most recent `[CTX]` is the canonical resume target. |
| `/what-next` activity signals | strict — `[CTX]` only | Activity ranking should count meaningful updates, not reactions. |
| Cross-ticket JQL queries (e.g. "find blocked") | strict | Only meaningful against structured fields. |
| `/improve-ticket` source read | lenient — read everything | PM discussion and original description is exactly what's needed. |
| Initial ticket onboarding | lenient | When no `[CTX]` exists yet, fall back rather than refuse to engage. |
| Decision archaeology | lenient | Some "we decided X because Y" lives in human discussion, never promoted to `[CTX]`. |

**Behavior when comments are skipped:**

Surface the skip count in output, don't silently pretend they don't exist:

```
Note: 4 comments not in [CTX] format were excluded from this 
synthesis. Run with --include-all to see them.
```

This is honest about the synthesis being partial, and creates gentle pressure toward adoption without being preachy. Engineers (and PMs) see "4 excluded" and start writing in the format.

**Matching rules:**

- **Strict prefix matching only.** A comment starts with `[CTX]` or it doesn't count. Don't try to be clever about fuzzy matches (`Status update:` ≠ `[CTX] Status update:`). Fuzzy matching becomes its own bug source; strict matching is simpler and more reliable.
- **No partial-credit compliance.** A `[CTX]` comment missing required sections is treated as non-compliant. Better to enforce fully or not at all.

**Plugin compliance config** (lives in plugin settings, override per command if needed):

```yaml
comment_compliance:
  status_extraction: strict       # /status, /handoff resume, /what-next
  requirements_reading: lenient   # /improve-ticket, onboarding
  show_excluded_count: true       # surface skipped comments in output
  partial_match: false            # strict prefix only
```

**The discipline-incentive angle:**

Strict skipping isn't primarily about reading efficiency — it's about creating a behavioral incentive. If your comments don't follow the format, the agent ignores them for state extraction. Engineers (and PMs) quickly notice this and start writing in the format if they want to be heard. The plugin becomes a forcing function for the convention, which is the only way team adoption sticks.

This only works if write-side enforcement is also tight. The two halves move together — write strict, read strict. Agents writing via `/handoff` always emit compliant `[CTX]` comments; agents reading via `/status` skip non-compliant. The corpus quality compounds over time.

---

## Build order

Phased so each step is shippable and validates before the next investment. Stopping at any point still leaves a useful plugin.

### Phase 1 — `/handoff` + comment discipline + Superpowers/claude-mem integration

The foundation. Highest daily value, builds on existing Jira-comment habit, validates the comment format spec.

- Plugin scaffolding (`marketplace.json`, `plugin.json`)
- `commands/handoff.md` + handoff template
- `skills/jira-comment-format.md`
- `docs/JIRA_AGENT_COMMENT_FORMAT.md`
- Wire to claude-mem (or Remember) for the local-memory half of handoff
- Wire to Atlassian MCP for the Jira-comment half

**Acceptance test:** Complete a task, run `/handoff`, exit, start fresh session, see resumed state from claude-mem with correct restatement. Jira ticket has a clean structured comment.

### Phase 2 — `/improve-ticket` — **revived (2026-05-28)**

> **Building this.** Originally dropped on 2026-05-27 (PR #28) because the value-add was
> framed as "local-codebase-grounded technical notes," too thin against Jira's native
> Atlassian Intelligence / Rovo. The revival reframes the value: the corpus advantage —
> `[CTX]` trail + free-form comments + local Remember scratch + git/PR history for the
> ticket key — is what Jira's in-ticket AI cannot see, and is the real differentiator.
> See `docs/superpowers/specs/2026-05-28-bitacora-improve-design.md`. Original sketch
> retained below for history.

Immediate utility, low risk with the confirm-before-write rule.

- `commands/improve-ticket.md`
- `agents/ticket-improver.md`
- `templates/jira-update.md` (rewrite template)

**Acceptance test:** Improve a real vague ticket, surface meaningful clarifying questions, produce a rewrite that preserves PM intent while adding technical structure.

### Phase 3 — `/status`

Closes the loop on the Jira-as-shared-memory pattern. After a few weeks of Phase 1 `/handoff` usage, the structured `[CTX]` corpus is rich enough to synthesize from. Lower risk than `/spike` or `/what-next` because it's read-only by default.

- `commands/status.md`
- `agents/status-synthesizer.md`
- `templates/status-output.md`
- Compliance rules wired in (strict for state extraction)

**Acceptance test:** Run `/status` on a real ticket with multiple `[CTX]` updates. Synthesis is accurate, audience modes produce meaningfully different outputs, skipped-comment count is surfaced honestly when present.

### Phase 4 — `/spike` — **dropped (2026-05-27)**

> **Not building this.** `/spike` is ticket *authoring* (creation), which sits outside
> Bitácora's scope: a status-tracking / continuity layer that reads and writes structured
> state on tickets that already exist. Singling out "spike" creation is also arbitrary
> (why not stories or bugs?), and native Jira already creates tickets. The one in-DNA
> nugget — a forced "build / don't build / build with caveats" recommendation at a spike's
> conclusion — already fits the existing `[CTX]` `Status:` line (as TESTING-10 demonstrated:
> `Status: Spike complete — RECOMMENDATION: build with caveats`). Dropped alongside
> `/improve-ticket`; the two share a lesson: **Bitácora is a memory layer, not a
> ticket-authoring tool.** Original sketch retained below for history.

High-value but the design hinges on the recommendation-forcing template. Needs real-use iteration.

- `commands/spike.md`
- `agents/spike-runner.md`
- `templates/spike-conclusion.md`
- Spike ticket creation logic via MCP

**Acceptance test:** Run a spike end-to-end. Forced recommendation field at conclusion. If "build," generate an implementation ticket inline.

### Phase 5 — `/what-next`

Most ambitious. Depends on previous phases having populated Jira with high-quality structured content for it to pick from.

- `commands/what-next.md`
- `agents/ticket-ranker.md`
- JQL query logic + ranking heuristics
- Presentation template

**Acceptance test:** Run `/what-next` in the morning. Produce a categorized shortlist with reason-to-pick annotations. Pick correctness > 50% of the time.

### Phase 6 — statusLine

Cosmetic but compounding. Friday-afternoon piece. Build last.

- `statusline/statusline.sh`
- Wire into `~/.claude/settings.json` (or plugin config if supported)

**Acceptance test:** statusLine shows correctly across all four threshold ranges. Shape-shifts at 85%. Tested on multiple terminal themes.

### Phase 7 (optional, later) — team distribution

- Decide whether to formalize PR review
- Add colleagues as repo collaborators
- Pitch comment format to the team as a shared convention

---

## Risks and guardrails

**1. Auto-creating or auto-updating tickets needs hard guardrails.**

Default flow: *draft → show → confirm → write.* Always. Cost of one accidental ticket spam is real team friction. No "trust mode" that bypasses confirmation.

**2. Some teams care about Jira ticket-history for compliance.**

The "preserve PM text as a section" rule handles most cases. For stricter shops, leave the original as a frozen quoted block at the top of the description.

**3. Don't condescend in rewrites.**

PMs see the rewritten tickets. The tone should be additive ("here's more detail we'll need"), not corrective ("here's what was wrong"). The agent's prompt for `/improve-ticket` should explicitly instruct this.

**4. Comment-format adoption is the actual failure mode for team rollout.**

Partial adoption is worse than no adoption — people get false confidence in incomplete shared memory. If pitching to the team, get an explicit commitment from a critical mass, or don't pitch yet.

**5. The plugin itself runs solo first.**

No team-wide install until the comment format and command behaviors have been validated by personal use for at least a few weeks. Don't pitch what you haven't road-tested.

**6. No auto-update mechanism.**

This is a hard architectural rule, not a setting. Plugin updates require explicit reinstall. Source lives in a private GitHub repo I control. No telemetry, no phone-home.

---

## Open questions to decide during build

- Whether the local handoff lives repo-local (`.claude-sessions/`) or global (`~/.claude-sessions/`). Repo-local is better for per-project state; global is better for cross-project continuity.
- Exact JQL queries for `/what-next` — depends on team's board structure and label conventions.
- Default spike timebox — start with 3 hours, iterate.
- Whether to support GitHub Issues as an alternative to Jira (probably no for v1, keep scope tight).
- Whether `/handoff` should *always* create a Jira comment, or only on explicit `/handoff --jira`. Default likely yes-always, but worth testing.

---

## Distribution and installation

**Repository:** Public GitHub repo. Bitácora will be open-sourced once Phase 1 is validated through personal use.

**Development phase (pre-release):**

Build and validate against personal use first in a private repo. Public release happens only after Phase 1 is genuinely working day-to-day — don't ship what hasn't been road-tested.

**Installation (once public):**

```
/plugin marketplace add <owner>/bitacora
/plugin install bitacora@bitacora
```

User scope (`~/.claude/`) so plugin applies across all projects.

**License:** TBD — consider MIT or Apache 2.0 for permissive use.

**Safety properties (explicit):**

- No auto-update mechanism — plugin updates require explicit user-initiated reinstall
- No telemetry, no phone-home, no usage tracking
- Public source means diffs are auditable by anyone before any version change
- Anyone using Bitácora can pin to a specific commit for reproducibility guarantees
- Repository ownership and release decisions stay with the maintainer; no third-party publishing rights

**The GSD lesson encoded here:**

Bitácora's public-source, no-auto-update, no-telemetry architecture is the structural answer to the failure mode that motivated this project. Anyone using Bitácora can read every line of it, pin to whatever commit they trust, and know with certainty that no version they didn't choose will land on their machine.

---

## Starting instructions for Claude Code

When picking this up: read this whole brief, then start with Phase 1. Use the `/plan` workflow from Superpowers to break Phase 1 into concrete tasks before writing any code. Confirm the task graph with me before executing.

Do not skip phases. Do not pre-build infrastructure for later phases. Each phase ships independently and validates the design before the next investment.
