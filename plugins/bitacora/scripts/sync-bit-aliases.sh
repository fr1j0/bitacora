#!/usr/bin/env bash
# sync-bit-aliases.sh — keep the opt-in /bit: command aliases in sync.
#
# Copies the plugin's bundled alias templates (alias/bit-*.md) into the user's
# personal commands dir (~/.claude/commands/bit/), stripping the `bit-` prefix
# so bit-status.md becomes the /bit:status command. Run from the plugin's
# SessionStart hook, this means aliases added in a later release sync
# automatically — no manual re-run of the README snippet.
#
# OPT-IN: does nothing unless ~/.claude/commands/bit/ already exists. The user
# opts in once by creating that dir (see the plugin README); until then this is
# a no-op and the /bit: namespace stays untouched.
#
# Add/update only: never deletes files in the dest dir. Always exits 0 so a
# SessionStart hook can never break a session.
#
# Source resolution:
#   $CLAUDE_PLUGIN_ROOT/alias        when set (the hook path) — trusted absolutely
#   ../alias next to this script     otherwise (manual run outside a hook)

dest="${HOME}/.claude/commands/bit"

# Opt-in gate: absent dir = not opted in = nothing to do.
[ -d "$dest" ] || exit 0

# Locate the bundled alias sources.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  src="${CLAUDE_PLUGIN_ROOT}/alias"
else
  src="$(cd "$(dirname "$0")/../alias" 2>/dev/null && pwd || true)"
fi
[ -n "${src:-}" ] && [ -d "$src" ] || exit 0

for f in "$src"/bit-*.md; do
  [ -e "$f" ] || continue          # literal glob when there are no matches
  name="$(basename "$f")"
  cp -- "$f" "$dest/${name#bit-}" 2>/dev/null || true
done

exit 0
