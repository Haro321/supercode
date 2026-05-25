#!/usr/bin/env bats

load test_helper

setup() {
  _load_libs
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "clean refuses when agent has unmerged commits" {
  require_repo
  mkdir -p "$WORKTREE_BASE"
  local wt="$WORKTREE_BASE/agent-1"
  git -C "$TEST_REPO" worktree add -b supercode/agent-1-test "$wt" main >/dev/null 2>&1
  echo "work" > "$wt/file.txt"
  git -C "$wt" add -A
  git -C "$wt" -c user.name=test -c user.email=test@test commit -m "unmerged work" --no-verify >/dev/null 2>&1

  run cmd_clean
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Refusing to clean"* ]]
}

@test "clean refuses when agent has uncommitted changes" {
  require_repo
  mkdir -p "$WORKTREE_BASE"
  local wt="$WORKTREE_BASE/agent-1"
  git -C "$TEST_REPO" worktree add -b supercode/agent-1-test "$wt" main >/dev/null 2>&1
  echo "dirty" > "$wt/dirty.txt"

  run cmd_clean
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Refusing to clean"* ]]
}

@test "clean --force removes worktrees despite unmerged work" {
  require_repo
  mkdir -p "$WORKTREE_BASE"
  local wt="$WORKTREE_BASE/agent-1"
  git -C "$TEST_REPO" worktree add -b supercode/agent-1-test "$wt" main >/dev/null 2>&1
  echo "work" > "$wt/file.txt"
  git -C "$wt" add -A
  git -C "$wt" -c user.name=test -c user.email=test@test commit -m "unmerged" --no-verify >/dev/null 2>&1

  run cmd_clean --force
  [[ "$status" -eq 0 ]]
  [[ ! -d "$wt" ]]
}

@test "clean --dry-run shows what would be removed without removing" {
  require_repo
  mkdir -p "$WORKTREE_BASE"
  local wt="$WORKTREE_BASE/agent-1"
  git -C "$TEST_REPO" worktree add -b supercode/agent-1-test "$wt" main >/dev/null 2>&1

  run cmd_clean --force --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Dry run"* ]]
  [[ -d "$wt" ]]
}

@test "clean warns when no worktrees exist" {
  require_repo
  run cmd_clean
  [[ "$output" == *"no worktrees"* ]]
}
