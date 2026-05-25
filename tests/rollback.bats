#!/usr/bin/env bats

load test_helper

setup() {
  _load_libs
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "rollback refuses without recorded prelaunch point" {
  require_repo
  run cmd_rollback
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no rollback point"* ]]
}

@test "rollback detects already-at-prelaunch state" {
  require_repo
  mkdir -p "$WORKTREE_BASE"
  local sha
  sha=$(git -C "$TEST_REPO" rev-parse HEAD)
  printf "%s\nmain\n" "$sha" > "$WORKTREE_BASE/.pre-launch"

  run cmd_rollback
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already at the pre-launch state"* ]]
}
