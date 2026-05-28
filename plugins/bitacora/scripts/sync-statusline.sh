#!/usr/bin/env bash
# sync-statusline.sh — keep the opt-in Bitácora statusLine scripts in sync.
#
# Copies the plugin's bundled statusline/*.sh into the user's stable location
# ~/.claude/bitacora/, so the user's settings.json can reference a fixed path
# immune to plugin-cache version churn. Run from the plugin's SessionStart
# hook, this means script updates sync automatically — no manual re-run of
# the README snippet.
#
# OPT-IN: does nothing unless ~/.claude/bitacora/ already exists. The user
# opts in once by creating that dir + adding the statusLine snippet to
# settings.json (see the plugin README); until then this is a no-op.
#
# Add/update only: never deletes files in the dest dir. Always exits 0 so a
# SessionStart hook can never break a session.
#
# Source resolution:
#   $CLAUDE_PLUGIN_ROOT/statusline    when set (the hook path) — trusted absolutely
#   ../statusline next to this script otherwise (manual run outside a hook)

dest="${HOME}/.claude/bitacora"

# Opt-in gate: absent dir = not opted in = nothing to do.
[ -d "$dest" ] || exit 0

# Locate the bundled statusline scripts.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  src="${CLAUDE_PLUGIN_ROOT}/statusline"
else
  src="$(cd "$(dirname "$0")/../statusline" 2>/dev/null && pwd || true)"
fi
[ -n "${src:-}" ] && [ -d "$src" ] || exit 0

for f in "$src"/*.sh; do
  [ -e "$f" ] || continue            # literal glob when there are no matches
  name="$(basename "$f")"
  cp -- "$f" "$dest/$name" 2>/dev/null || true
  chmod +x "$dest/$name" 2>/dev/null || true
done

exit 0
