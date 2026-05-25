#!/usr/bin/env bash
# Launch a supercode session.

cmd_start() {
  require_repo

  local DIRECT_MODE=0
  local AGENT_COUNT=""
  local SNAPSHOT_MODE="${SUPERCODE_SNAPSHOT:-commit}"
  local PRESET=""
  local ROLES_STR=""
  local tasks=()

  while (( $# )); do
    case "$1" in
      --direct)   DIRECT_MODE=1; shift ;;
      --agents)   shift; AGENT_COUNT="${1:-}"; shift ;;
      --snapshot) shift; SNAPSHOT_MODE="${1:-commit}"; shift ;;
      --preset)   shift; PRESET="${1:-}"; shift ;;
      --roles)    shift; ROLES_STR="${1:-}"; shift ;;
      *)          tasks+=("$1"); shift ;;
    esac
  done

  # If preset/roles specified, delegate to dispatch
  if [[ -n "$PRESET" || -n "$ROLES_STR" ]]; then
    local dispatch_args=()
    [[ -n "$PRESET" ]] && dispatch_args+=(--preset "$PRESET")
    [[ -n "$ROLES_STR" ]] && dispatch_args+=(--roles "$ROLES_STR")
    dispatch_args+=("${tasks[@]}")
    cmd_dispatch "${dispatch_args[@]}"
    return
  fi

  local task_count=${#tasks[@]}

  case "$SNAPSHOT_MODE" in
    commit|stash|none) ;;
    *) die "invalid --snapshot mode: $SNAPSHOT_MODE (use: commit, stash, none)" ;;
  esac

  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    die "session '$SESSION_NAME' is already running. Use 'supercode attach' or 'supercode kill'."
  fi

  local base_ref
  base_ref="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  [[ "$base_ref" == "HEAD" ]] && base_ref="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  local stamp
  stamp="$(date +%s)"

  mkdir -p "$WORKTREE_BASE"

  # Pre-launch snapshot
  local prelaunch_branch
  prelaunch_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  if [[ "$prelaunch_branch" != "HEAD" ]]; then
    local has_changes=0
    if ! git -C "$REPO_ROOT" diff --quiet 2>/dev/null \
       || ! git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null \
       || [[ -n "$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
      has_changes=1
    fi

    if (( has_changes )); then
      case "$SNAPSHOT_MODE" in
        commit)
          git -C "$REPO_ROOT" add -A
          git -C "$REPO_ROOT" -c user.name='supercode' -c user.email='supercode@local' \
            commit -m "supercode: pre-launch snapshot ($(date '+%Y-%m-%d %H:%M:%S'))" --no-verify >/dev/null
          ok "snapshotted uncommitted changes on $prelaunch_branch ($(git -C "$REPO_ROOT" rev-parse --short HEAD))"
          ;;
        stash)
          git -C "$REPO_ROOT" stash push -m "supercode: pre-launch stash ($(date '+%Y-%m-%d %H:%M:%S'))" >/dev/null
          ok "stashed uncommitted changes (restore with: git stash pop)"
          ;;
        none)
          warn "uncommitted changes present -- proceeding without snapshot (--snapshot none)"
          ;;
      esac
    else
      ok "clean working tree -- recorded $prelaunch_branch @ $(git -C "$REPO_ROOT" rev-parse --short HEAD) as rollback point"
    fi
    printf "%s\n%s\n" "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$prelaunch_branch" \
      > "$WORKTREE_BASE/.pre-launch"
  else
    warn "detached HEAD -- skipping pre-launch snapshot (no rollback point recorded)"
  fi

  if (( DIRECT_MODE )); then
    _start_direct_mode "$AGENT_COUNT" "$stamp" "$base_ref" "$task_count" "${tasks[@]}"
  else
    _start_brain_mode "$base_ref" "$task_count" "${tasks[@]}"
  fi
}

