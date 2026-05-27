#!/usr/bin/env bash
# Asserts validate-ctx.sh classifies the three golden fixtures correctly.
set -uo pipefail  # no -e: the validator exits non-zero intentionally; we capture $? manually
DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$DIR/validate-ctx.sh"
FIXTURES="$DIR/../skills/jira-comment-format/examples"

fail=0
check() {
  local file="$1" expected_word="$2" expected_code="$3" out code
  out="$("$VALIDATOR" "$file")"
  code=$?
  if [[ "$out" == "$expected_word" && "$code" == "$expected_code" ]]; then
    echo "PASS: $(basename "$file") → $out ($code)"
  else
    echo "FAIL: $(basename "$file") → got '$out' ($code), expected '$expected_word' ($expected_code)"
    fail=1
  fi
}

check "$FIXTURES/compliant.txt" compliant     0
check "$FIXTURES/malformed.txt" malformed     1
check "$FIXTURES/non-ctx.txt"   not-in-format 2

# startswith, not substring: a comment mentioning [CTX] mid-line is NOT compliant
ss_out="$(mktemp)"
trap 'rm -f "$ss_out"' EXIT
printf 'see the [CTX] note\nStatus: x\nNext: y\n' | "$VALIDATOR" >"$ss_out" 2>&1; ss_code=$?
if [[ "$(cat "$ss_out")" == "not-in-format" && "$ss_code" == "2" ]]; then
  echo "PASS: mid-line [CTX] mention → not-in-format (2)"
else
  echo "FAIL: mid-line [CTX] mention → got '$(cat "$ss_out")' ($ss_code)"
  fail=1
fi

exit $fail
