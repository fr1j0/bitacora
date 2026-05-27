# `/bitacora:status` Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/bitacora:status [KEY] [--for-pm|--for-eng|--for-self]` — a read-only command that synthesizes a Jira ticket's latest `[CTX]` into an audience-tailored summary, prints it, and offers a clipboard copy.

**Architecture:** A new prose-driven `session-status` skill holds the workflow (parse → resolve ticket → resolve site → strict `[CTX]` read → per-mode render → print + clipboard). Thin `commands/status.md` and `alias/bit-status.md` delegate to it, mirroring the existing `session-resume` sibling. No new code modules — the plugin is composed of Markdown skill/command files; "tests" are frontmatter validity, listing consistency, and manual acceptance against a live ticket.

**Tech Stack:** Claude Code plugin (Markdown commands + skills), Atlassian Rovo MCP (read), git, shell clipboard tools (`pbcopy`/`wl-copy`/`xclip`/`clip`).

**Spec:** `docs/superpowers/specs/2026-05-27-bitacora-status-design.md`

**Branch:** Work on `feat/bitacora-status` (already created). Commit per task. **Do not add `Co-Authored-By` trailers** (project convention). Open a PR at the end; do not merge to `main` (branch-protected).

---

## File Structure

| File | Responsibility |
|------|----------------|
| `plugins/bitacora/skills/session-status/SKILL.md` | The workflow (all real logic lives here) |
| `plugins/bitacora/skills/session-status/examples/self.txt` | One `[CTX]` rendered in `--for-self` |
| `plugins/bitacora/skills/session-status/examples/eng.txt` | Same `[CTX]` rendered in `--for-eng` |
| `plugins/bitacora/skills/session-status/examples/pm.txt` | Same `[CTX]` rendered in `--for-pm` |
| `plugins/bitacora/commands/status.md` | Registers `/bitacora:status`; delegates to skill |
| `plugins/bitacora/alias/bit-status.md` | Opt-in `/bit:status`; delegates to skill |
| `plugins/bitacora/commands/help.md` | Move `/status` Planned → Shipped (keep in sync) |
| `plugins/bitacora/alias/bit-help.md` | Mirror of help.md fenced block |
| `README.md` (root) | Commands table: `/status` 🚧 → ✅ |
| `plugins/bitacora/README.md` | Add `/status` row; update alias prose list |

---

## Task 1: Create the `session-status` skill

**Files:**
- Create: `plugins/bitacora/skills/session-status/SKILL.md`

- [ ] **Step 1: Write the skill file**

Create `plugins/bitacora/skills/session-status/SKILL.md` with exactly this content:

````markdown
---
name: session-status
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary — --for-self (terse recall), --for-eng (technical handoff), or --for-pm (plain-language stakeholder status). Read-only; prints the summary and offers a clipboard copy. Use when the user runs /bitacora:status or /bit:status.
---

Read a ticket's latest `[CTX]` state and synthesize an **audience-tailored summary**, then
print it and offer to copy it to the clipboard. This is a **sibling to
`bitacora:session-resume`**: same ticket resolution and the same strict `[CTX]` read, but
status produces a standalone summary *for a human reader* rather than rehydrating the
working agent. It is strictly **read-only** — it never writes to Jira or mutates Remember,
so there is no confirmation gate. Follow the **READ** rules in
`bitacora:jira-comment-format` (strict `status_extraction`) for extracting state.

## 1. Parse arguments

- **Mode flag:** `--for-pm`, `--for-eng`, or `--for-self`. An explicit flag always wins;
  with no flag, fall back to `status.default_mode` (built-in default `self`). An unknown
  flag or more than one mode flag is an error — name the valid modes and stop; never guess.
- **Ticket key:** any `project_key_pattern` match in the arguments forces the target.
- **`--include-all`:** optional; reveal the excluded (non-`[CTX]` / malformed) comments
  instead of only counting them.

## 2. Resolve the target ticket (single, focused)

Resolve exactly one ticket, in priority order (identical to resume):

- **Explicit key** in the arguments (`project_key_pattern` match) — forces it.
- **Current branch:** `git branch --show-current`, extract a `project_key_pattern` match.
- **Recent checkouts:** `git reflog --date=iso | grep -i checkout | head -n 20` — extract
  key matches from branch names, de-duplicate, cap at ≈20. If several distinct candidates
  surface, **list them and let the user pick**. Never guess between them.
- **Nothing resolves:** ask for a key once (no nag); stop.

## 3. Resolve the Atlassian site

