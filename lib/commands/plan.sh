#!/usr/bin/env bash
# Plan phase: Brain creates spec, contracts, and agent assignments.

cmd_plan() {
  require_repo

  local task=""
  local preset=""
  local roles_str=""

  while (( $# )); do
    case "$1" in
      --preset)  shift; preset="${1:-}"; shift ;;
      --roles)   shift; roles_str="${1:-}"; shift ;;
      *)         task="$task $1"; shift ;;
    esac
  done
  task="${task# }"

  [[ -n "$task" ]] || die "usage: supercode plan \"description of what to build\" [--preset NAME] [--roles a,b,c]"

  # Resolve roles for the plan prompt
  local roles_list=""
  if [[ -n "$preset" ]]; then
    roles_list=$(resolve_preset "$preset")
  elif [[ -n "$roles_str" ]]; then
    roles_list=$(parse_roles "$roles_str")
  fi

  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    die "session '$SESSION_NAME' already running. Kill it first or use 'supercode brain plan'."
  fi

  ensure_sc_dir
  local sc_dir
  sc_dir="$(_sc_dir_path)"

  info "Starting planning phase for: ${C_BOLD}$task${C_RESET}"

  # Launch a single-pane session with Brain
  tmux new-session -d -s "$SESSION_NAME" -n plan -c "$REPO_ROOT"
  local brain_pid
  brain_pid=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')
  tmux set-option -wq -t "$SESSION_NAME:0" "@brain-pane" "$brain_pid"
  tmux select-pane -t "$brain_pid" -T "brain (planning)"

  apply_tmux_theme "$SESSION_NAME"

  local claude_cmd="clear && claude ${SUPERCODE_CLAUDE_ARGS:-}"
  tmux send-keys -t "$brain_pid" "$claude_cmd" Enter

  # Build the planning prompt
  local prompt=""
  prompt+="You are the Brain in planning mode. Your job is to create a detailed plan BEFORE any coding starts."$'\n\n'
  prompt+="THE USER'S REQUEST: $task"$'\n\n'

  local ptype
  ptype=$(detect_project_type)
  prompt+="PROJECT TYPE DETECTED: $ptype"$'\n\n'

  if [[ -n "$roles_list" ]]; then
    prompt+="AGENT ROLES TO USE: $roles_list"$'\n\n'
  fi

  prompt+="YOUR JOB:"$'\n'
  prompt+="Create the following files in the .supercode/ directory. These files will be given to every agent when they start working."$'\n\n'

  prompt+="1. Create .supercode/SPEC.md -- the specification:"$'\n'
  prompt+="   - What is being built (feature description)"$'\n'
  prompt+="   - Requirements (functional and non-functional)"$'\n'
  prompt+="   - Acceptance criteria"$'\n'
  prompt+="   - Out of scope"$'\n\n'

  prompt+="2. Create .supercode/CONTRACTS.md -- shared interfaces and types:"$'\n'
  prompt+="   - API endpoints (method, path, request body, response body)"$'\n'
  prompt+="   - Shared type definitions (with file path where they should live)"$'\n'
  prompt+="   - Database schema changes"$'\n'
  prompt+="   - Environment variables needed"$'\n'
  prompt+="   - Any shared constants or config"$'\n\n'

  prompt+="3. Create .supercode/AGENTS.md -- agent assignments:"$'\n'
  prompt+="   - For each agent role, list:"$'\n'
  prompt+="     - Role name"$'\n'
  prompt+="     - Specific task description"$'\n'
  prompt+="     - Files this agent owns (glob patterns)"$'\n'
  prompt+="     - Dependencies on other agents"$'\n\n'

  prompt+="4. Create .supercode/plan.json -- machine-readable plan:"$'\n'
  prompt+='   ```json'$'\n'
  prompt+='   {'$'\n'
  prompt+='     "task": "the user request",'$'\n'
  prompt+='     "project_type": "detected type",'$'\n'
  prompt+='     "agents": ['$'\n'
  prompt+='       {'$'\n'
  prompt+='         "role": "backend",'$'\n'
  prompt+='         "task": "specific task for this agent",'$'\n'
  prompt+='         "ownership": ["src/api/**", "src/services/**"],'$'\n'
  prompt+='         "depends_on": []'$'\n'
  prompt+='       }'$'\n'
  prompt+='     ]'$'\n'
  prompt+='   }'$'\n'
  prompt+='   ```'$'\n\n'

  prompt+="IMPORTANT:"$'\n'
  prompt+="- Do NOT write any implementation code. Only planning documents."$'\n'
  prompt+="- Be specific about file paths, function names, and data shapes."$'\n'
  prompt+="- Inspect the existing codebase first to understand the project structure."$'\n'
  prompt+="- After creating all files, say: PLANNING COMPLETE -- review the files in .supercode/ then run 'supercode dispatch' to start the agents."$'\n'

  (
    sleep "$BOOT_DELAY"
    _send_multiline_to_pane "$brain_pid" "$prompt"
  ) >/dev/null 2>&1 &
  disown || true

  ok "Planning session started. Brain will create spec, contracts, and agent assignments."
  info "After review, run ${C_BOLD}supercode dispatch${C_RESET} to launch the agents."

  if [[ -t 0 && -t 1 ]]; then
    info "Attaching... (detach with ${C_BOLD}Ctrl-b d${C_RESET})"
    exec tmux attach -t "$SESSION_NAME"
  else
    info "Attach from a terminal with: ${C_BOLD}supercode attach${C_RESET}"
  fi
}
