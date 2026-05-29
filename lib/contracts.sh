#!/usr/bin/env bash
# Contract and file ownership management.

SUPERCODE_DIR=".supercode"

_sc_dir_path() {
  echo "$REPO_ROOT/$SUPERCODE_DIR"
}

_ownership_file() {
  echo "$(_sc_dir_path)/ownership.json"
}

ensure_sc_dir() {
  mkdir -p "$(_sc_dir_path)"
}

ownership_set() {
  local role=$1 pattern=$2
  local f
  f="$(_ownership_file)"
  ensure_sc_dir
  if [[ -f "$f" ]] && command -v jq >/dev/null 2>&1; then
    local current
    current=$(jq -r --arg r "$role" '.[$r] // ""' "$f" 2>/dev/null || echo "")
    if [[ -n "$current" ]]; then
      jq --arg r "$role" --arg p "$pattern" '.[$r] = (.[$r] + "," + $p)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
      jq --arg r "$role" --arg p "$pattern" '.[$r] = $p' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
  elif command -v jq >/dev/null 2>&1; then
    # File doesn't exist yet -- create it with a single key (jq escapes safely).
    jq -n --arg r "$role" --arg p "$pattern" '{($r): $p}' > "$f"
  else
    # Without jq we can't safely merge or escape; refuse rather than clobber the
    # whole ownership map (the rest of the ownership API already no-ops sans jq).
    warn "jq not found -- 'supercode claim' requires jq to record ownership (skipped: $role -> $pattern)"
  fi
}

ownership_get() {
  local role=$1
  local f
  f="$(_ownership_file)"
  if [[ -f "$f" ]] && command -v jq >/dev/null 2>&1; then
    jq -r --arg r "$role" '.[$r] // ""' "$f" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

ownership_list() {
  local f
  f="$(_ownership_file)"
  if [[ -f "$f" ]] && command -v jq >/dev/null 2>&1; then
    echo "${C_BOLD}File ownership:${C_RESET}"
    jq -r 'to_entries[] | "  \(.key): \(.value)"' "$f" 2>/dev/null
  elif [[ -f "$f" ]]; then
    echo "${C_BOLD}File ownership:${C_RESET}"
    cat "$f"
  else
    echo "${C_DIM}No ownership defined. Use 'supercode claim' or run 'supercode plan' to generate.${C_RESET}"
  fi
}

ownership_init_from_roles() {
  local f
  f="$(_ownership_file)"
  ensure_sc_dir
  shift || true
  local roles=("$@")
  if command -v jq >/dev/null 2>&1; then
    local json="{}"
    for role in "${roles[@]}"; do
      local default_own="${ROLE_DEFAULT_OWNERSHIP[$role]:-}"
      if [[ -n "$default_own" ]]; then
        json=$(echo "$json" | jq --arg r "$role" --arg p "$default_own" '.[$r] = $p')
      fi
    done
    echo "$json" | jq '.' > "$f"
  fi
}

ownership_check_violations() {
  local current=$1
  local f
  f="$(_ownership_file)"
  [[ -f "$f" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local violations_found=0
  while IFS= read -r wt; do
    local agent agent_num branch role
    agent=$(basename "$wt")
    agent_num="${agent#agent-}"
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || continue)

    role=$(session_get_agent "$agent_num" role 2>/dev/null || echo "")
    [[ -n "$role" ]] || continue

    local agent_ownership
    agent_ownership=$(jq -r --arg r "$role" '.[$r] // ""' "$f" 2>/dev/null || echo "")
    [[ -n "$agent_ownership" ]] || continue

    local changed_files
    changed_files=$(git -C "$REPO_ROOT" diff --name-only "$current...$branch" 2>/dev/null || true)
    [[ -n "$changed_files" ]] || continue

    while IFS= read -r changed_file; do
      [[ -n "$changed_file" ]] || continue
      local owned=0
      IFS=',' read -ra patterns <<< "$agent_ownership"
      for pat in "${patterns[@]}"; do
        pat=$(echo "$pat" | xargs)
        # Simple glob match using bash
        if [[ "$changed_file" == $pat ]]; then
          owned=1
          break
        fi
        # Check directory prefix for ** patterns
        local prefix="${pat%%/\*\*}"
        if [[ "$prefix" != "$pat" && "$changed_file" == "$prefix"/* ]]; then
          owned=1
          break
        fi
      done
      if (( ! owned )); then
        if (( ! violations_found )); then
          echo "${C_YELLOW}Ownership violations:${C_RESET}"
          violations_found=1
        fi
        echo "  ${C_BOLD}$agent ($role)${C_RESET} modified ${C_RED}$changed_file${C_RESET} (outside ownership: $agent_ownership)"
      fi
    done <<< "$changed_files"
  done < <(_sorted_worktrees)

  return $violations_found
}

detect_project_type() {
  local root="${1:-$REPO_ROOT}"
  if [[ -f "$root/package.json" ]]; then
    if [[ -f "$root/next.config.js" || -f "$root/next.config.mjs" || -f "$root/next.config.ts" ]]; then
      echo "nextjs"
    elif grep -q '"react"' "$root/package.json" 2>/dev/null; then
      echo "react"
    elif grep -q '"vue"' "$root/package.json" 2>/dev/null; then
      echo "vue"
    elif grep -q '"svelte"' "$root/package.json" 2>/dev/null; then
      echo "svelte"
    else
      echo "node"
    fi
  elif [[ -f "$root/pyproject.toml" || -f "$root/setup.py" || -f "$root/requirements.txt" ]]; then
    if [[ -f "$root/manage.py" ]]; then
      echo "django"
    elif grep -q "fastapi\|flask" "$root/requirements.txt" 2>/dev/null || grep -q "fastapi\|flask" "$root/pyproject.toml" 2>/dev/null; then
      echo "python-web"
    else
      echo "python"
    fi
  elif [[ -f "$root/Cargo.toml" ]]; then
    echo "rust"
  elif [[ -f "$root/go.mod" ]]; then
    echo "go"
  elif [[ -f "$root/composer.json" ]]; then
    echo "php"
  elif [[ -f "$root/Gemfile" ]]; then
    echo "ruby"
  elif [[ -f "$root/build.gradle" || -f "$root/pom.xml" ]]; then
    echo "java"
  else
    echo "unknown"
  fi
}

_test_commands_for_project() {
  local ptype=$1
  case "$ptype" in
    nextjs|react|vue|svelte|node)
      echo "npm test;npm run lint;npm run typecheck;npm run build"
      ;;
    python|python-web|django)
      echo "pytest;python -m mypy .;ruff check ."
      ;;
    rust)
      echo "cargo test;cargo clippy;cargo build"
      ;;
    go)
      echo "go test ./...;go vet ./...;go build ./..."
      ;;
    php)
      echo "composer test;php vendor/bin/phpstan analyse"
      ;;
    ruby)
      echo "bundle exec rspec;bundle exec rubocop"
      ;;
    java)
      echo "gradle test;gradle build"
      ;;
    *)
      echo ""
      ;;
  esac
}