`getAccessibleAtlassianResources` → `cloudId`. If multiple sites, use the `jira_cloud_id`
override if configured, else ask. **If the MCP is absent, auth fails, or the site can't be
resolved, this is a hard stop** (see Error behavior) — status cannot do its job without
Jira read access.

## 4. Read the ticket (strict [CTX])

`getJiraIssue` for the resolved key, **requesting comments**. Extract `[CTX]` comments per
the **strict** READ rules in `bitacora:jira-comment-format`:

- Count only **compliant** `[CTX]` comments (start with `[CTX]`, carry `Status:` + `Next:`).
- The **latest** compliant `[CTX]` is authoritative for `Status` and `Next`.
- Stitch up to `status.ctx_lookback` prior `[CTX]` comments (default 2) to build a short
  Done/progress trajectory.
- Use each comment's own `created` timestamp from the API — **never a hand-typed date**.
- Surface excluded counts separately (non-`[CTX]`, malformed); never silently drop. With
  `--include-all`, print the excluded comments too.

## 5. Render for the selected mode

Faithful, condensed, **no invention**. Omit any section the `[CTX]` did not contain.
Preserve URLs verbatim except where a mode strips them (below). Rephrasing the `Status:`
value into plain language for PM is allowed; inventing facts is not.

### --for-self (default) — terse personal recall (jargon + PR links fine)

```
PROJ-1234 "<title>" — <Jira status>
Left off:   <latest Status>
Next:       <Next bullets>
Decisions:  <decision bullets>        (only if present)
Blockers:   <bullets>                 (only if present)
```

### --for-eng — technical teammate handoff (keep links, rationale, detail)

```
PROJ-1234 "<title>" — <Jira status>
https://<site>/browse/PROJ-1234

Done recently:
- <Done across the lookback window>
Decisions:
- <decision + rationale>
Next:
- <Next bullets>
Blockers / open questions:
- <only if present>
```

### --for-pm — plain-language stakeholder status (strip jargon + PR hashes; lead with state/risk; keep ticket link)

```
PROJ-1234 "<title>"
https://<site>/browse/PROJ-1234

Status:        <on track / blocked / in progress — plain words>
Progress:      <outcome-oriented Done across the lookback, jargon stripped>
What's next:   <Next in plain language>
Risks / needs: <Blockers + Open questions, framed as asks>   (only if present)
```

See `examples/self.txt`, `examples/eng.txt`, `examples/pm.txt` — the same `[CTX]` rendered
in all three modes.

## 6. Print, then offer a clipboard copy

Print the rendered summary into the conversation. Then offer to copy it to the clipboard —
**read-only, no Jira write, no gate**. Clipboard is best-effort: pipe the rendered text to
the first available of `pbcopy` (macOS), `wl-copy` or `xclip -selection clipboard` (Linux),
or `clip` (Windows). If none is found, skip the offer silently — the printed summary always
stands on its own.

## Error / edge behavior

- **Atlassian MCP absent / auth fails / site unresolvable:** **hard stop.** Report the
  reason and point to MCP setup; do not pretend a local-only fallback.
- **No `[CTX]` on the ticket:** say so plainly; show the Jira workflow status + title for
  orientation; suggest running `/bitacora:handoff` so future summaries have something to
  read.
- **Ticket 404 / no read permission:** surface the reason for that key; offer to retry with
  a different key. No retry loop.
- **No ticket resolved:** say so; suggest passing a key.
- **Invalid / conflicting mode flag:** error listing the valid modes; do not guess.

## Configuration

Reuses `project_key_pattern`, the compliance modes (strict for status), and `jira_cloud_id`
from the `bitacora:jira-comment-format` / handoff config
(`${CLAUDE_PROJECT_DIR}/.bitacora.yml` then `~/.claude/bitacora.yml`; absence is normal).
Two optional additions:

```yaml
status:
  ctx_lookback: 2        # prior [CTX] stitched for the Done/progress trajectory
  default_mode: self     # self | eng | pm — overrides the built-in default mode
```
````

- [ ] **Step 2: Verify the skill file exists and has valid frontmatter**

Run:
```bash
head -3 plugins/bitacora/skills/session-status/SKILL.md
```
Expected: first line `---`, second line begins `name: session-status`, third line begins `description:`.

- [ ] **Step 3: Commit**

```bash
git add plugins/bitacora/skills/session-status/SKILL.md
git commit -m "feat(status): add session-status skill workflow"
```

---

## Task 2: Add the three-mode example fixtures

**Files:**
- Create: `plugins/bitacora/skills/session-status/examples/self.txt`
- Create: `plugins/bitacora/skills/session-status/examples/eng.txt`
- Create: `plugins/bitacora/skills/session-status/examples/pm.txt`

