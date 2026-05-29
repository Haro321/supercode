#!/usr/bin/env bash
# Alembic migration chain helpers.
#
# When N agents create migrations in parallel worktrees, they each set
# down_revision to the same pre-fork head. Merging all branches into master
# leaves the chain forked (N heads), and `alembic upgrade head` refuses to
# run. These helpers detect that and offer to linearize by re-parenting
# the forked children in commit-time order.

# Find every alembic versions/ directory under the repo, excluding venvs
# and node_modules. Prints one absolute path per line.
migrations_find_dirs() {
  local root="${1:-$REPO_ROOT}"
  [[ -d "$root" ]] || return 0
  find "$root" -type d -path '*/alembic/versions' \
    -not -path '*/venv/*' -not -path '*/.venv/*' \
    -not -path '*/node_modules/*' -not -path '*/__pycache__/*' \
    2>/dev/null
}

# Extract revision and down_revision from a migration file.
# Echoes "rev|down_rev" (down_rev may be empty for the base).
_migrations_parse_file() {
  local f=$1
  local rev down
  rev=$(grep -E "^revision[[:space:]]*[:=]" "$f" 2>/dev/null \
    | head -1 | sed -E "s/.*[:=][[:space:]]*['\"]?([^'\"#]+).*/\1/" \
    | tr -d "[:space:]\"'")
  down=$(grep -E "^down_revision[[:space:]]*[:=]" "$f" 2>/dev/null \
    | head -1 | sed -E "s/.*[:=][[:space:]]*['\"]?([^'\"#]+).*/\1/" \
    | tr -d "[:space:]\"'")
  [[ "$down" == "None" ]] && down=""
  echo "$rev|$down"
}