# Default mode: Brain-only interactive session
_start_brain_mode() {
  local base_ref=$1 task_count=$2
  shift 2
  local tasks=("$@")

  info "Repo:        ${C_BOLD}$REPO_NAME${C_RESET}"
  info "Base branch: ${C_BOLD}$base_ref${C_RESET}"
  info "Mode:        ${C_BOLD}Brain (interactive)${C_RESET}"

  ensure_sc_dir
  shared_dir_init

  info "Launching Brain session ${C_BOLD}$SESSION_NAME${C_RESET}..."

  tmux new-session -d -s "$SESSION_NAME" -n brain -c "$REPO_ROOT"
  local brain_pid
  brain_pid=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')
  tmux set-option -wq -t "$SESSION_NAME:0" "@brain-pane" "$brain_pid"
  tmux select-pane -t "$brain_pid" -T "brain"

  apply_tmux_theme "$SESSION_NAME"

  local logdir="$WORKTREE_BASE/logs"
  mkdir -p "$logdir"

  local claude_cmd="clear && claude ${SUPERCODE_CLAUDE_ARGS:-}"
  tmux send-keys -t "$brain_pid" "$claude_cmd" Enter
  tmux pipe-pane -t "$brain_pid" -o "cat >> '$logdir/brain.log'" 2>/dev/null || true

  local prompt
  if (( task_count > 0 )); then
    prompt=$(_build_interactive_brain_prompt "${tasks[@]}")
  else
    prompt=$(_build_interactive_brain_prompt)
  fi

  (
    sleep "$BOOT_DELAY"
    _send_multiline_to_pane "$brain_pid" "$prompt"
  ) >/dev/null 2>&1 &
  disown || true

  ok "Brain launched. Talk to it to plan your project."
  info "When the plan is ready, run ${C_BOLD}supercode dispatch${C_RESET} to launch agents."

  if [[ -t 0 && -t 1 ]]; then
    info "Attaching... (detach with ${C_BOLD}Ctrl-b d${C_RESET})"
    exec tmux attach -t "$SESSION_NAME"
  else
    info "Attach from a terminal with: ${C_BOLD}supercode attach${C_RESET}"
  fi
}

