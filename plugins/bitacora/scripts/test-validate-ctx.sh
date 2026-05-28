#!/usr/bin/env bash
# Asserts validate-ctx.sh classifies the three golden fixtures correctly.
set -uo pipefail  # no -e: the validator exits non-zero intentionally; we capture $? manually
DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$DIR/validate-ctx.sh"
FIXTURES="$DIR/../skills/jira-comment-format/examples"

fail=0
check() {
  local file="$1" expected_word="$2" expected_code="$3" out code
  out="$("$VALIDATOR" "$file" 2>/dev/null)"
  code=$?
  if [[ "$out" == "$expected_word" && "$code" == "$expected_code" ]]; then
    echo "PASS: $(basename "$file") → $out ($code)"
  else
    echo "FAIL: $(basename "$file") → got '$out' ($code), expected '$expected_word' ($expected_code)"
    fail=1
  fi
}

check "$FIXTURES/compliant.txt"                       compliant     0
check "$FIXTURES/compliant-with-preamble.txt"         compliant     0
check "$FIXTURES/malformed.txt"                       malformed     1
check "$FIXTURES/malformed-bare-url.txt"              malformed     1
check "$FIXTURES/malformed-tool-leak.txt"             malformed     1
check "$FIXTURES/malformed-preamble-bare-url.txt"     malformed     1
check "$FIXTURES/malformed-preamble-missing-sections.txt" malformed 1
check "$FIXTURES/non-ctx.txt"                         not-in-format 2

# startswith, not substring: a comment mentioning [CTX] mid-line is NOT compliant
mkstdin="$(mktemp)"
trap 'rm -f "$mkstdin"' EXIT
printf 'see the [CTX] note\nStatus: x\nNext: y\n' | "$VALIDATOR" >"$mkstdin" 2>/dev/null; code=$?
if [[ "$(cat "$mkstdin")" == "not-in-format" && "$code" == "2" ]]; then
  echo "PASS: mid-line [CTX] mention → not-in-format (2)"
else
  echo "FAIL: mid-line [CTX] mention → got '$(cat "$mkstdin")' ($code)"
  fail=1
fi

# Positive: a wrapped URL (markdown link) keeps the body compliant
printf '[CTX] Status update\n\nStatus: x\n\nDone:\n\n- PR opened: [#7951](https://github.com/acme/frontend/pull/7951)\n\nNext:\n\n- Merge.\n' \
  | "$VALIDATOR" >"$mkstdin" 2>/dev/null; code=$?
if [[ "$(cat "$mkstdin")" == "compliant" && "$code" == "0" ]]; then
  echo "PASS: wrapped URL [label](url) → compliant (0)"
else
  echo "FAIL: wrapped URL [label](url) → got '$(cat "$mkstdin")' ($code)"
  fail=1
fi

# Positive: autolink form <url> keeps the body compliant
printf '[CTX] Status update\n\nStatus: x\n\nDone:\n\n- PR opened: <https://github.com/acme/frontend/pull/7951>\n\nNext:\n\n- Merge.\n' \
  | "$VALIDATOR" >"$mkstdin" 2>/dev/null; code=$?
if [[ "$(cat "$mkstdin")" == "compliant" && "$code" == "0" ]]; then
  echo "PASS: autolink <url> → compliant (0)"
else
  echo "FAIL: autolink <url> → got '$(cat "$mkstdin")' ($code)"
  fail=1
fi

exit $fail