# Emit the chain for a versions dir: one line per file, "rev|down|path".
# Files that don't have a `revision = ...` line are skipped silently.
migrations_collect_chain() {
  local dir=$1
  [[ -d "$dir" ]] || return 0
  local f rev_down
  for f in "$dir"/*.py; do
    [[ -f "$f" ]] || continue
    rev_down=$(_migrations_parse_file "$f")
    [[ "${rev_down%%|*}" ]] || continue
    echo "${rev_down}|$f"
  done
}

# Print heads (revisions that no other migration lists as down_revision)
# in the given versions/ dir, one per line.
migrations_heads() {
  local dir=$1
  local chain all_rev all_down
  chain=$(migrations_collect_chain "$dir") || return 0
  [[ -z "$chain" ]] && return 0
  all_rev=$(echo "$chain"   | awk -F'|' '{print $1}' | sort -u)
  all_down=$(echo "$chain"  | awk -F'|' '$2!="" {print $2}' | sort -u)
  comm -23 <(echo "$all_rev") <(echo "$all_down")
}

# Print fork points: revs that are the down_revision of >1 migration.
# Output: one fork rev per line.
migrations_fork_points() {
  local dir=$1
  migrations_collect_chain "$dir" \
    | awk -F'|' '$2!="" {print $2}' \
    | sort | uniq -d
}

# For a given rev, walk down (child of, child of...) until reaching a leaf.
# If a fork is hit mid-walk, returns the first child (lexicographic). The
# linearizer iterates so this is fine — after each pass forks shrink.
_migrations_walk_to_tail() {
  local dir=$1 start=$2
  local chain cur next
  chain=$(migrations_collect_chain "$dir")
  cur=$start
  while :; do
    next=$(echo "$chain" | awk -F'|' -v p="$cur" '$2==p {print $1}' | head -1)
    [[ -z "$next" ]] && break
    cur=$next
  done
  echo "$cur"
}

# Sort key for a migration file's creation order. Returns "<epoch>\t<tiebreaker>"
# so callers can use `sort -k1,1n -k2,2`. The tiebreaker matters because parallel
# agents often commit migrations in the same second — without it, `sort -n` ties
# resolve non-deterministically and linearization picks an arbitrary parent.
#   - Tracked file: git commit time + commit hash (deterministic across runs)
#   - Untracked file: file mtime + filename
_migrations_file_time() {
  local file=$1 info t h
  info=$(git -C "$REPO_ROOT" log -1 --format='%ct %H' -- "$file" 2>/dev/null)
  if [[ -n "$info" ]]; then
    t="${info%% *}"
    h="${info##* }"
    printf '%s\t%s' "$t" "$h"
  else
    t=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    printf '%s\t%s' "$t" "$(basename "$file")"
  fi
}

# Rewrite the down_revision line in a migration file. Preserves quoting
# style and surrounding whitespace as much as possible by doing two edits:
# the docstring `Revises:` header (if present) and the assignment.
_migrations_rewrite_down() {
  local file=$1 new_parent=$2
  local tmp
  tmp=$(mktemp) || return 1
  awk -v new="$new_parent" '
    BEGIN { did_assign=0; did_header=0 }
    /^down_revision[[:space:]]*=/ && !did_assign {
      print "down_revision = " "\x27" new "\x27"
      did_assign=1; next
    }
    /^Revises:[[:space:]]/ && !did_header {
      print "Revises: " new
      did_header=1; next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Linearize one alembic versions/ dir. Repeats until no fork points remain
# or until 20 passes (safety). Edits files in place; caller is responsible
# for staging/committing.
#
# Returns 0 and prints "linearized: N edit(s)" on success, 1 on no-op.
migrations_linearize_dir() {
  local dir=$1
  [[ -d "$dir" ]] || return 1
  local edits=0 pass=0

  while (( pass < 20 )); do
    local forks
    forks=$(migrations_fork_points "$dir")
    [[ -z "$forks" ]] && break
    ((++pass))

    local fork
    while IFS= read -r fork; do
      [[ -z "$fork" ]] && continue
      # Children of this fork
      local chain children_with_time
      chain=$(migrations_collect_chain "$dir")
      children_with_time=$(echo "$chain" \
        | awk -F'|' -v p="$fork" '$2==p {print $1 "|" $3}')

      # Sort children by commit time of their file
      local sorted=()
      while IFS='|' read -r crev cfile; do
        [[ -z "$crev" ]] && continue
        local t
        t=$(_migrations_file_time "$cfile")
        sorted+=("$t|$crev|$cfile")
      done <<< "$children_with_time"

      # Sort by commit time (k1, numeric), then by hash (k2) for a stable
      # tiebreak when multiple migrations land in the same second.
      IFS=$'\n' sorted=($(printf '%s\n' "${sorted[@]}" | sort -k1,1n -k2,2))
      unset IFS

      # Re-parent children[1..] onto previous child's tail
      local i prev_tail prev_rev
      prev_rev=""
      for (( i=0; i<${#sorted[@]}; i++ )); do
        local entry="${sorted[$i]}"
        local crev cfile
        crev=$(echo "$entry" | awk -F'|' '{print $2}')
        cfile=$(echo "$entry" | awk -F'|' '{print $3}')
        if (( i == 0 )); then
          prev_rev=$crev
          continue
        fi
        prev_tail=$(_migrations_walk_to_tail "$dir" "$prev_rev")
        _migrations_rewrite_down "$cfile" "$prev_tail"
        ((++edits))
        prev_rev=$crev
      done
    done <<< "$forks"
  done

  if (( edits > 0 )); then
    echo "$edits"
    return 0
  fi
  return 1
}

# Top-level: scan every alembic dir in the repo. For each that has >1 head
# or any fork point, print a short summary. Returns 0 if all chains are
# linear, 1 if at least one dir has multi-head or forks.
migrations_audit() {
  local root="${1:-$REPO_ROOT}"
  local issues=0
  local dir
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    local heads forks head_count
    heads=$(migrations_heads "$dir")
    forks=$(migrations_fork_points "$dir")
    head_count=$(echo "$heads" | grep -c '.' || true)
    if (( head_count > 1 )) || [[ -n "$forks" ]]; then
      ((++issues))
      local rel="${dir#$root/}"
      echo "  ${C_BOLD}${rel}${C_RESET}"
      if (( head_count > 1 )); then
        echo "    heads ($head_count): $(echo "$heads" | tr '\n' ' ')"
      fi
      if [[ -n "$forks" ]]; then
        echo "    forks: $(echo "$forks" | tr '\n' ' ')"
      fi
    fi
  done < <(migrations_find_dirs "$root")
  (( issues == 0 ))
}
