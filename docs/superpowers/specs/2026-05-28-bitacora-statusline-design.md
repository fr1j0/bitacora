# Bitácora statusLine — combined design (handoff-pending + context meter)

A multi-segment Claude Code `statusLine` the user opts into, that shows three things on one
line: the current ticket/branch, the context-window fill, and whether ticket work is
un-handed-off. At ≥85% context, the meter — and the handoff segment when present — bold +
red, signaling the moment to run `/bitacora:handoff` then `/clear` + `/bitacora:resume`.

**Realizes and supersedes**
`docs/superpowers/specs/2026-05-27-statusline-handoff-indicator-design.md` (the
handoff-pending indicator), which was deferred pending the existence of a Phase 6 statusLine
script. This spec builds that statusLine and integrates *both* signals — handoff hygiene
and context heaviness — into a single shipping unit. Decisions from the older spec
(detection logic, marker file, pure-function structure, configuration knob) are adopted as
written and extended.

## Problem

Two distinct mistakes happen near the end of a productive session:

- **Clearing without handing off** — the user runs `/clear` before `/bitacora:handoff`, so
  the curated Jira `[CTX]` and local Remember scratch are never written; the next session
  starts from the raw transcript.
- **Overrunning the context window** — the user works past the point where the model is
  thrashing on context, when the right move was `/clear` and `/bitacora:resume` a few turns
  earlier.

There is no always-visible cue for either. The README has long promised "a context-window
meter that tells you when to clear and resume cleanly"; the deferred handoff-pending spec
designed the other half. Neither shipped because no statusLine script existed to host them.

## Goal

A single Bitácora-provided `statusLine` script the user wires into their Claude Code
`settings.json`, which on every render prints:

```
AT-4104  ·  ctx ██████░░ 76%  ·  ✎ handoff pending
```

with visual escalation at ≥85% context, so the two mistakes above become visible at the
exact moment they matter.

## Prerequisites

- Claude Code's `statusLine` mechanism — the script receives a JSON payload on stdin
  including `context_window.used_percentage` (precomputed 0–100).
- `bash`, `jq`, `git` available on `$PATH` (already required by other plugin scripts).

## Non-goals (YAGNI)

- **No auto-installation** of the `statusLine` setting. The user adds the snippet to their
  own `settings.json` once (we document it). Touching the user's settings without consent is
  out of scope; the auto-sync hook from PR #27 is for `bit-*.md` alias copies only.
- **No composable mode** in v1. Claude Code permits exactly one `statusLine.command`, so
  ours replaces whatever the user had. Users with custom statusLines can wrap our script;
  formal composability is a post-v1 concern.
- **No `--why` / `--debug` flags** in v1. The statusLine renders one line; introspection of
  why a segment is present belongs elsewhere.
- **No second context threshold** (e.g., a yellow band at 60%). One threshold @ 85% keeps
  the urgency moment singular.
- **No network calls.** The statusLine renders on every assistant message; remote calls
  would lag the terminal. All detection is local (stdin JSON + git + a marker file).

## Design

### File structure

| File | Status | Responsibility |
|------|--------|----------------|
| `plugins/bitacora/statusline/statusline.sh` | New | Reads stdin JSON, orchestrates the three segments, prints one line |
| `plugins/bitacora/statusline/handoff-pending.sh` | New | Sourceable pure function `handoff_pending(is_ticket_branch, tree_dirty, last_commit_ts, marker_ts) → bool` |
| `plugins/bitacora/scripts/sync-statusline.sh` | New | Opt-in SessionStart sync: copy `statusline/*.sh` into `~/.claude/bitacora/` if that dir exists (mirrors the `sync-bit-aliases.sh` pattern: opt-in gate, additive only, always exits 0) |
| `plugins/bitacora/scripts/test-statusline.sh` | New | Tests the pure function matrix + full-script renders against JSON fixtures |
| `plugins/bitacora/scripts/test-sync-statusline.sh` | New | Tests the opt-in gate, prefix-less copy, additive-only behavior, missing-source no-op — mirrors `test-sync-bit-aliases.sh` |
| `plugins/bitacora/hooks/hooks.json` | Modify | Add a second SessionStart hook command invoking `sync-statusline.sh` alongside `sync-bit-aliases.sh` |
| `plugins/bitacora/skills/session-handoff/SKILL.md` | Modify | On successful completion, write epoch seconds to `.bitacora/last-handoff` (creating the dir) |
| `.gitignore` | Modify | Add `.bitacora/` (the marker dir is per-project, not committed) |
| `.github/workflows/test.yml` | Modify | Add the two new test steps (`test-statusline.sh` + `test-sync-statusline.sh`) alongside the existing checks |
| `plugins/bitacora/README.md` | Modify | Add the opt-in snippet + the "replaces existing statusLine" caveat |

### Rendering

Each render produces a single line of UTF-8 text, ANSI-styled when allowed. Segments are
joined by `  ·  ` (two spaces, middot, two spaces). Absent segments contribute no separator.

