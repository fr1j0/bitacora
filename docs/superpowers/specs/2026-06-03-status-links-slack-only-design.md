# Design — Ticket-Key Links Become `--copy-as-slack`-Only

**Date:** 2026-06-03
**Status:** Approved design, ready for implementation planning
**Issue:** #90 · **Supersedes the linking decision in** `2026-06-02-status-ticket-key-links-design.md` (shipped in v0.4.0 via #88)
**Ships as:** v0.4.1
**Scope:** Move ticket-key linking in the multi-ticket / aggregate `/status` renders from *every printed render* to the **`--copy-as-slack` path only**. Printed output reverts to bare keys.

## Summary

v0.4.0 (#88) renders each per-ticket index key as an inline markdown link `[KEY](…/browse/KEY)`
in all printed renders. In a dense digest that adds visual noise to the terminal glance, and the
raw `[KEY](url)` is cluttered anywhere markdown doesn't render. The click-through value is highest
when **sharing** (Slack / paste), not in the ephemeral terminal preview. This refinement keeps the
printed render terse (bare keys) and renders links **only** in the `--copy-as-slack` output.

## Key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Printed renders: bare keys** (all lenses, digest/`--blocked`/`--standup`/epic) | Reverts v0.4.0's inline links. The terse glance stays scannable; a key per line × many lines is noise. |
| D2 | **`--copy-as-slack`: index keys → `<https://<site>/browse/KEY|KEY>`** | The share path is where click-through pays off. The Slack-link rule already exists in the *Slack mrkdwn rendering* subsection; it becomes the **sole** place links appear. |
| D3 | **Index-only still applies within Slack** | Only the per-ticket index entries (`By ticket:`/`By child:`/`--blocked`/`--standup` `Moved:`) link; inline (`Health`/`Top risks`/`Dependencies`) + tails stay bare — same boundary as before, now Slack-scoped. |
| D4 | **Single-ticket `--for-*` URL lines unchanged** | One header URL line is not noise and was never in scope. |
| D5 | **Add a Slack-render fixture for automated coverage** | `examples/multi-aggregate-slack.txt` captures the `--copy-as-slack` digest; the contract test asserts the `<url|KEY>` form there. The 5 default fixtures revert to bare, and the test's printed-link assertions are dropped. |

## Changes

- **`skills/session-status/SKILL.md`**
  - Invert the §7 **Ticket-key links** rule: index entries print **bare** keys; under
    `--copy-as-slack`, render the leading key as `<https://<site>/browse/KEY|KEY>`.
  - Revert the four render templates (`--blocked`, `--standup` `Moved:`, §5 Aggregate render
    exec/eng `By child:`) to the bare `- <KEY> "<title>" — …` form.
  - Revert the §5 Aggregate-render pointer to drop the printed-link instruction (keep a note
    that Slack linking is per §7).
  - Keep / sharpen the Slack subsection bullet (it now carries the whole linking behavior).
- **Fixtures**
  - Revert `multi-aggregate.txt`, `multi-blocked.txt`, `multi-standup.txt`, `epic-exec.txt`,
    `epic-eng.txt` index entries to **bare** keys.
  - **Add** `examples/multi-aggregate-slack.txt` — the `--copy-as-slack` digest over the
    4-ticket scenario, Slack `mrkdwn`: `*bold*`, `•` bullets, and `<https://example.atlassian.net/browse/KEY|KEY>`
    index links; inline/tail keys bare.
- **`scripts/test-multi-status-fixtures.sh`**
  - Remove the `check_linked` printed-link assertions (§8) and the multi-`*` epic link checks.
  - Restore/confirm the original bare state holds for the default fixtures (the existing
    coverage / key-universe / per-lens checks already cover them).
  - Add a Slack-form assertion against `multi-aggregate-slack.txt`: each reporting key appears as
    `<…/browse/KEY|KEY>` (grep `/browse/KEY|KEY>`); and confirm the inline/tail keys (`PERF-9`)
    are **not** Slack-linked.
- **Docs**
  - CHANGELOG: add a **v0.4.1** entry — "ticket-key links are now `--copy-as-slack`-only; printed
    renders show bare keys (refines v0.4.0)."
  - `README.md` "Today" line + `plugins/bitacora/README.md`: reword "keys rendered as links" →
    "keys become links when copied for Slack."
  - `MANUAL-ACCEPTANCE.md` M9: reword to "printed render shows bare keys; `--copy-as-slack`
    output uses `<url|KEY>`."
- **Version:** bump `marketplace.json` + `plugin.json` `0.4.0 → 0.4.1`.

## Testing

- The fixture-contract test keeps deterministic coverage: default fixtures bare (existing
  assertions), Slack fixture asserts the `<url|KEY>` form (new). The printed-vs-Slack split is
  the regression lock.
- M9 manual: confirm a printed digest shows bare keys and `--copy-as-slack` produces `<url|KEY>`.

## Out of scope

- Single-ticket header linking (D4) — unchanged.
- Any printed-render linking (D1) — explicitly removed.
- Linking inline / tail keys, even in Slack (D3).
