#!/usr/bin/env bash
# Dispatch agents based on a plan (from Brain) or preset/roles.

cmd_dispatch() {
  require_repo

  local preset=""
  local roles_str=""
  local task_override=""

  while (( $# )); do
    case "$1" in
      --preset)  shift; preset="${1:-}"; shift ;;
      --roles)   shift; roles_str="${1:-}"; shift ;;
      *)         task_override="$task_override $1"; shift ;;
    esac
  done
  task_override="${task_override# }"

  local sc_dir
  sc_dir="$(_sc_dir_path)"
  local plan_file="$sc_dir/plan.json"

  # Determine roles: CLI args > plan.json > default
  local -a roles=()
  local -a tasks=()
  local -a deps=()  # per-agent dependency list (comma-separated)

  if [[ -n "$preset" ]]; then
    IFS=',' read -ra roles <<< "$(resolve_preset "$preset")"
    for role in "${roles[@]}"; do
      tasks+=("$task_override")
      deps+=("")
    done
  elif [[ -n "$roles_str" ]]; then
    IFS=',' read -ra roles <<< "$(parse_roles "$roles_str")"
    for role in "${roles[@]}"; do
      tasks+=("$task_override")
      deps+=("")
    done
  elif [[ -f "$plan_file" ]] && command -v jq >/dev/null 2>&1; then
    info "Reading plan from $plan_file"
    local agent_count
    agent_count=$(jq '.agents | length' "$plan_file" 2>/dev/null || echo 0)
    if (( agent_count == 0 )); then
      die "plan.json has no agents defined. Re-run 'supercode plan' or specify --preset/--roles."
    fi
    for ((i=0; i<agent_count; i++)); do
      local role task dep_list
      role=$(jq -r ".agents[$i].role" "$plan_file" 2>/dev/null || echo "worker")
      task=$(jq -r ".agents[$i].task" "$plan_file" 2>/dev/null || echo "")
      dep_list=$(jq -r '(.agents['"$i"'].depends_on // []) | join(",")' "$plan_file" 2>/dev/null || echo "")
      roles+=("$role")
      tasks+=("$task")
      deps+=("$dep_list")
    done
  else
    die "no plan found. Run 'supercode plan' first, or use --preset/--roles."
  fi

  local n=${#roles[@]}
  [[ $n -ge $MIN_AGENTS ]] || die "need at least $MIN_AGENTS agents (got $n roles)"
  [[ $n -le $MAX_AGENTS ]] || die "max $MAX_AGENTS agents (got $n roles)"

  # Detect existing Brain-only session (in-place dispatch)
  local inplace=0
  local brain_pid=""
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    local existing_pane_count
    existing_pane_count=$(tmux list-panes -t "$SESSION_NAME:0" 2>/dev/null | wc -l)
    if (( existing_pane_count <= 1 )); then
      inplace=1
      brain_pid=$(_brain_pane_id "$SESSION_NAME")
      [[ -n "$brain_pid" ]] || brain_pid=$(tmux display-message -t "$SESSION_NAME:0.0" -p '#{pane_id}')
    else
      die "session '$SESSION_NAME' already has workers. Kill it first."
    fi
  fi

  local base_ref
  base_ref="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  [[ "$base_ref" == "HEAD" ]] && base_ref="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  local stamp
  stamp="$(date +%s)"

  # Ensure spec files are committed so worktrees see them
  if [[ -d "$sc_dir" ]]; then
    if [[ -n "$(git -C "$REPO_ROOT" ls-files --others --exclude-standard "$SUPERCODE_DIR" 2>/dev/null)" ]] \
       || [[ -n "$(git -C "$REPO_ROOT" diff --name-only "$SUPERCODE_DIR" 2>/dev/null)" ]]; then
      git -C "$REPO_ROOT" add "$SUPERCODE_DIR/"
      git -C "$REPO_ROOT" -c user.name='supercode' -c user.email='supercode@local' \
        commit -m "supercode: planning docs ($(date '+%Y-%m-%d %H:%M:%S'))" --no-verify >/dev/null
      ok "committed .supercode/ planning docs so agents can see them"
    fi
  fi

  info "Repo:        ${C_BOLD}$REPO_NAME${C_RESET}"
  info "Base branch: ${C_BOLD}$base_ref${C_RESET}"
  info "Agents:      ${C_BOLD}$n${C_RESET} (${roles[*]})"

  mkdir -p "$WORKTREE_BASE"

  # Pre-launch snapshot (skip if already done by Brain session)
  if [[ ! -f "$WORKTREE_BASE/.pre-launch" ]]; then
    local prelaunch_branch
    prelaunch_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
    if [[ "$prelaunch_branch" != "HEAD" ]]; then
      if ! git -C "$REPO_ROOT" diff --quiet 2>/dev/null \
         || ! git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null \
         || [[ -n "$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        git -C "$REPO_ROOT" add -A
        git -C "$REPO_ROOT" -c user.name='supercode' -c user.email='supercode@local' \
          commit -m "supercode: pre-dispatch snapshot ($(date '+%Y-%m-%d %H:%M:%S'))" --no-verify >/dev/null
        ok "snapshotted uncommitted changes"
      fi
      printf "%s\n%s\n" "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$prelaunch_branch" \
        > "$WORKTREE_BASE/.pre-launch"
    fi
  fi

  # Create worktrees
  info "Creating ${C_BOLD}$n${C_RESET} worktrees..."
  local worktrees=()
  local branches=()
  for ((i=0; i<n; i++)); do
    local agent_n=$((i+1))
    local wt="$WORKTREE_BASE/agent-$agent_n"
    local branch="supercode/agent-$agent_n-$stamp"
    if [[ -d "$wt" ]]; then
      assert_safe_worktree_path "$wt"
      git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    fi
    git -C "$REPO_ROOT" worktree add -b "$branch" "$wt" "$base_ref" >/dev/null
    worktrees+=("$wt")
    branches+=("$branch")
    ok "agent-$agent_n (${roles[$i]})  ->  $wt"
  done

  # Initialize shared directory and symlink into each worktree
  shared_dir_init
  for wt in "${worktrees[@]}"; do
    shared_dir_link "$wt"
  done
  ok "shared directory linked into all worktrees"

  # Initialize session state with roles
  session_init "$n" "$base_ref" "$stamp" "${tasks[@]}"
  for ((i=0; i<n; i++)); do
    session_update_agent "$((i+1))" "role" "${roles[$i]}"
  done

  # Compute per-role counters for status file naming (role_1, role_2, ...)
  declare -A _role_counter=()
  local -a role_ns=()
  for ((i=0; i<n; i++)); do
    local r="${roles[$i]}"
    _role_counter[$r]=$(( ${_role_counter[$r]:-0} + 1 ))
    role_ns+=("${_role_counter[$r]}")
  done

  # Set initial status signals (keyed by role_N where N is per-role counter)
  for ((i=0; i<n; i++)); do
    local agent_n=$((i+1))
    local role_n="${role_ns[$i]}"
    local dep_str="${deps[$i]}"
    if [[ -n "$dep_str" ]]; then
      signal_write "${roles[$i]}" "waiting" "waiting on: $dep_str" "$role_n" "$agent_n"
    else
      signal_write "${roles[$i]}" "working" "" "$role_n" "$agent_n"
    fi
  done

  # Initialize ownership from roles
  ownership_init_from_roles "${roles[@]}"

  # Build tmux layout
  if (( inplace )); then
    # Add worker panes to existing Brain session
    local -a worker_pids=()
    for ((i=0; i<n; i++)); do
      tmux split-window -t "$SESSION_NAME:0" -c "${worktrees[$i]}"
      local new_pid
      new_pid=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')
      worker_pids+=("$new_pid")
      tmux select-layout -t "$SESSION_NAME:0" tiled >/dev/null 2>&1 || true
    done
    tmux select-layout -t "$SESSION_NAME:0" tiled >/dev/null
  else
    info "Launching tmux session..."
    tmux new-session -d -s "$SESSION_NAME" -n agents -c "${worktrees[0]}"
    _build_grid "$n" "${worktrees[@]}"
  fi

  apply_tmux_theme "$SESSION_NAME"

  tmux set-hook -t "$SESSION_NAME" client-resized \
    "run-shell '$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0") __rebalance $SESSION_NAME'" \
    >/dev/null 2>&1 || true

  local logdir="$WORKTREE_BASE/logs"
  mkdir -p "$logdir"

  local claude_cmd="clear && claude ${SUPERCODE_CLAUDE_ARGS:-}"
  local all_roles_str="${roles[*]}"

  # Boot workers with role-specific prompts
  for ((i=0; i<n; i++)); do
    local agent_n=$((i+1))
    local pid="${worker_pids[$i]}"
    local role="${roles[$i]}"
    local task="${tasks[$i]}"
    tmux select-pane -t "$pid" -T "$role (agent-$agent_n)"
    _set_pane_label "$pid" "$role" "$agent_n"
    tmux send-keys -t "$pid" "$claude_cmd" Enter
    tmux pipe-pane -t "$pid" -o "cat >> '$logdir/agent-$agent_n.log'" 2>/dev/null || true

    local ownership
    ownership=$(ownership_get "$role" 2>/dev/null || echo "")
    local agent_deps="${deps[$i]}"
    local role_n="${role_ns[$i]}"
    local role_prompt
    role_prompt=$(_build_role_prompt "$role" "$task" "$all_roles_str" "$ownership" "$agent_deps" "$role_n" "$agent_n")
    (
      sleep "$BOOT_DELAY"
      _send_multiline_to_pane "$pid" "$role_prompt"
    ) &
  done

  if (( inplace )); then
    # Brain is already running — don't restart claude, don't send prompt
    # Worker prompts are backgrounded and will arrive after BOOT_DELAY
    disown 2>/dev/null || true
    _do_rebalance "$SESSION_NAME" >/dev/null 2>&1 || true
    ok "Dispatched $n agents: ${roles[*]}"
    ok "Agents will receive their tasks in ${BOOT_DELAY}s."
  else
    # Fresh brain — start claude and send dispatch prompt
    tmux send-keys -t "$brain_pid" "$claude_cmd" Enter
    tmux pipe-pane -t "$brain_pid" -o "cat >> '$logdir/brain.log'" 2>/dev/null || true

    local task_desc="${task_override:-$(jq -r '.task // ""' "$plan_file" 2>/dev/null || echo "")}"
    local brain_prompt
    brain_prompt=$(_build_role_dispatch_prompt "$n" "$task_desc" "${roles[@]}")
    (
      sleep "$BOOT_DELAY"
      _send_multiline_to_pane "$brain_pid" "$brain_prompt"
    ) &

    wait
    disown 2>/dev/null || true

    _do_rebalance "$SESSION_NAME" >/dev/null 2>&1 || true

    ok "Dispatched $n role-based agents + brain."

    if [[ -t 0 && -t 1 ]]; then
      info "Attaching... (detach with ${C_BOLD}Ctrl-b d${C_RESET})"
      exec tmux attach -t "$SESSION_NAME"
    else
      info "Attach from a terminal with: ${C_BOLD}supercode attach${C_RESET}"
    fi
  fi
}
