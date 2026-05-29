#!/usr/bin/env bash
# Asserts sync-statusline.sh honors the opt-in gate, copies *.sh files,
# picks up later-added scripts, updates content, and never deletes dest files.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/sync-statusline.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

plugin="$work/plugin"
mkdir -p "$plugin/statusline"
mkdir -p "$plugin/scripts"
printf 'x\n' > "$plugin/statusline/statusline.sh"
printf 'y\n' > "$plugin/statusline/handoff-pending.sh"
printf 'z\n' > "$plugin/statusline/README.md"   # non *.sh → must be ignored
printf 'hook\n' > "$plugin/scripts/precompact-handoff-check.sh"

fakehome="$work/home"
export HOME="$fakehome"
export CLAUDE_PLUGIN_ROOT="$plugin"
dest="$fakehome/.claude/bitacora"

# 1. Not opted in (dest absent) → no-op; must not create the dir.
bash "$SCRIPT"
[ ! -e "$dest" ] && pass "opt-out: no-op when ~/.claude/bitacora absent" \
                 || bad  "opt-out: created dir/files when not opted in"

# 2. Opted in → copies both scripts; non-.sh ignored.
mkdir -p "$dest"
bash "$SCRIPT"
[ -f "$dest/statusline.sh" ]              && pass "copies statusline.sh"                || bad "missing statusline.sh"
[ -f "$dest/handoff-pending.sh" ]         && pass "copies handoff-pending.sh"           || bad "missing handoff-pending.sh"
[ -f "$dest/precompact-handoff-check.sh" ] && pass "copies precompact-handoff-check.sh" || bad "missing precompact-handoff-check.sh"
[ ! -e "$dest/README.md" ]         && pass "ignores non *.sh files"         || bad "copied a non-.sh file"
[ -x "$dest/statusline.sh" ]       && pass "copy is executable"             || bad "copy is not executable"

# 3. Script added in a later release → synced on next run.
printf 'new\n' > "$plugin/statusline/new-helper.sh"
bash "$SCRIPT"
[ -f "$dest/new-helper.sh" ] && pass "later-added script syncs automatically" || bad "new script not synced"

# 4. Content of an existing script changes → updated.
printf 'updated\n' > "$plugin/statusline/statusline.sh"
bash "$SCRIPT"
[ "$(cat "$dest/statusline.sh")" = "updated" ] && pass "updates changed content" || bad "stale content"

# 5. CLAUDE_PLUGIN_ROOT set but its statusline dir missing → no-op, exit 0.
rm -rf "$plugin/statusline"
if bash "$SCRIPT"; then pass "missing source dir → exits 0 (no-op)"; else bad "nonzero exit on missing source dir"; fi

# 6. Add/update only — a user's own dest file is never deleted.
mkdir -p "$plugin/statusline"; printf 'x\n' > "$plugin/statusline/statusline.sh"
printf 'mine\n' > "$dest/custom.sh"
bash "$SCRIPT"
[ -f "$dest/custom.sh" ] && pass "never deletes existing dest files" || bad "deleted a dest file"

if [ "$fail" -eq 0 ]; then echo "All sync-statusline tests passed."; else echo "Some tests FAILED."; fi
exit "$fail"
