#!/usr/bin/env bash
# View agent status signals.

cmd_signals() {
  require_repo
  local status_dir
  status_dir="$(_status_dir)"

  if [[ ! -d "$status_dir" ]] || ! compgen -G "$status_dir/*.json" >/dev/null 2>&1; then
    info "No status signals yet."
    return 0
  fi

  echo "${C_BOLD}Agent Signals:${C_RESET}"
  echo ""

  local total=0 done=0 blocked=0 working=0
  for f in "$status_dir"/*.json; do
    [[ -f "$f" ]] || continue
    ((++total))
    local key role status message timestamp agent_n display_name
    key=$(basename "$f" .json)
    if command -v jq >/dev/null 2>&1; then
      role=$(jq -r '.role // "unknown"' "$f" 2>/dev/null)
      status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null)
      message=$(jq -r '.message // ""' "$f" 2>/dev/null)
      timestamp=$(jq -r '.timestamp // ""' "$f" 2>/dev/null)
      agent_n=$(jq -r '.agent // ""' "$f" 2>/dev/null)
    else
      role=$(grep -o '"role":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      status=$(grep -o '"status":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      message=$(grep -o '"message":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      timestamp=""
      agent_n=""
    fi
    display_name="$role"
    [[ -n "$agent_n" && "$agent_n" != "null" && "$agent_n" != "" ]] && display_name="$role (agent-$agent_n)"

    local color="$C_DIM"
    case "$status" in
      done)      color="$C_GREEN"; ((++done)) ;;
      working)   color="$C_CYAN"; ((++working)) ;;
      blocked)   color="$C_RED"; ((++blocked)) ;;
      waiting)   color="$C_YELLOW" ;;
    esac

    printf "  ${C_BOLD}%-22s${C_RESET} ${color}%-10s${C_RESET}" "$display_name" "$status"
    [[ -n "$message" && "$message" != "null" ]] && printf "  %s" "${C_DIM}$message${C_RESET}"
    echo ""
  done

  echo ""
  printf "  ${C_DIM}total: %d  done: %d  working: %d  blocked: %d${C_RESET}\n" \
    "$total" "$done" "$working" "$blocked"

  local stale_list
  stale_list=$(signal_stale_agents 180)
  if [[ -n "$stale_list" ]]; then
    echo ""
    echo "  ${C_YELLOW}${C_BOLD}STALE (no update in >3min):${C_RESET}"
    for role in $stale_list; do
      local age
      age=$(signal_age_seconds "$role")
      printf "    ${C_YELLOW}%-15s${C_RESET} ${C_DIM}last update %ds ago${C_RESET}\n" "$role" "$age"
    done
  fi

  if (( blocked > 0 )); then
    echo ""
    echo "  ${C_RED}${C_BOLD}TIP:${C_RESET} Run ${C_BOLD}supercode brain unblock${C_RESET} to auto-diagnose blocked agents"
  fi
}
