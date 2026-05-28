# Security Policy

## Reporting a vulnerability

Please report security issues **privately**. Do not open a public issue.

**Preferred channel:** [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) — on this repo's **Security** tab, click **Report a vulnerability**. This opens a private draft advisory only the maintainer can see.

**Fallback:** if private reporting isn't available, email the address listed on the [maintainer's GitHub profile](https://github.com/fr1j0) with the subject line `bitacora: security`.

When reporting, include:

- the affected file(s) and a brief reproducer (a minimal handoff body, fixture, or workflow snippet is enough);
- the impact you observed (e.g. validator bypass, agent-instruction injection, workflow privilege escalation);
- any suggested fix, if you have one.

## What we mean by "in scope"

The security surface of this repo is small and specific. The following classes count:

- **Shell scripts under `plugins/bitacora/scripts/`** — validators (`validate-ctx.sh`), the statusline scripts, and any helper that ships with the plugin. Bugs that let a malformed comment slip past the validator, or that allow command injection from a comment body, qualify.
- **Skill `SKILL.md` files** — these are agent-executed instructions. A change that would let a Jira comment's content (read by the agent) hijack agent behavior — classic prompt injection / instruction poisoning — qualifies.
- **GitHub Actions workflows** under `.github/workflows/` — anything enabling workflow-injection, untrusted code execution in the target token's context, or unintended privilege escalation across the issue-gate and label automations.

## What we mean by "out of scope"

- The user's own Atlassian / Jira instance, Confluence, or other Atlassian-side configuration.
- Third-party MCP servers the user installs (Atlassian Rovo, Google Drive, etc.) — report those to their respective maintainers.
- Downstream Claude Code installations, the `~/.claude/` configuration, or harness behavior outside this repo's source.
- Anything that requires a maintainer-level GitHub token to exploit.

## Supported versions

Only the latest commit on `main` is supported. There are no LTS branches; security fixes ship forward, not backward.
