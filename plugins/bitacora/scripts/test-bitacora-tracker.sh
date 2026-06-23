#!/usr/bin/env bash
# Tests for bitacora-tracker.sh github dispatch + JSON normalization, using a
# PATH-shimmed fake `gh` so nothing hits the network or real auth. Real `jq`
# runs, so comment normalization is exercised for real.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BT="$DIR/bitacora-tracker.sh"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Fake gh: appends argv to $GH_ARGS, emits canned output per subcommand.
cat > "$TMP/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_ARGS"
case "$1 $2" in
  "issue list")    echo '[{"number":7,"title":"x","labels":[],"updatedAt":"2026-06-23T00:00:00Z","milestone":null}]' ;;
  "issue view")
    if [[ "$*" == *"--json comments"* ]]; then
      echo '{"comments":[{"author":{"login":"fr1j0"},"createdAt":"2026-06-23T00:00:00Z","body":"[CTX] Status update"}]}'
    else
      echo '{"number":7,"title":"x","body":"b","labels":[],"state":"OPEN","milestone":null,"comments":[]}'
    fi ;;
  "issue comment") echo "https://github.com/org/repo/issues/7#issuecomment-1" ;;
  "issue edit")    echo "https://github.com/org/repo/issues/7" ;;
  "api user")      echo "fr1j0" ;;
  "auth status")   exit 0 ;;
  *) echo "fake gh: unhandled: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$TMP/gh"
export PATH="$TMP:$PATH"
export GH_ARGS="$TMP/gh-args"

run() { TRACKER="${TRK:-github}" bash "$BT" "$@" 2>"$TMP/err"; }

# whoami
out="$(run whoami)"; code=$?
[[ "$out" == "fr1j0" && $code -eq 0 ]] && echo "PASS: whoami" || { echo "FAIL: whoami → '$out' ($code)"; fail=1; }

# list-mine passes --assignee @me and returns the array
out="$(run list-mine)"; code=$?
{ [[ $code -eq 0 ]] && echo "$out" | grep -q '"number":7' \
  && grep -q -- "--assignee @me" "$GH_ARGS"; } \
  && echo "PASS: list-mine" || { echo "FAIL: list-mine → '$out' ($code)"; fail=1; }

# comments are normalized to [{author,createdAt,body}] (author flattened from .login)
out="$(run comments 7)"; code=$?
{ [[ $code -eq 0 ]] && echo "$out" | jq -e '.[0].author == "fr1j0" and (.[0].body | startswith("[CTX]"))' >/dev/null; } \
  && echo "PASS: comments normalized" || { echo "FAIL: comments → '$out' ($code)"; fail=1; }

# comment requires --body-file
BODY="$TMP/body.md"; echo "[CTX] Status update" > "$BODY"
out="$(run comment 7 --body-file "$BODY")"; code=$?
{ [[ $code -eq 0 ]] && grep -q -- "issue comment 7 --body-file" "$GH_ARGS"; } \
  && echo "PASS: comment" || { echo "FAIL: comment → '$out' ($code)"; fail=1; }
run comment 7 >/dev/null 2>&1; [[ $? -eq 2 ]] && echo "PASS: comment missing --body-file → 2" || { echo "FAIL: comment arg-guard"; fail=1; }

# edit-body
out="$(run edit-body 7 --body-file "$BODY")"; code=$?
{ [[ $code -eq 0 ]] && grep -q -- "issue edit 7 --body-file" "$GH_ARGS"; } \
  && echo "PASS: edit-body" || { echo "FAIL: edit-body → '$out' ($code)"; fail=1; }

# doctor passes when gh+jq present and authed
run doctor >/dev/null 2>&1; [[ $? -eq 0 ]] && echo "PASS: doctor ok" || { echo "FAIL: doctor ok"; fail=1; }

# unknown verb → 2
run frobnicate >/dev/null 2>&1; [[ $? -eq 2 ]] && echo "PASS: unknown verb → 2" || { echo "FAIL: unknown verb"; fail=1; }

# gitlab backend stub → 3
TRK=gitlab run list-mine >/dev/null 2>&1; [[ $? -eq 3 ]] && echo "PASS: gitlab stub → 3" || { echo "FAIL: gitlab stub"; fail=1; }

if (( fail )); then echo "SOME TESTS FAILED"; exit 1; else echo "ALL TESTS PASSED"; fi
