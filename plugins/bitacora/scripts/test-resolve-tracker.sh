#!/usr/bin/env bash
# Deterministic tests for resolve-tracker.sh. Throwaway git repos + config files
# under mktemp; no real remotes or ~/.claude config involved.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
RT="$DIR/resolve-tracker.sh"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkrepo() {  # name [remote-url] → prints repo path; no remote when url omitted
  local path="$TMP/$1"
  git init -q "$path"
  [[ -n "${2:-}" ]] && git -C "$path" remote add origin "$2"
  printf '%s' "$path"
}

GH_REPO="$(mkrepo gh-repo https://github.com/org/vatios.git)"
GL_REPO="$(mkrepo gl-repo git@gitlab.com:org/thing.git)"
JIRA_REPO="$(mkrepo jira-repo git@bitbucket.example.com:org/thing.git)"
NOREMOTE="$(mkrepo no-remote)"

# Config with an explicit tracker: override.
OVERRIDE_CFG="$TMP/override.yml"
cat > "$OVERRIDE_CFG" <<'EOF'
tracker: jira   # explicit override beats remote inference
next:
  stale_days: 30
EOF

# Config selecting gitlab explicitly (for a self-managed host that won't infer).
GL_CFG="$TMP/gl.yml"
echo 'tracker: "gitlab"' > "$GL_CFG"

MISSING="$TMP/none.yml"

check() {  # desc expected-stdout expected-code args...
  local desc="$1" expected="$2" want_code="$3"; shift 3
  local out code
  out="$(bash "$RT" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == "$want_code" ]]; then
    echo "PASS: $desc → '$out' ($code)"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' ($want_code)"; fail=1
  fi
}

check "github inferred from remote" github 0 \
  --dir "$GH_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check "gitlab inferred from remote" gitlab 0 \
  --dir "$GL_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check "unknown host infers jira" jira 0 \
  --dir "$JIRA_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check "explicit tracker beats inference" jira 0 \
  --dir "$GH_REPO" --repo-config "$OVERRIDE_CFG" --home-config "$MISSING"
check "explicit gitlab for self-managed (no remote)" gitlab 0 \
  --dir "$NOREMOTE" --repo-config "$GL_CFG" --home-config "$MISSING"
check "no remote and no explicit tracker → exit 4" "" 4 \
  --dir "$NOREMOTE" --repo-config "$MISSING" --home-config "$MISSING"
check "unknown arg → exit 2" "" 2 --bogus

if (( fail )); then echo "SOME TESTS FAILED"; exit 1; else echo "ALL TESTS PASSED"; fi
