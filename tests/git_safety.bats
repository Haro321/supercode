#!/usr/bin/env bats

load test_helper

setup() {
  _load_libs
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "assert_safe_worktree_path allows paths inside SUPERCODE_HOME" {
  require_repo
  run assert_safe_worktree_path "$SUPERCODE_HOME/myrepo/agent-1"
  [[ "$status" -eq 0 ]]
}

@test "assert_safe_worktree_path rejects paths outside SUPERCODE_HOME" {
  require_repo
  run assert_safe_worktree_path "/tmp/evil-path"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unsafe path"* ]]
}

@test "assert_safe_worktree_path rejects root" {
  require_repo
  SUPERCODE_HOME="/"
  run assert_safe_worktree_path "/"
  [[ "$status" -ne 0 ]]
}

@test "_unmerged_count returns 0 for merged branch" {
  require_repo
  [[ $(_unmerged_count "main") == "0" ]]
}

@test "_unmerged_count counts commits on unmerged supercode branch" {
  require_repo
  git -C "$TEST_REPO" checkout -b supercode/test-branch >/dev/null 2>&1
  echo "content" > "$TEST_REPO/file.txt"
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" -c user.name=test -c user.email=test@test commit -m "new commit" --no-verify >/dev/null 2>&1
  git -C "$TEST_REPO" checkout main >/dev/null 2>&1

  result=$(_unmerged_count "supercode/test-branch")
  [[ "$result" == "1" ]]
}