# Direct mode: N workers with tasks, no brain
_start_direct_mode() {
  local AGENT_COUNT=$1 stamp=$2 base_ref=$3 task_count=$4
  shift 4
  local tasks=("$@")

  local n
  if [[ -n "$AGENT_COUNT" ]]; then
    [[ "$AGENT_COUNT" =~ ^[0-9]+$ ]] || die "--agents must be a number (got '$AGENT_COUNT')"
    n=$AGENT_COUNT
    [[ $n -ge $MIN_AGENTS ]] || die "--agents minimum is $MIN_AGENTS (got $n)"
    [[ $n -le $MAX_AGENTS ]] || die "--agents maximum is $MAX_AGENTS (got $n)"
  else
    n=$task_count
    [[ $n -ge $MIN_AGENTS ]] || die "--direct needs at least $MIN_AGENTS tasks (got $n)"
    [[ $n -le $MAX_AGENTS ]] || die "max $MAX_AGENTS agents (got $n)"
  fi

  info "Repo:        ${C_BOLD}$REPO_NAME${C_RESET}"
  info "Base branch: ${C_BOLD}$base_ref${C_RESET}"
  info "Agents:      ${C_BOLD}$n${C_RESET}"
  info "Mode:        ${C_BOLD}Direct${C_RESET}"

  info "Creating ${C_BOLD}$n${C_RESET} worktrees..."

  local worktrees=()
  local branches=()
  for i in $(seq 1 $n); do
    local wt="$WORKTREE_BASE/agent-$i"
    local branch="supercode/agent-$i-$stamp"

    if [[ -d "$wt" ]]; then
      assert_safe_worktree_path "$wt"
      git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    fi

    git -C "$REPO_ROOT" worktree add -b "$branch" "$wt" "$base_ref" >/dev/null
    worktrees+=("$wt")
    branches+=("$branch")
    ok "agent-$i  ->  $wt  ${C_DIM}($branch)${C_RESET}"
  done

  session_init "$n" "$base_ref" "$stamp" "${tasks[@]}"

  info "Launching tmux session ${C_BOLD}$SESSION_NAME${C_RESET} ($n panes)..."

  tmux new-session -d -s "$SESSION_NAME" -n agents -c "${worktrees[0]}"

  _build_direct_layout "$n" "${worktrees[@]}"
  apply_tmux_theme "$SESSION_NAME"

  tmux set-hook -t "$SESSION_NAME" client-resized \
    "run-shell '$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0") __rebalance $SESSION_NAME'" \
    >/dev/null 2>&1 || true

  local logdir="$WORKTREE_BASE/logs"
  mkdir -p "$logdir"
  local claude_cmd="clear && claude ${SUPERCODE_CLAUDE_ARGS:-}"

  for ((idx=0; idx<n; idx++)); do
    local pane="$SESSION_NAME:0.$idx"
    local agent_n=$((idx+1))
    tmux select-pane -t "$pane" -T "agent-$agent_n"
    local lbl; lbl=$(_short_label "${tasks[$idx]}")
    _set_pane_label "$pane" "$lbl" "$agent_n"
    tmux send-keys -t "$pane" "$claude_cmd" Enter
    tmux pipe-pane -t "$pane" -o "cat >> '$logdir/agent-$agent_n.log'" 2>/dev/null || true
  done
  (
    sleep "$BOOT_DELAY"
    for ((idx=0; idx<n; idx++)); do
      local pane="$SESSION_NAME:0.$idx"
      _send_multiline_to_pane "$pane" "${tasks[$idx]}"
    done
  ) >/dev/null 2>&1 &
  disown || true
  ok "Direct mode: $n agents launched, tasks dispatched in ${BOOT_DELAY}s."

  if [[ -t 0 && -t 1 ]]; then
    info "Attaching... (detach with ${C_BOLD}Ctrl-b d${C_RESET})"
    exec tmux attach -t "$SESSION_NAME"
  else
    info "Attach from a terminal with: ${C_BOLD}supercode attach${C_RESET}"
  fi
}

# Build layouts for direct mode (no brain)
_build_direct_layout() {
  local n=$1; shift
  local worktrees=("$@")

  if [[ $n -eq 5 ]]; then
    tmux split-window -t "$SESSION_NAME:0" -v -c "${worktrees[3]}"
    tmux split-window -t "$SESSION_NAME:0.0" -h -c "${worktrees[1]}"
    tmux split-window -t "$SESSION_NAME:0.1" -h -c "${worktrees[2]}"
    tmux split-window -t "$SESSION_NAME:0.3" -h -c "${worktrees[4]}"
  elif [[ $n -eq 4 ]]; then
    tmux split-window -t "$SESSION_NAME:0" -v -c "${worktrees[2]}"
    tmux split-window -t "$SESSION_NAME:0.0" -h -c "${worktrees[1]}"
    tmux split-window -t "$SESSION_NAME:0.2" -h -c "${worktrees[3]}"
    tmux select-layout -t "$SESSION_NAME:0" tiled >/dev/null
  elif [[ $n -eq 3 ]]; then
    for ((idx=1; idx<n; idx++)); do
      tmux split-window -t "$SESSION_NAME:0" -h -c "${worktrees[$idx]}"
    done
    tmux select-layout -t "$SESSION_NAME:0" even-horizontal >/dev/null
  elif [[ $n -eq 2 ]]; then
    tmux split-window -t "$SESSION_NAME:0" -h -c "${worktrees[1]}"
  else
    for ((idx=1; idx<n; idx++)); do
      tmux split-window -t "$SESSION_NAME:0" -c "${worktrees[$idx]}"
      tmux select-layout -t "$SESSION_NAME:0" tiled >/dev/null
    done
    tmux select-layout -t "$SESSION_NAME:0" tiled >/dev/null
  fi
}
