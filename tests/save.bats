#!/usr/bin/env bats

load test_helper

setup() {
  _load_libs
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "save refuses when main repo has uncommitted changes" {
  require_repo
  echo "dirty" > "$TEST_REPO/dirty.txt"
  git -C "$TEST_REPO" add dirty.txt
  mkdir -p "$WORKTREE_BASE/agent-1"
  git -C "$TEST_REPO" worktree add -b supercode/agent-1-test "$WORKTREE_BASE/agent-1" main >/dev/null 2>&1
  run cmd_save
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "save refuses when no worktrees exist" {
  require_repo
  run cmd_save
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no supercode worktrees"* ]]
}

@test "save refuses on detached HEAD" {
  require_repo
  local sha
  sha=$(git -C "$TEST_REPO" rev-parse HEAD)
  git -C "$TEST_REPO" checkout "$sha" >/dev/null 2>&1
  mkdir -p "$WORKTREE_BASE/agent-1"
  run cmd_save
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "save --dry-run does not modify anything" {
  require_repo
  mkdir -p "$WORKTREE_BASE"
  local wt="$WORKTREE_BASE/agent-1"
  git -C "$TEST_REPO" worktree add -b supercode/agent-1-test "$wt" main >/dev/null 2>&1
  echo "new content" > "$wt/file.txt"
  git -C "$wt" add -A
  git -C "$wt" -c user.name=test -c user.email=test@test commit -m "test change" --no-verify >/dev/null 2>&1

  local pre_sha
  pre_sha=$(git -C "$TEST_REPO" rev-parse HEAD)

  run cmd_save --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Dry run"* ]]

  local post_sha
  post_sha=$(git -C "$TEST_REPO" rev-parse HEAD)
  [[ "$pre_sha" == "$post_sha" ]]
}