#### Segment 1 — branch / ticket

- `git symbolic-ref --short HEAD` (timeout 1s) is the branch name.
- If the branch matches `project_key_pattern` (reused from `jira-comment-format`), render
  the **ticket key** (the matched substring, e.g. `AT-4104`).
- Else render the **branch name** verbatim (e.g. `feat/bitacora-statusline`).
- Detached HEAD / no branch / git error → segment absent.

#### Segment 2 — context meter

- `jq -r '.context_window.used_percentage // 0'` from stdin; round to nearest integer.
- Render `ctx <bar> <pct>%` with an 8-cell bar using `█` (filled) and `░` (empty).
  Cell math (round-nearest, never overflows): `filled = min(8, round(pct * 8 / 100))`,
  `empty  = 8 - filled`. Render the raw integer `pct`.
  Worked examples: 50% → `████░░░░ 50%` (4 filled); 76% → `██████░░ 76%` (round(6.08)=6);
  87% → `███████░ 87%` (round(6.96)=7); 100% → `████████ 100%` (clamped).
- **At `pct ≥ context_escalation_threshold` (default 85):** the segment renders in
  **bold + red**.
- If stdin is missing / malformed / `used_percentage` absent, render `ctx ?` (no bar, no
  color); never error out.

#### Segment 3 — handoff pending

- Reuses the pure decision from the existing handoff-pending spec:
  `handoff_pending = is_ticket_branch AND (tree_dirty OR last_commit_ts > marker_ts)`.
- Inputs:
  - `is_ticket_branch` — Segment 1 produced a ticket key.
  - `tree_dirty` — `git status --porcelain` (timeout 1s) is non-empty.
  - `last_commit_ts` — `git log -1 --format=%ct` (0 if no commits).
  - `marker_ts` — integer contents of `.bitacora/last-handoff` (0 if file absent).
- When true, render `✎ handoff pending`. Otherwise absent.
- **When the meter is also escalated** (`pct ≥ threshold`), this segment renders in
  **bold + red** as well — the "clear is due, but handoff first" moment.

#### Color handling

- All ANSI styling honors the **`NO_COLOR` convention** (https://no-color.org/): if the
  `NO_COLOR` environment variable is set to any value, color is suppressed. In its place, a
  `⚠ ` prefix is added to the meter (and handoff segment) at and above the threshold —
  preserving the urgency signal without color.
- TTY detection is unnecessary: Claude Code renders the output itself; it handles ANSI
  passthrough.

### Detection logic — git safety

Every git invocation is wrapped in `timeout 1s` so a slow / hung git can never block the
statusLine. Any non-zero exit, timeout, or empty output causes the affected segment to be
absent rather than render an error — fail-safe by design.

### Modify `session-handoff`

Append a short step at the end of the skill's "Report" phase: on successful completion
(after Jira writes + Remember save), write the current epoch seconds to
`.bitacora/last-handoff`, creating `.bitacora/` if it does not exist. Apply this to
**successful local-only handoffs as well** — resetting the clock is harmless when no
tickets were touched and keeps the indicator from going stale forever on Jira-less work.

The marker file is per-project and gitignored; it represents *"work up to this point has
been handed off."*

### Opt-in (user wires it once; stays in sync afterward)

The user's `settings.json` cannot reliably reference `${CLAUDE_PLUGIN_ROOT}` — that
variable is only documented for plugin-defined hook commands. Hard-coding the cache path
(`~/.claude/plugins/cache/bitacora/bitacora/<version>/…`) would break every plugin
upgrade.

Solution: a **stable user-side path** maintained by the existing SessionStart auto-sync
hook (shipped in PR #27 for `/bit:` aliases). The hook is extended to also opt-in-sync
the statusline scripts:

- **Stable path:** `~/.claude/bitacora/statusline.sh` (and its sourceable peer
  `~/.claude/bitacora/handoff-pending.sh`).
- **Opt-in marker:** the directory `~/.claude/bitacora/` existing — same pattern as
  `~/.claude/commands/bit/` for aliases. No directory → hook is a no-op.
- **Sync behavior** (each SessionStart): if `~/.claude/bitacora/` exists, copy
  `${CLAUDE_PLUGIN_ROOT}/statusline/*.sh` into it (additive; never deletes user files).

User one-time setup (documented in the plugin README under *Optional*, alongside the
`/bit:` alias snippet):

```bash
mkdir -p ~/.claude/bitacora
alias_file="$(find ~/.claude/plugins -path '*bitacora/statusline/statusline.sh' | head -1)"
if [ -z "$alias_file" ]; then
  echo "bitacora statusline not found — is the plugin installed?" >&2
else
  cp "$(dirname "$alias_file")"/*.sh ~/.claude/bitacora/
fi
```

Then in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/bitacora/statusline.sh"
  }
}
```

(Claude Code does expand `$HOME` and `~` in `statusLine.command` per its shell-out
semantics; the absolute path resolves identically on every run.)

**Caveat:** Claude Code permits exactly one `statusLine.command` — installing this
**replaces** any existing statusLine. Users with their own statusLine can wrap ours
(`bitacora/statusline.sh && printf " · %s" "$(custom segments)"`) but that is unsupported
in v1.

### Configuration

Reuses `project_key_pattern` from `jira-comment-format`. Adds:

```yaml
statusline:
  show_branch:                true   # render the branch/ticket segment
  show_context_meter:         true   # render the ctx meter
  show_handoff_indicator:     true   # render ✎ handoff pending
  context_escalation_threshold: 85   # %: meter (and handoff) bold+red at/above this