These render the **same** source `[CTX]` (an OAuth-login ticket `AUTH-204`, latest update plus one prior for trajectory) three ways. They are documentation + the rendering acceptance reference. The source they represent:

```
Latest [CTX]:  Status: In Progress
               Done: token refresh implemented (rotating refresh tokens), covered by
                     integration tests vs the staging IdP
               Decisions: store refresh tokens httpOnly+Secure server-side, never
                     localStorage (XSS exposure)
               Next: wire refresh into SPA silent-renew; decide session idle-timeout
               Blockers: need product to confirm idle-timeout (30m vs 60m)
               Open questions: should "remember me" extend refresh lifetime, how long?
Prior [CTX]:   Done: OAuth provider client (PKCE), callback happy path
```

- [ ] **Step 1: Write `examples/self.txt`**

```
AUTH-204 "OAuth login" — In Progress
Left off:   Token refresh implemented (rotating refresh tokens), covered by integration tests.
Next:
- Wire refresh into the SPA silent-renew flow
- Decide session idle-timeout with product
Decisions:
- Refresh tokens httpOnly+Secure server-side, never localStorage (XSS)
Blockers:
- Product to confirm idle-timeout (30m vs 60m)
```

- [ ] **Step 2: Write `examples/eng.txt`**

```
AUTH-204 "OAuth login" — In Progress
https://acme.atlassian.net/browse/AUTH-204

Done recently:
- OAuth provider client (PKCE) and callback happy path
- Token refresh with rotating refresh tokens, covered by integration tests vs the staging IdP
Decisions:
- Store refresh tokens httpOnly+Secure server-side, never in localStorage — avoids XSS token theft
Next:
- Wire refresh into the SPA silent-renew flow
- Decide session idle-timeout with product
Blockers / open questions:
- Blocked on product confirming idle-timeout (30m vs 60m)
- Open: should "remember me" extend refresh lifetime, and to how long?
```

- [ ] **Step 3: Write `examples/pm.txt`**

```
AUTH-204 "OAuth login"
https://acme.atlassian.net/browse/AUTH-204

Status:        On track, in progress — core sign-in works; finishing the "stay signed in" piece.
Progress:      Users can sign in, and their session now renews automatically in the background.
What's next:   Hook the auto-renew into the web app, then settle how long a session stays active.
Risks / needs: Need a product decision on idle timeout (30 vs 60 min). Open question: should "remember me" keep people signed in longer, and for how long?
```

- [ ] **Step 4: Verify the fixtures differ in emphasis/jargon**

