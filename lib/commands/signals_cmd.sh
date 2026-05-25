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
    ((total++))
    local role status message timestamp
    role=$(basename "$f" .json)
    if command -v jq >/dev/null 2>&1; then
      status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null)
      message=$(jq -r '.message // ""' "$f" 2>/dev/null)
      timestamp=$(jq -r '.timestamp // ""' "$f" 2>/dev/null)
    else
      status=$(grep -o '"status":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      message=$(grep -o '"message":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      timestamp=""
    fi

    local color="$C_DIM"
    case "$status" in
      done)      color="$C_GREEN"; ((done++)) ;;
      working)   color="$C_CYAN"; ((working++)) ;;
      blocked)   color="$C_RED"; ((blocked++)) ;;
      waiting)   color="$C_YELLOW" ;;
    esac

    printf "  ${C_BOLD}%-15s${C_RESET} ${color}%-10s${C_RESET}" "$role" "$status"
    [[ -n "$message" && "$message" != "null" ]] && printf "  %s" "${C_DIM}$message${C_RESET}"
    echo ""
  done

  echo ""
  printf "  ${C_DIM}total: %d  done: %d  working: %d  blocked: %d${C_RESET}\n" \
    "$total" "$done" "$working" "$blocked"
}