```

Lookup order matches the rest of the plugin: `./.bitacora.yml` then `~/.claude/bitacora.yml`.
Absence is normal — defaults above apply silently.

### Error / edge behavior

| Situation | Behavior |
|---|---|
| Not a git repo / detached HEAD / no branch | Branch + handoff segments absent; meter renders if JSON is valid |
| No marker file (`.bitacora/last-handoff` absent) | `marker_ts = 0` → any commit / dirty tree on a ticket branch shows the indicator (correct: never handed off) |
| Branch switching mid-session | Time-based marker handles it — a commit after the marker on *any* ticket branch counts |
| Ticket branch, clean tree, no commit since handoff | Indicator absent |
| `git` slow / unavailable | Wrapped in `timeout 1s`; on failure the affected segment is silently absent — statusLine never hangs or shows errors |
| Stdin missing / not JSON / `used_percentage` absent | Meter renders `ctx ?`; other segments unaffected |
| `NO_COLOR` set | All color suppressed; `⚠ ` prefix substitutes at the threshold |

### Testing

Two new test scripts, both wired into CI alongside `validate-ctx` and `sync-bit-aliases`.

**`scripts/test-statusline.sh`** covers:

1. **Pure function matrix** for `handoff_pending` (matches the older spec's table):
   ticket-branch + dirty → on; ticket-branch + commit > marker → on; ticket-branch + clean →
   off; non-ticket-branch → off; no marker + work → on; not-a-repo → off (I/O level).
2. **Meter rendering** against fixture JSON inputs at boundary values: 0%, 12%, 50%, 84%,
   85%, 99%, 100%; missing `context_window`; malformed JSON; `used_percentage = null`.
3. **Composition**: with-handoff and without-handoff renders at low vs ≥85% context,
   confirming the escalation flips both signals.
4. **`NO_COLOR`**: re-run a subset of (2)+(3) with `NO_COLOR=1` and assert no ANSI
   sequences appear, with the `⚠ ` prefix replacing color at the threshold.

**`scripts/test-sync-statusline.sh`** mirrors `test-sync-bit-aliases.sh`:

1. **Opt-out gate:** no `~/.claude/bitacora/` → script is a no-op; does not create the dir.
2. **Opt-in:** with the dir present, `statusline.sh` and `handoff-pending.sh` are copied in.
3. **Later-added file:** a new `*.sh` added to the plugin source on a subsequent run is
   picked up (the real-world bug that motivated the original sync hook).
4. **Content update:** an edited source file's content reaches the dest.
5. **Add/update only:** a user-created file in the dest is never deleted.
6. **Missing source dir:** script exits 0 silently.

**Live acceptance:** install via `settings.json`, observe the statusLine across a real
session — meter ticks per assistant message, escalates past 85%, handoff icon clears after
running `/bitacora:handoff`.

## Decisions (locked from the brainstorm)

- **Single takeover script** (not composable snippets in v1) — Claude Code only allows one
  `statusLine.command` anyway, and a takeover model is the simplest contract.
- **Read `context_window.used_percentage` directly from stdin JSON** — Claude Code
  precomputes it; no transcript parsing, no token estimation.
- **One escalation threshold (85%)** for both signals — single urgency moment, matches the
  older handoff-pending spec's number.
- **`NO_COLOR` respected via `⚠ ` prefix at the threshold** — accessible by default.
- **8-cell bar (`█`/`░`)** for the meter — readable + compact, fits in any reasonable
  terminal width.
- **Pure-function decision** for handoff-pending in its own sourceable file — isolates the
  logic for unit-testability, matching the `validate-ctx.sh` pattern.
- **Marker write lives inside `/bitacora:handoff`** (a small modification to the shipped
  skill) rather than in a wrapper — the marker semantically *is* "handoff completed," so it
  belongs at the source.
- **No auto-installation of the `statusLine` setting** — the user opts in by editing their
  `settings.json` themselves; we document the snippet.
- **Opt-in script sync via the existing SessionStart hook** (a new sibling script,
  `sync-statusline.sh`, alongside `sync-bit-aliases.sh`) — gives the user a stable path
  (`~/.claude/bitacora/statusline.sh`) immune to plugin-cache version churn, mirroring the
  pattern already proven for `/bit:` aliases. Two scripts instead of one merged script keeps
  each sync narrowly scoped and independently testable.
