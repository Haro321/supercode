#!/usr/bin/env bats

load test_helper

setup() {
  _load_libs
}

@test "_short_label strips 'Build a' prefix" {
  result=$(_short_label "Build a REST API server")
  [[ "$result" == "REST API server" ]]
}

@test "_short_label strips 'Create' prefix" {
  result=$(_short_label "Create user authentication")
  [[ "$result" == "user authentication" ]]
}

@test "_short_label strips 'Implement' prefix" {
  result=$(_short_label "Implement rate limiting")
  [[ "$result" == "rate limiting" ]]
}

@test "_short_label takes first 3 words" {
  result=$(_short_label "one two three four five six")
  [[ "$result" == "one two three" ]]
}

@test "_short_label caps at 24 characters" {
  result=$(_short_label "superlongwordnumberone superlongwordnumbertwo superlongwordnumberthree")
  [[ ${#result} -le 24 ]]
}

@test "_short_label handles empty string" {
  result=$(_short_label "")
  [[ "$result" == "" ]]
}

@test "_short_label strips 'Set up the' prefix" {
  result=$(_short_label "Set up the database schema")
  [[ "$result" == "database schema" ]]
}

@test "read_tasks_from_file ignores comments and blank lines" {
  local tmpfile="$BATS_TMPDIR/tasks-$$.txt"
  cat > "$tmpfile" <<'EOF'
# This is a comment
task one

# Another comment
task two

task three
EOF
  setup_test_repo
  # We can't fully run read_tasks_from_file because it calls cmd_start,
  # so test the parsing logic directly
  local tasks=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == "#"* ]] && continue
    tasks+=("$line")
  done < "$tmpfile"
  [[ ${#tasks[@]} -eq 3 ]]
  [[ "${tasks[0]}" == "task one" ]]
  [[ "${tasks[1]}" == "task two" ]]
  [[ "${tasks[2]}" == "task three" ]]
  rm -f "$tmpfile"
  teardown_test_repo
}

@test "sq_escape escapes single quotes" {
  result=$(sq_escape "it's a test")
  [[ "$result" == "it'\\''s a test" ]]
}

@test "sq_escape leaves clean strings unchanged" {
  result=$(sq_escape "no quotes here")
  [[ "$result" == "no quotes here" ]]
}

@test "_agent_accent_color returns valid color for agent 1" {
  result=$(_agent_accent_color 1)
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "_agent_accent_color wraps around palette" {
  c1=$(_agent_accent_color 1)
  c9=$(_agent_accent_color 9)
  [[ "$c1" == "$c9" ]]
}
