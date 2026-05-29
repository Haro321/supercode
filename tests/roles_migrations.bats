#!/usr/bin/env bats

load test_helper

setup() {
  source "$SUPERCODE_LIB/ui.sh"
  source "$SUPERCODE_LIB/git.sh"
  source "$SUPERCODE_LIB/roles.sh"
  source "$SUPERCODE_LIB/contracts.sh"
  source "$SUPERCODE_LIB/signals.sh"
  source "$SUPERCODE_LIB/migrations.sh"
}

# --- roles / presets consistency (guards doc<->code drift) ---------------

@test "every preset references only defined roles" {
  local p r
  for p in "${!PRESETS[@]}"; do
    IFS=',' read -ra _rs <<< "${PRESETS[$p]}"
    for r in "${_rs[@]}"; do
      [[ -n "${ROLE_DESCRIPTIONS[$r]:-}" ]] \
        || { echo "preset '$p' references unknown role '$r'"; return 1; }
    done
  done
}

@test "every role in the README role table exists in ROLE_DESCRIPTIONS" {
  # Note: don't use $SUPERCODE_DIR here -- contracts.sh repurposes that name as
  # the ".supercode" dir. Resolve the repo root from the test file's location.
  local readme="$BATS_TEST_DIRNAME/../README.md"
  local in_table=0 line role
  while IFS= read -r line; do
    if [[ "$line" == "| Role | Responsibility |"* ]]; then in_table=1; continue; fi
    (( in_table )) || continue
    [[ "$line" == "|"* ]] || break          # left the table
    [[ "$line" == *"---"* ]] && continue     # separator row
    role=$(printf '%s' "$line" | sed -E 's/^\| *`([^`]+)`.*/\1/')
    [[ "$role" == "$line" ]] && continue     # no backticked role on this row
    [[ -n "${ROLE_DESCRIPTIONS[$role]:-}" ]] \
      || { echo "README lists role '$role' not in ROLE_DESCRIPTIONS"; return 1; }
  done < "$readme"
  (( in_table )) || { echo "could not find the README role table"; return 1; }
}

@test "every role has a default-ownership entry" {
  local r
  for r in "${!ROLE_DESCRIPTIONS[@]}"; do
    [[ -n "${ROLE_DEFAULT_OWNERSHIP[$r]+x}" ]] \
      || { echo "role '$r' has no ROLE_DEFAULT_OWNERSHIP entry"; return 1; }
  done
}

@test "parse_roles trims whitespace around comma-separated roles" {
  run parse_roles "backend, frontend ,qa"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "backend,frontend,qa" ]]
}

@test "parse_roles rejects an unknown role" {
  run parse_roles "backend,definitelynotarole"
  [[ "$status" -ne 0 ]]
}

# --- migration chain helpers --------------------------------------------

@test "migrations_linearize_dir resolves a typed (colon) fork" {
  export REPO_ROOT="$BATS_TMPDIR/mig-typed-$$"
  local v="$REPO_ROOT/alembic/versions"
  rm -rf "$REPO_ROOT"; mkdir -p "$v"
  printf "revision: str = 'base'\ndown_revision: Union[str, None] = None\n" > "$v/1.py"
  printf "revision: str = 'a'\ndown_revision: Union[str, None] = 'base'\n"   > "$v/2.py"
  printf "revision: str = 'b'\ndown_revision: Union[str, None] = 'base'\n"   > "$v/3.py"
  run migrations_linearize_dir "$v"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "1" ]]                        # exactly one re-parent, not 20
  [[ -z "$(migrations_fork_points "$v")" ]]     # fork resolved
  rm -rf "$REPO_ROOT"
}

@test "migrations_linearize_dir refuses a merge migration" {
  export REPO_ROOT="$BATS_TMPDIR/mig-merge-$$"
  local v="$REPO_ROOT/alembic/versions"
  rm -rf "$REPO_ROOT"; mkdir -p "$v"
  printf "revision = 'base'\ndown_revision = None\n"        > "$v/1.py"
  printf "revision = 'a'\ndown_revision = 'base'\n"          > "$v/2.py"
  printf "revision = 'b'\ndown_revision = 'base'\n"          > "$v/3.py"
  printf "revision = 'mrg'\ndown_revision = ('a', 'b')\n"    > "$v/4.py"
  [[ "$(_migrations_parse_file "$v/4.py")" == "mrg|a,b" ]]   # tuple parsed, not "("
  run migrations_linearize_dir "$v"
  [[ "$status" -ne 0 ]]                          # refuses rather than corrupts
  rm -rf "$REPO_ROOT"
}

# --- signal staleness ----------------------------------------------------

@test "signal_age_seconds falls back to file mtime when timestamp is absent" {
  export WORKTREE_BASE="$BATS_TMPDIR/sig-$$"
  rm -rf "$WORKTREE_BASE"
  shared_dir_init
  # an agent overwrites status WITHOUT a timestamp field
  printf '{"role":"backend","status":"working","message":"x","agent":"1"}\n' \
    > "$(_status_dir)/backend_1.json"
  run signal_age_seconds backend_1
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^[0-9]+$ ]]                    # a real age, never -1
  rm -rf "$WORKTREE_BASE"
}
