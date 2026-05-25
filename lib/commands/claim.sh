#!/usr/bin/env bash
# File ownership management.

cmd_claim() {
  require_repo

  local sub=${1:-}; shift || true

  case "$sub" in
    "")
      die "usage: supercode claim <role> <glob-pattern>  or  supercode claims  or  supercode conflicts"
      ;;
    *)
      # supercode claim <role> <pattern>
      local role="$sub"
      local pattern="${1:-}"
      [[ -n "$pattern" ]] || die "usage: supercode claim <role> <glob-pattern>"
      [[ -n "${ROLE_DESCRIPTIONS[$role]:-}" ]] || warn "unknown role '$role' -- claiming anyway"
      ownership_set "$role" "$pattern"
      ok "$role now owns: $pattern"
      ;;
  esac
}

cmd_claims() {
  require_repo
  ownership_list
}

cmd_conflicts() {
  require_repo

  [[ -d "$WORKTREE_BASE" ]] && compgen -G "$WORKTREE_BASE/agent-*" >/dev/null \
    || die "no agent worktrees found"

  local current
  current="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

  echo "${C_BOLD}Checking for conflicts...${C_RESET}"
  echo ""

  # File overlap detection
  local -A file_agents=()
  while IFS= read -r wt; do
    local agent agent_num branch role
    agent=$(basename "$wt")
    agent_num="${agent#agent-}"
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || continue)
    role=$(session_get_agent "$agent_num" role 2>/dev/null || echo "$agent")

    local files
    files=$(git -C "$REPO_ROOT" diff --name-only "$current...$branch" 2>/dev/null || true)
    # Also check uncommitted
    files+=$'\n'$(git -C "$wt" diff --name-only 2>/dev/null || true)
    files+=$'\n'$(git -C "$wt" diff --cached --name-only 2>/dev/null || true)

    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [[ -n "${file_agents[$f]:-}" ]]; then
        file_agents["$f"]="${file_agents[$f]}, $role($agent)"
      else
        file_agents["$f"]="$role($agent)"
      fi
    done <<< "$files"
  done < <(_sorted_worktrees)

  local conflicts_found=0
  for f in "${!file_agents[@]}"; do
    if [[ "${file_agents[$f]}" == *","* ]]; then
      if (( ! conflicts_found )); then
        echo "${C_RED}File conflicts detected:${C_RESET}"
        conflicts_found=1
      fi
      echo "  ${C_BOLD}$f${C_RESET} -- modified by: ${file_agents[$f]}"
    fi
  done

  if (( ! conflicts_found )); then
    ok "No file conflicts detected across agents."
  fi

  # Ownership violations
  echo ""
  if ! ownership_check_violations "$current" 2>/dev/null; then
    : # violations printed by the function
  else
    ok "No ownership violations detected."
  fi
}
