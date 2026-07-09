# Contributing to Bitácora

Thanks for your interest! Bitácora is in **beta** and we're keeping the contribution flow
deliberately simple: **every change starts as an issue.**

## The flow

1. **Open an issue.** Pick a template:
   - [Bug report](https://github.com/fr1j0/bitacora/issues/new?template=bug_report.yml)
   - [Feature request](https://github.com/fr1j0/bitacora/issues/new?template=feature_request.yml)
   - [Question](https://github.com/fr1j0/bitacora/issues/new?template=question.yml)
2. **Wait for triage.** A maintainer will review and either close it, ask for more
   info (`needs-info` label), or approve it (`ready-for-dev` label).
3. **Branch and code.** Once your issue has `ready-for-dev`, create a topic branch
   named `<type>/issue-<N>-<slug>` (e.g. `feat/issue-42-context-meter`,
   `fix/issue-17-empty-ctx`) **off `main`**. Never push to `main` directly.
4. **Open a PR.** Include `Closes #<N>` in the PR body. An automated check verifies
   the linked issue is `ready-for-dev`; if not, the check fails and the PR can't merge.

## Why issue-first?

Bitácora has a [tight scope](README.md#what-lives-where--status-vs-scratch) — it tracks
status and continuity on Jira tickets, and *not* ticket-authoring, spike-running, or
other workflows that have been considered and parked. Triaging first saves you from
writing code that won't be accepted; see [docs/TRIAGE.md](docs/TRIAGE.md) for the
maintainer-side scope guardrails.

## Maintainer exceptions

Maintainers can apply `skip-issue-check` to a PR for typo-only, CI-only, or docs-only
fixes. Everything else needs an approved issue.

## Branching rules

- Branch off `main`. Never push to `main` directly (it's branch-protected).
- Branch name: `<type>/issue-<N>-<slug>`. `<type>` is one of `feat`, `fix`, `chore`,
  `docs`, `refactor`, `test`.
- Squash-merge is the default. Keep commits descriptive but don't over-engineer the
  history — squash collapses it.

## Local checks

CI runs ShellCheck (`--severity=warning`) and five shell-test suites on every PR. To
match it locally before pushing:

```bash
# One-time: install ShellCheck
brew install shellcheck         # macOS
# apt install shellcheck        # Debian/Ubuntu

# Lint
shellcheck --severity=warning plugins/bitacora/scripts/*.sh plugins/bitacora/statusline/*.sh

# Tests (each script self-reports PASS/FAIL)
for t in plugins/bitacora/scripts/test-*.sh; do bash "$t" || break; done
```

## Code of Conduct

Be kind. Assume good faith. If something feels off, open an issue or reach out to a
maintainer.

## License

By contributing, you agree your work is licensed under the [MIT License](LICENSE).
