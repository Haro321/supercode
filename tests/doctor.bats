#!/usr/bin/env bats

load test_helper

setup() {
  _load_libs
}

@test "doctor finds required dependencies" {
  run cmd_doctor
  [[ "$output" == *"bash:"* ]]
  [[ "$output" == *"git:"* ]]
  [[ "$output" == *"tmux:"* ]]
}

@test "doctor reports SUPERCODE_HOME" {
  run cmd_doctor
  [[ "$output" == *"SUPERCODE_HOME"* ]]
}

@test "doctor checks bash version" {
  run cmd_doctor
  [[ "$output" == *"bash: $BASH_VERSION"* ]]
}

@test "doctor shows optional deps section" {
  run cmd_doctor
  [[ "$output" == *"Optional:"* ]]
}
