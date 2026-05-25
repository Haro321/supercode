#!/usr/bin/env bash
# Shared helpers for supercode bats tests.

SUPERCODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SUPERCODE_LIB="$SUPERCODE_DIR/lib"
export SUPERCODE_HOME="$BATS_TMPDIR/supercode-test-$$"

# Source just the libraries without running the dispatch
_load_libs() {
  source "$SUPERCODE_LIB/ui.sh"
  source "$SUPERCODE_LIB/git.sh"
  source "$SUPERCODE_LIB/tmux_helpers.sh"
  source "$SUPERCODE_LIB/agents.sh"
  source "$SUPERCODE_LIB/brain.sh"
  source "$SUPERCODE_LIB/session.sh"
  for f in "$SUPERCODE_LIB"/commands/*.sh; do
    [[ -f "$f" ]] && source "$f"
  done
}

# Create a temporary git repo for testing
setup_test_repo() {
  export TEST_REPO="$BATS_TMPDIR/test-repo-$$"
  mkdir -p "$TEST_REPO"
  git -C "$TEST_REPO" init -b main >/dev/null 2>&1
  git -C "$TEST_REPO" -c user.name='test' -c user.email='test@test' \
    commit --allow-empty -m "initial" >/dev/null 2>&1
  cd "$TEST_REPO"
}

teardown_test_repo() {
  rm -rf "$TEST_REPO" "$SUPERCODE_HOME" 2>/dev/null || true
}
