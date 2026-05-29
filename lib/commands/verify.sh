#!/usr/bin/env bash
# QA verification: run build/test/lint commands in each worktree.

cmd_verify() {
  require_repo

  [[ -d "$WORKTREE_BASE" ]] && compgen -G "$WORKTREE_BASE/agent-*" >/dev/null \
    || die "no agent worktrees found"

  local ptype
  ptype=$(detect_project_type)
  local test_cmds
  test_cmds=$(_test_commands_for_project "$ptype")

  # Parse --cmd BEFORE the detection guard so a custom command works even when
  # the project type is unknown (the exact case the guard's hint advertises).
  local custom_cmd=""
  while (( $# )); do
    case "$1" in
      --cmd) shift; custom_cmd="${1:-}"; shift ;;
      *)     shift ;;
    esac
  done
  [[ -n "$custom_cmd" ]] && test_cmds="$custom_cmd"

  info "Project type: ${C_BOLD}$ptype${C_RESET}"

  if [[ -z "$test_cmds" ]]; then
    warn "could not detect test commands for project type '$ptype'"
    echo "  Run verification manually in each worktree, or specify commands:"
    echo "  ${C_BOLD}supercode verify --cmd 'npm test'${C_RESET}"
    return 1
  fi

  info "Test commands: ${C_DIM}$test_cmds${C_RESET}"
  echo ""

  local all_pass=1

  # Run in each worktree
  while IFS= read -r wt; do
    local agent agent_num role
    agent=$(basename "$wt")
    agent_num="${agent#agent-}"
    role=$(session_get_agent "$agent_num" role 2>/dev/null || echo "worker")

    echo "${C_BOLD}-- $agent ($role) --${C_RESET}"

    local has_changes=0
    if ! git -C "$wt" diff --quiet 2>/dev/null \
       || ! git -C "$wt" diff --cached --quiet 2>/dev/null \
       || [[ -n "$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
      has_changes=1
    fi
    local branch_ahead
    branch_ahead=$(_unmerged_count "$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" 2>/dev/null || echo 0)

    if [[ "$has_changes" == "0" && "$branch_ahead" == "0" ]]; then
      echo "  ${C_DIM}(no changes -- skipping)${C_RESET}"
      echo ""
      continue
    fi

    IFS=';' read -ra cmds <<< "$test_cmds"
    for cmd in "${cmds[@]}"; do
      # trim leading/trailing whitespace only -- do NOT use xargs, which strips
      # quotes and collapses spacing and would corrupt a custom --cmd.
      cmd="${cmd#"${cmd%%[![:space:]]*}"}"
      cmd="${cmd%"${cmd##*[![:space:]]}"}"
      [[ -n "$cmd" ]] || continue
      printf "  ${C_CYAN}$ %s${C_RESET} ... " "$cmd"
      if (cd "$wt" && eval "$cmd" >/dev/null 2>&1); then
        echo "${C_GREEN}pass${C_RESET}"
      else
        echo "${C_RED}FAIL${C_RESET}"
        all_pass=0
        session_update_agent "$agent_num" "verify" "fail:$cmd" 2>/dev/null || true
      fi
    done
    echo ""
  done < <(_sorted_worktrees)

  echo ""
  if (( all_pass )); then
    ok "All verification checks passed."
  else
    warn "Some checks failed. Review the output above."
    echo "  Fix issues and run ${C_BOLD}supercode verify${C_RESET} again."
    return 1
  fi
}
