# Privacy Policy

**Bitácora collects nothing.**

Bitácora is a local Claude Code plugin — a set of commands, skills, and shell scripts that
run on your own machine. It has no backend, no servers, no analytics, and no telemetry. It
does not phone home, and the maintainers receive no data about you or your usage.

## What data Bitácora touches, and where it stays

- **Jira tickets.** Bitácora reads and writes `[CTX]` status comments on *your* Jira tickets,
  through *your* Atlassian Rovo MCP connection using *your* credentials. That data lives in
  your Atlassian instance and is governed by **Atlassian's** privacy policy and your
  organization's Jira configuration — Bitácora is not a party to it and stores none of it.
  Every Jira write is shown to you and confirmed before it happens.
- **Local session scratch.** Optional handoff notes are delegated to a local memory tool
  (Remember / claude-mem / a memory MCP) and written to files on your machine. Bitácora does
  not transmit them anywhere.
- **Git metadata.** Bitácora reads local `git` state (current branch, recent checkouts) to
  resolve which ticket you're working on. This is read locally and never sent anywhere.
- **Clipboard.** When you ask it to copy a summary, the text goes to your system clipboard
  via your OS clipboard utility. Nothing else.

## What Bitácora does NOT do

- No telemetry, analytics, or usage tracking.
- No data sent to the maintainers or any third party operated by Bitácora.
- No auto-update — nothing on your machine changes unless you explicitly reinstall.
- No accounts, no identifiers, no profiling.

## Third parties

Bitácora composes with tools you configure and control — the Atlassian Rovo MCP (Jira), your
local memory tool, and Claude Code itself. Your use of those tools is governed by *their*
respective privacy policies, not this one.

## Contact

Bitácora is open source (MIT). Questions or concerns:
[github.com/fr1j0/bitacora/issues](https://github.com/fr1j0/bitacora/issues).
