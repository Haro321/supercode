#!/usr/bin/env bash
# Enhanced status display.

cmd_status() {
  require_repo
  local json_mode=0
  [[ "${1:-}" == "--json" ]] && json_mode=1

  if (( json_mode )); then
    session_to_json
    return
  fi

  echo "${C_BOLD}Repo:${C_RESET}   $REPO_NAME"

  local current
  current="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  echo "${C_BOLD}Branch:${C_RESET} $current @ $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"

  # Session status
  echo ""
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "${C_BOLD}Session:${C_RESET} ${C_GREEN}running${C_RESET}  (attach: ${C_BOLD}supercode attach${C_RESET})"
  else
    echo "${C_BOLD}Session:${C_RESET} ${C_DIM}not running${C_RESET}"
  fi

  # Agents
  echo ""
  echo "${C_BOLD}Agents:${C_RESET}"
  if [[ -d "$WORKTREE_BASE" ]] && compgen -G "$WORKTREE_BASE/agent-*" >/dev/null; then
    while IFS= read -r wt; do
      local agent branch ahead dirty task
      agent=$(basename "$wt")
      branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      ahead=$(_unmerged_count "$branch" 2>/dev/null || echo 0)

      dirty="no"
      if ! git -C "$wt" diff --quiet 2>/dev/null \
         || ! git -C "$wt" diff --cached --quiet 2>/dev/null \
         || [[ -n "$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        dirty="yes"
      fi

      local agent_num="${agent#agent-}"
      task=$(session_get_agent "$agent_num" task 2>/dev/null || echo "")
      local role
      role=$(session_get_agent "$agent_num" role 2>/dev/null || echo "")
      local astatus
      astatus=$(session_get_agent "$agent_num" status 2>/dev/null || echo "running")

      local role_display=""
      [[ -n "$role" ]] && role_display="${C_CYAN}$role${C_RESET}  "

      local label="${task:+$task}"
      [[ -z "$label" ]] && label="${branch##supercode/}"

      printf "  ${C_BOLD}%-10s${C_RESET} ${role_display}%-10s  dirty: %-3s  commits: %-3s  %s\n" \
        "$agent" "$astatus" "$dirty" "$ahead" "${C_DIM}${label:0:40}${C_RESET}"
    done < <(_sorted_worktrees)
  else
    echo "  ${C_DIM}(none)${C_RESET}"
  fi

  # Brain
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    local brain_id
    brain_id=$(_brain_pane_id "$SESSION_NAME")
    if [[ -n "$brain_id" ]]; then
      echo ""
      echo "${C_BOLD}Brain:${C_RESET}  ${C_GREEN}running${C_RESET}"
    fi
  fi

  # Rollback / save points
  echo ""
  if [[ -f "$WORKTREE_BASE/.pre-launch" ]]; then
    local pre_sha
    pre_sha=$(sed -n 1p "$WORKTREE_BASE/.pre-launch")
    echo "${C_BOLD}Rollback:${C_RESET} ${C_DIM}${pre_sha:0:12}${C_RESET}"
  fi
  if [[ -f "$WORKTREE_BASE/.last-save" ]]; then
    local save_sha
    save_sha=$(sed -n 1p "$WORKTREE_BASE/.last-save")
    echo "${C_BOLD}Unsave:${C_RESET}   ${C_DIM}${save_sha:0:12}${C_RESET}"
  fi
}

# Backward-compatible alias
cmd_list() {
  cmd_status "$@"
}
