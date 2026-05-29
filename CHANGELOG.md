# Changelog

All notable changes to Bitácora are recorded here. The plugin follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html); while in alpha (`0.x.y`), expect the API to keep settling.

## [v0.2.1] — 2026-05-29 · Alpha-ready

The first cut intended for an internal alpha audience. Validated end-to-end on a clean Claude Code profile.

### Behavior

- `/improve` no longer runs a pre-flight clarifying-questions round. It now produces a confident, opinionated rewrite in one pass and surfaces non-obvious choices as a new **Assumptions** section. Accept-or-cancel is the only user gate. ([#61](https://github.com/fr1j0/bitacora/pull/61))
- `[ARCHIVE]` snapshot header no longer carries a hand-typed timestamp — the Jira `created` metadata is authoritative, matching the rule the `[CTX]` format already enforced. ([#62](https://github.com/fr1j0/bitacora/pull/62))
- Identifier-backtick rule in the `[CTX]` format now explicitly names slash commands (`/bitacora:improve`), so command mentions render as inline `code` instead of bare prose. ([#63](https://github.com/fr1j0/bitacora/pull/63))

### Fixes

- **Handoff guardrail hook resolves correctly on installed plugins.** `precompact-handoff-check.sh` was sourcing `$DIR/handoff-pending.sh`, but the helper lives in `plugins/bitacora/statusline/`. The guard had been silently failing-open on every prompt since `v0.2.0`. The test stager was also corrected to mirror the production two-dir layout so future path drift fails CI rather than being masked. ([#60](https://github.com/fr1j0/bitacora/pull/60))
- Guardrail hook now prints `bitacora: jq not on PATH; handoff guardrail disabled` to stderr when `jq` is unavailable, instead of disabling silently. Fail-open behavior unchanged. ([#65](https://github.com/fr1j0/bitacora/pull/65))

### Docs

- **Installation section rewritten** with the verified direct-from-repo install path (`/plugin marketplace add fr1j0/bitacora` → `/plugin install bitacora@bitacora` → `/reload-plugins` → `/bitacora:help` to verify). Each step in its own code fence to prevent the paste-both-and-submit failure. ([#65](https://github.com/fr1j0/bitacora/pull/65), [#66](https://github.com/fr1j0/bitacora/pull/66))
- Auth-restart troubleshooting note added for the Claude Code quirk where in-session `/login` doesn't refresh the running process's auth state. ([#67](https://github.com/fr1j0/bitacora/pull/67))
- StatusLine and guardrail-hook opt-in instructions now use `jq`-in-place merges rather than heredoc clobbering — fixes a real risk where a colleague following the instructions verbatim could silently destroy their plugin install. ([#68](https://github.com/fr1j0/bitacora/pull/68))
- New top-level [`USAGE.md`](USAGE.md) with banking-domain conventions: `/improve` on formally controlled requirement tickets, `/status` as recall not source of truth, the load-bearing `Decisions:` line. ([#65](https://github.com/fr1j0/bitacora/pull/65))
- Project-key-pattern caveat added — the guardrail hook hardcodes the default uppercase pattern (`[A-Z][A-Z0-9]+-[0-9]+`) and does not yet read `.bitacora.yml` overrides. Tracked for a future enhancement. ([#65](https://github.com/fr1j0/bitacora/pull/65))
- Both READMEs' "Phase 1 shipped" intro lists now include every command. ([#69](https://github.com/fr1j0/bitacora/pull/69))

### Known limitations

- `/plugin install bitacora@bitacora` always installs from `main`. Pinning to a specific revision currently requires a fork. Versioned-tag install is on the roadmap once Claude Code's marketplace supports it.
- Atlassian Rovo MCP auth is account-scoped (lives outside `~/.claude/`). Revoking access in `claude.ai → Settings` affects every session for that account, not the testing profile alone.
- See [USAGE.md](USAGE.md) for banking-domain conventions that aren't enforced by the plugin.

## [v0.2.0] — 2026-05-28

Initial public alpha. Phase 1 command surface — `/bitacora:handoff`, `/bitacora:resume`, `/bitacora:status`, `/bitacora:next`, `/bitacora:improve`, `/bitacora:help` — plus the opt-in statusLine context meter, the `/clear` handoff guardrail hook, and the `[CTX]` Jira-comment-format discipline.

[v0.2.1]: https://github.com/fr1j0/bitacora/releases/tag/v0.2.1
[v0.2.0]: https://github.com/fr1j0/bitacora/releases/tag/v0.2.0
