#!/usr/bin/env bash
# Deterministic tests for resolve-project-scope.sh. Builds throwaway git repos
# and config files under mktemp so nothing depends on the caller's environment,
# real remotes, or a real ~/.claude/bitacora.yml.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
RPS="$DIR/resolve-project-scope.sh"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() {  # name [remote-url] → prints repo path; no remote when url omitted
  local path="$TMP/$1"
  git init -q "$path"
  [[ -n "${2:-}" ]] && git -C "$path" remote add origin "$2"
  printf '%s' "$path"
}

# Home-level config: the central map (plus unrelated keys the parser must skip).
HOME_CFG="$TMP/home-bitacora.yml"
cat > "$HOME_CFG" <<'EOF'
project_key_pattern: "[A-Z][A-Z0-9]+-\\d+"
comment_compliance:
  status_extraction: strict
next:
  stale_days: 30
  remote_project_map:
    "github.com/org/ai-advisor-portal": "AT"   # quoted entry + inline comment
    github.com/org/unquoted-repo: TESTING
    "github.com/org/shared-repo": "HOME"
digest:
  epic_type: Epic
EOF

# Repo-level config: overrides shared-repo only.
REPO_CFG="$TMP/repo-bitacora.yml"
cat > "$REPO_CFG" <<'EOF'
next:
  remote_project_map:
    "github.com/org/shared-repo": "REPO"
EOF

# A config with no next: block at all.
NOMAP_CFG="$TMP/nomap.yml"
echo 'project_key_pattern: "[A-Z]+-\\d+"' > "$NOMAP_CFG"

# A config ending inside remote_project_map (no trailing keys): the awk lookup
# hits EOF in the map and exits 0 with empty output when the slug is absent —
# the caller's [[ -n "$key" ]] guard must still turn that into exit 3.
EOFMAP_CFG="$TMP/eof-map.yml"
cat > "$EOFMAP_CFG" <<'EOF'
next:
  remote_project_map:
    "github.com/org/some-other-repo": "OTHER"
EOF

MISSING="$TMP/does-not-exist.yml"

check() {  # desc expected-stdout expected-code args...
  local desc="$1" expected="$2" want_code="$3"; shift 3
  local out code
  out="$(bash "$RPS" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected" && "$code" == "$want_code" ]]; then
    echo "PASS: $desc → '$out' ($code)"
  else
    echo "FAIL: $desc → got '$out' ($code), expected '$expected' ($want_code)"; fail=1
  fi
}
check_err_contains() {  # desc substring expected-code args...
  local desc="$1" sub="$2" want_code="$3"; shift 3
  local err code
  err="$(bash "$RPS" "$@" 2>&1 >/dev/null)"; code=$?
  if [[ "$code" == "$want_code" && "$err" == *"$sub"* ]]; then
    echo "PASS: $desc → exit $code, stderr names '$sub'"
  else
    echo "FAIL: $desc → exit $code, stderr '$err' (expected $want_code containing '$sub')"; fail=1
  fi
}

SSH_REPO="$(mkrepo ssh-repo 'git@github.com:Org/AI-Advisor-Portal.git')"
HTTPS_REPO="$(mkrepo https-repo 'https://github.com/org/ai-advisor-portal.git')"
SSHPROTO_REPO="$(mkrepo sshproto-repo 'ssh://git@github.com/org/ai-advisor-portal.git')"
NOGIT_SUFFIX_REPO="$(mkrepo nosuffix-repo 'https://github.com/org/unquoted-repo')"
SHARED_REPO="$(mkrepo shared-repo 'git@github.com:org/shared-repo.git')"
UNMAPPED_REPO="$(mkrepo unmapped-repo 'git@github.com:other/vatios.git')"
BARE_REPO="$(mkrepo bare-repo)"          # git repo, no remotes
UPSTREAM_REPO="$(mkrepo upstream-repo)"  # no origin: only an upstream remote
git -C "$UPSTREAM_REPO" remote add upstream 'git@github.com:org/ai-advisor-portal.git'
PLAIN_DIR="$TMP/plain-dir"; mkdir -p "$PLAIN_DIR"   # not a git repo

check "ssh remote (+case, +.git strip)"  AT 0 --dir "$SSH_REPO"      --repo-config "$MISSING" --home-config "$HOME_CFG"
check "https remote"                     AT 0 --dir "$HTTPS_REPO"    --repo-config "$MISSING" --home-config "$HOME_CFG"
check "ssh:// protocol remote"           AT 0 --dir "$SSHPROTO_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check "no .git suffix, unquoted entry"   TESTING 0 --dir "$NOGIT_SUFFIX_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check "repo-level map overrides home"    REPO 0 --dir "$SHARED_REPO" --repo-config "$REPO_CFG" --home-config "$HOME_CFG"
check "home fallback (repo cfg lacks slug)" HOME 0 --dir "$SHARED_REPO" --repo-config "$NOMAP_CFG" --home-config "$HOME_CFG"
check "first-remote fallback (no origin)" AT 0 --dir "$UPSTREAM_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"

check_err_contains "slug not in any map → exit 3"   "github.com/other/vatios" 3 --dir "$UNMAPPED_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check_err_contains "map at EOF, slug absent → exit 3" "github.com/other/vatios" 3 --dir "$UNMAPPED_REPO" --repo-config "$EOFMAP_CFG" --home-config "$MISSING"
check_err_contains "both configs missing → exit 3"  "github.com/other/vatios" 3 --dir "$UNMAPPED_REPO" --repo-config "$MISSING" --home-config "$MISSING"
check_err_contains "repo without remotes → exit 4"  "no git remote" 4 --dir "$BARE_REPO" --repo-config "$MISSING" --home-config "$HOME_CFG"
check_err_contains "not a git repo → exit 4"        "not a git repository" 4 --dir "$PLAIN_DIR" --repo-config "$MISSING" --home-config "$HOME_CFG"
check_err_contains "unknown arg → exit 2"           "unknown arg" 2 --bogus

exit $fail