The PM view must be jargon-free (self/eng may carry jargon — that's fine). Run:
```bash
grep -l "PKCE\|httpOnly\|IdP" plugins/bitacora/skills/session-status/examples/pm.txt || echo "PM CLEAN"
```
Expected: `PM CLEAN` (none of those technical terms appear in the PM rendering).

Run:
```bash
grep -c "Progress:" plugins/bitacora/skills/session-status/examples/pm.txt
```
Expected: `1` (PM view leads with plain-language progress).

- [ ] **Step 5: Commit**

```bash
git add plugins/bitacora/skills/session-status/examples/
git commit -m "docs(status): add self/eng/pm rendering example fixtures"
```

---

## Task 3: Add the command and alias files

**Files:**
- Create: `plugins/bitacora/commands/status.md`
- Create: `plugins/bitacora/alias/bit-status.md`

- [ ] **Step 1: Write `commands/status.md`**

```markdown
---
description: Synthesize a Jira ticket's latest [CTX] into an audience-tailored summary (--for-pm/--for-eng/--for-self). Read-only; prints and offers a clipboard copy.
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts. A
`--for-pm`, `--for-eng`, or `--for-self` flag selects the audience mode
(default: self).

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Write `alias/bit-status.md`**

```markdown
---
description: (alias of /bitacora:status) Audience-tailored summary of a ticket's latest [CTX].
---

Use the `bitacora:session-status` skill to run the session status workflow.

Any Jira-style ticket key in the arguments below forces the target ticket;
otherwise resolve it from the current branch or recent checkouts. A
`--for-pm`, `--for-eng`, or `--for-self` flag selects the audience mode
(default: self).

Arguments: $ARGUMENTS
```

- [ ] **Step 3: Verify both delegate to the skill**

Run:
```bash
grep -l "bitacora:session-status" plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md
```
Expected: both file paths listed.

- [ ] **Step 4: Commit**

```bash
git add plugins/bitacora/commands/status.md plugins/bitacora/alias/bit-status.md
git commit -m "feat(status): add /bitacora:status command and /bit:status alias"
```

---

## Task 4: Promote `/status` to Shipped in the help reference

**Files:**
- Modify: `plugins/bitacora/commands/help.md`
- Modify: `plugins/bitacora/alias/bit-help.md`

Both files contain an identical fenced block that must stay in sync. Apply the same two edits to each.

- [ ] **Step 1: In `commands/help.md`, move the `/status` line into Shipped**

Replace the Shipped block ending (the `/bitacora:help` line) so `/status` joins it:

Find:
```
  /bitacora:resume [KEY]        Rehydrate a cleared session from a
                                ticket's latest [CTX] (read-only).
  /bitacora:help                Show this command reference.
```
Replace with:
```
  /bitacora:resume [KEY]        Rehydrate a cleared session from a
                                ticket's latest [CTX] (read-only).
  /bitacora:status [KEY]        Summarize a ticket's latest [CTX] for an
                                audience (--for-pm/--for-eng/--for-self).
  /bitacora:help                Show this command reference.
```

- [ ] **Step 2: In `commands/help.md`, remove `/status` from Planned**

Find:
```
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
  /bitacora:status    Summarize a ticket's current state (PM / eng / self modes).
  /bitacora:spike     Create a timeboxed spike ticket with a mandatory rec.
```
Replace with:
```
  /bitacora:improve   Sharpen a vague or weak ticket your branch is based on.
  /bitacora:spike     Create a timeboxed spike ticket with a mandatory rec.
```

- [ ] **Step 3: In `commands/help.md`, add `/bit:status` to the alias line**

Find:
```
  Alias: /bit:handoff, /bit:resume, /bit:help (opt-in — see plugin README)
```
Replace with:
```
  Alias: /bit:handoff, /bit:resume, /bit:status, /bit:help (opt-in — see plugin README)
```

- [ ] **Step 4: Apply the identical three edits to `alias/bit-help.md`**

The fenced block in `alias/bit-help.md` is byte-identical to the one in `commands/help.md`. Apply Steps 1–3 verbatim to `alias/bit-help.md`.

- [ ] **Step 5: Verify the two files are still in sync and `/status` is Shipped**

Run:
```bash
diff <(sed -n '/^```$/,/^```$/p' plugins/bitacora/commands/help.md) \
     <(sed -n '/^```$/,/^```$/p' plugins/bitacora/alias/bit-help.md) && echo "IN SYNC"
```
Expected: `IN SYNC` (no diff).

Run:
```bash
grep -A6 "Shipped" plugins/bitacora/commands/help.md | grep "bitacora:status"
```
Expected: the `/bitacora:status [KEY]` Shipped line prints.

Run:
```bash
sed -n '/Planned/,/Alias/p' plugins/bitacora/commands/help.md | grep -c "bitacora:status"
```
Expected: `0` (no longer under Planned).

- [ ] **Step 6: Commit**

```bash
git add plugins/bitacora/commands/help.md plugins/bitacora/alias/bit-help.md
git commit -m "docs(status): promote /bitacora:status to Shipped in help reference"
```

---

## Task 5: Update the READMEs

**Files:**
- Modify: `README.md` (root, Commands table)
- Modify: `plugins/bitacora/README.md` (Commands table + alias prose)

- [ ] **Step 1: In root `README.md`, promote the `/status` row to Shipped**

Find:
```
| `/bitacora:status` | 🚧 Planned | Synthesize a ticket's current state into a human-readable summary. Audience modes for PM (`--for-pm`), engineer (`--for-eng`), and self (`--for-self`). |
```
Replace with:
```
| `/bitacora:status` | ✅ **Phase 1** | Synthesize a ticket's latest `[CTX]` into an audience-tailored summary — PM (`--for-pm`), engineer (`--for-eng`), or self (`--for-self`, default). Read-only: prints the summary and offers a clipboard copy. |
```

- [ ] **Step 2: In `plugins/bitacora/README.md`, add a `/status` row after the resume row**

Find:
```
| `/bitacora:resume [KEY]` | Rehydrate a fresh session from a ticket's latest `[CTX]`: read its `Status` / `Decisions` / `Next` back into context after a `/clear` and print a compact, read-only briefing. Pass a key to target a ticket; otherwise resolved from the branch. |
```
Replace with:
```
| `/bitacora:resume [KEY]` | Rehydrate a fresh session from a ticket's latest `[CTX]`: read its `Status` / `Decisions` / `Next` back into context after a `/clear` and print a compact, read-only briefing. Pass a key to target a ticket; otherwise resolved from the branch. |
| `/bitacora:status [KEY] [--for-pm\|--for-eng\|--for-self]` | Synthesize a ticket's latest `[CTX]` into an audience-tailored summary (default `--for-self`): different sections foregrounded and a different voice per mode. Read-only — prints the summary and offers a clipboard copy. |
```

- [ ] **Step 3: In `plugins/bitacora/README.md`, add `/bit:status` to the alias prose**

Find:
```
the snippet — no need to edit it. Then `/bit:handoff`, `/bit:resume`, and `/bit:help`
run the same workflows as their `/bitacora:…` forms.
```
Replace with:
```
the snippet — no need to edit it. Then `/bit:handoff`, `/bit:resume`, `/bit:status`, and
`/bit:help` run the same workflows as their `/bitacora:…` forms.
```

- [ ] **Step 4: Verify both READMEs reflect the new command**

Run:
```bash
grep "bitacora:status" README.md plugins/bitacora/README.md
```
Expected: the root row shows `✅ **Phase 1**`; the plugin row shows the `--for-pm|--for-eng|--for-self` signature.

Run:
```bash
grep -c "🚧 Planned.*bitacora:status\|bitacora:status.*🚧 Planned" README.md
```
Expected: `0` (no Planned marker remains on the status row).

- [ ] **Step 5: Commit**

```bash
git add README.md plugins/bitacora/README.md
git commit -m "docs(status): mark /bitacora:status shipped in both READMEs"
```

---

## Task 6: Final consistency check and acceptance handoff

**Files:** none modified — verification only.

- [ ] **Step 1: Confirm every listing agrees that `/status` is shipped**

Run:
```bash
echo "help.md:";      grep -c "bitacora:status" plugins/bitacora/commands/help.md
echo "bit-help.md:";  grep -c "bitacora:status" plugins/bitacora/alias/bit-help.md
echo "root README:";  grep -c "bitacora:status" README.md
echo "plugin README:"; grep -c "bitacora:status" plugins/bitacora/README.md
echo "command:";      ls plugins/bitacora/commands/status.md
echo "alias:";        ls plugins/bitacora/alias/bit-status.md
echo "skill:";        ls plugins/bitacora/skills/session-status/SKILL.md
```
Expected: each grep ≥ 1; all three `ls` paths exist.

- [ ] **Step 2: Confirm the existing test suite is untouched and still green**

Run:
```bash
bash plugins/bitacora/scripts/test-validate-ctx.sh
```
Expected: all existing tests pass (status reads, never writes `[CTX]`; the validator is unaffected).

- [ ] **Step 3: Manual acceptance against a live ticket** (requires the Atlassian MCP)

On a branch named for a ticket that already has a `[CTX]` (e.g. the guinea-pig ticket), run each mode and confirm the rendering matches the spec's section emphasis/tone:
- `/bitacora:status --for-self` → terse; `Left off` / `Next` lead.
- `/bitacora:status --for-eng` → keeps PR links + rationale; `Done recently` / `Decisions` / `Blockers`.
- `/bitacora:status --for-pm` → plain language, no PR hashes/jargon; `Status` / `Progress` / `Risks` lead.
- Confirm the clipboard offer copies on macOS (`pbcopy`) and the printed summary stands alone if no clipboard tool exists.
- On a ticket with **no** `[CTX]`: confirm the graceful "nothing in `[CTX]` yet" path (shows Jira status + title, suggests `/bitacora:handoff`).
- With the Atlassian MCP disabled: confirm the **hard stop** with a setup pointer.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/bitacora-status
gh pr create --title "feat: add /bitacora:status audience-tailored summary command" --body "Implements docs/superpowers/specs/2026-05-27-bitacora-status-design.md. New session-status skill + status command + /bit:status alias; help and READMEs updated. Read-only, three audience modes (default self), strict [CTX] read with lookback, opt-in clipboard."
```
Do not merge — `main` is branch-protected; leave the PR for review.

---

## Notes for the implementer

- **Prose, not code.** This plugin's "implementation" is authoring Markdown skill/command files. There is no compile step and no unit-test harness for the rendering — it is model-driven. The deterministic checks are frontmatter validity, listing consistency (Task 4/6), and the unchanged `validate-ctx.sh` suite. Real behavioral confidence comes from Task 6 Step 3 (manual acceptance).
- **Mirror the sibling.** When in doubt about phrasing or structure, match `skills/session-resume/SKILL.md`, `commands/resume.md`, and `alias/bit-resume.md` — `/status` is deliberately their sibling.
- **No `Co-Authored-By` trailers** in any commit (project convention).
- **Keep help.md and bit-help.md byte-identical** inside the fenced block — the Task 4 Step 5 `diff` must print `IN SYNC`.
