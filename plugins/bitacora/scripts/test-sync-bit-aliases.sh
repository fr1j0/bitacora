#!/usr/bin/env bash
# Asserts sync-bit-aliases.sh honors the opt-in gate, strips the bit- prefix,
# picks up later-added aliases, updates content, and never deletes dest files.
set -uo pipefail  # no -e: we assert on behavior, not on the script's exit alone
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/sync-bit-aliases.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# Fully isolated environment: fake HOME + fake plugin root, never the real ones.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

plugin="$work/plugin"
mkdir -p "$plugin/alias"
printf 'x\n' > "$plugin/alias/bit-handoff.md"
printf 'y\n' > "$plugin/alias/bit-status.md"
printf 'z\n' > "$plugin/alias/README.md"   # non bit-*.md → must be ignored

fakehome="$work/home"
export HOME="$fakehome"
export CLAUDE_PLUGIN_ROOT="$plugin"
dest="$fakehome/.claude/commands/bit"

# 1. Not opted in (dest absent) → no-op; must not create the dir.
bash "$SCRIPT"
[ ! -e "$dest" ] && pass "opt-out: no-op when ~/.claude/commands/bit absent" \
                 || bad  "opt-out: created dir/files when not opted in"

# 2. Opted in → copies aliases, bit- prefix stripped, non-bit ignored.
mkdir -p "$dest"
bash "$SCRIPT"
[ -f "$dest/handoff.md" ]   && pass "copies bit-handoff.md → handoff.md" || bad "missing handoff.md"
[ -f "$dest/status.md" ]    && pass "copies bit-status.md → status.md"   || bad "missing status.md"
[ ! -e "$dest/README.md" ]  && pass "ignores non bit-*.md files"         || bad "copied a non bit- file"
[ ! -e "$dest/bit-handoff.md" ] && pass "strips bit- prefix"             || bad "did not strip prefix"

# 3. Alias added in a later release → synced on next run (the reported bug).
printf 'r\n' > "$plugin/alias/bit-resume.md"
bash "$SCRIPT"
[ -f "$dest/resume.md" ] && pass "later-added alias syncs automatically" || bad "new alias not synced"

# 4. Content of an existing alias changes → updated.
printf 'updated\n' > "$plugin/alias/bit-status.md"
bash "$SCRIPT"
[ "$(cat "$dest/status.md")" = "updated" ] && pass "updates changed alias content" || bad "stale content"

# 5. CLAUDE_PLUGIN_ROOT set but its alias dir missing → no-op, exit 0.
rm -rf "$plugin/alias"
if bash "$SCRIPT"; then pass "missing alias dir → exits 0 (no-op)"; else bad "nonzero exit on missing alias dir"; fi

# 6. Add/update only — a user's own dest file is never deleted.
mkdir -p "$plugin/alias"; printf 'x\n' > "$plugin/alias/bit-handoff.md"
printf 'mine\n' > "$dest/custom.md"
bash "$SCRIPT"
[ -f "$dest/custom.md" ] && pass "never deletes existing dest files" || bad "deleted a dest file"

if [ "$fail" -eq 0 ]; then echo "All sync-bit-aliases tests passed."; else echo "Some tests FAILED."; fi
exit "$fail"
