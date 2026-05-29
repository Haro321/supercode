#!/usr/bin/env bash
# Tmux helpers: pane communication, identification, and theme application.

sq_escape() {
  local s=$1
  printf "%s" "${s//\'/\'\\\'\'}"
}

_send_multiline_to_pane() {
  local pane=$1
  local text=$2
  local buf="sc-prompt-$$-$RANDOM"
  printf '%s' "$text" | tmux load-buffer -b "$buf" -
  tmux paste-buffer -b "$buf" -t "$pane"
  sleep 0.2
  tmux send-keys -t "$pane" Enter
  tmux delete-buffer -b "$buf" 2>/dev/null || true
}

_brain_pane_id() {
  tmux show-option -wqv -t "$1:0" "@brain-pane" 2>/dev/null || true
}

_agent_pane_indices() {
  local session=$1
  local brain_id
  brain_id=$(_brain_pane_id "$session")
  tmux list-panes -t "$session:0" -F '#{pane_id} #{pane_index}' 2>/dev/null \
    | awk -v b="$brain_id" '$1!=b {print $2}' \
    | sort -n
}

_agent_pane_index() {
  local session=$1 n=$2
  [[ "$n" =~ ^[0-9]+$ ]] || die "expected agent number, got '$n'"
  local brain_id
  brain_id=$(_brain_pane_id "$session")
  # Build list of non-brain pane indices in order
  local -a agent_panes=()
  while IFS=' ' read -r pid pidx; do
    [[ "$pid" == "$brain_id" ]] && continue
    agent_panes+=("$pidx")
  done < <(tmux list-panes -t "$session:0" -F '#{pane_id} #{pane_index}' 2>/dev/null)
  local target_idx=$(( n - 1 ))
  (( target_idx >= 0 && target_idx < ${#agent_panes[@]} )) \
    || die "no agent $n in session (have ${#agent_panes[@]} agents)"
  printf '%s' "${agent_panes[$target_idx]}"
}

# Build the 2-row grid for brain-mediated mode: n workers + brain
_build_grid() {
  local n=$1; shift
  local worktrees=("$@")
  local top_row=$(( (n + 1) / 2 ))
  local bot_row=$(( n - top_row + 1 ))  # +1 for brain

  local p1
  p1=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')

  # The first bottom-row pane becomes worker_pids[top_row] (agent top_row+1),
  # so it must start in its own worktree, worktrees[top_row] -- not the last
  # top-row worker's worktree.
  tmux split-window -t "$p1" -v -c "${worktrees[$top_row]:-$REPO_ROOT}"
  local bot_first
  bot_first=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')

  local prev="$p1"
  local -a top_pids=("$p1")
  for ((i=1; i<top_row; i++)); do
    tmux split-window -t "$prev" -h -c "${worktrees[$i]}"
    prev=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')
    top_pids+=("$prev")
  done

  local -a bot_pids=("$bot_first")
  prev="$bot_first"
  for ((i=1; i<bot_row-1; i++)); do
    local wt_idx=$((top_row + i))
    tmux split-window -t "$prev" -h -c "${worktrees[$wt_idx]:-$REPO_ROOT}"
    prev=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')
    bot_pids+=("$prev")
  done
  tmux split-window -t "$prev" -h -c "$REPO_ROOT"
  local pb
  pb=$(tmux display-message -t "$SESSION_NAME:0" -p '#{pane_id}')

  worker_pids=()
  for pid in "${top_pids[@]}"; do worker_pids+=("$pid"); done
  for pid in "${bot_pids[@]}"; do worker_pids+=("$pid"); done
  brain_pid="$pb"

  tmux set-option -wq -t "$SESSION_NAME:0" "@brain-pane" "$brain_pid"
  tmux select-pane -t "$brain_pid" -T "brain"
  tmux select-layout -t "$SESSION_NAME:0" tiled >/dev/null
}

apply_tmux_theme() {
  local session=$1

  tmux set-option -w -t "$session:0" pane-border-status top >/dev/null 2>&1 || true
  tmux set-option -w -t "$session:0" pane-border-lines heavy >/dev/null 2>&1 || true
  tmux set-option -w -t "$session:0" pane-border-indicators both >/dev/null 2>&1 || true
  tmux set-option -w -t "$session:0" pane-border-style 'fg=colour240' >/dev/null 2>&1 || true
  tmux set-option -w -t "$session:0" pane-active-border-style 'fg=colour39,bold' >/dev/null 2>&1 || true
  tmux set-option -w -t "$session:0" window-style 'bg=colour234,fg=colour252' >/dev/null 2>&1 || true
  tmux set-option -w -t "$session:0" window-active-style 'bg=colour234,fg=colour252' >/dev/null 2>&1 || true

  tmux set-option -w -t "$session:0" pane-border-format \
    '#{?#{&&:#{!=:#{@brain-pane},},#{==:#{pane_id},#{@brain-pane}}},#{?#{<:#{pane_width},35},- #[bg=colour214\,fg=colour234\,bold] SUPERBRAIN #[default] ,#{?#{<:#{pane_width},55},------ #[bg=colour214\,fg=colour234\,bold] SUPERBRAIN #[default] ,#{?#{<:#{pane_width},85},--------------- #[bg=colour214\,fg=colour234\,bold] SUPERBRAIN #[default] ,#{?#{<:#{pane_width},120},------------------------- #[bg=colour214\,fg=colour234\,bold] SUPERBRAIN #[default] ,------------------------------------- #[bg=colour214\,fg=colour234\,bold] SUPERBRAIN #[default] }}}}, #{?pane_active,#[fg=colour120]>,#[fg=colour240]o} #[fg=colour#{?#{!=:#{@accent},},#{@accent},39}#{?pane_active,\,bold,}]#{e|+:#{pane_index},1}#[nobold] #[fg=colour244].#[fg=#{?pane_active,colour252,colour244}#{?pane_active,\,bold,}] #{?#{!=:#{@label},},#{=27:#{@label}},#{?#{<:#{pane_width},35},#{=23:#{pane_title}},#{?#{<:#{pane_width},55},#{=43:#{pane_title}},#{?#{<:#{pane_width},85},#{=73:#{pane_title}},#{?#{<:#{pane_width},120},#{=105:#{pane_title}},#{pane_title}}}}}}#[default] }' \
    >/dev/null 2>&1 || true

  tmux set-option -t "$session" mouse on >/dev/null 2>&1 || true

  tmux set-option -t "$session" status on >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-position bottom >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-interval 2 >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-justify centre >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-style 'bg=colour234,fg=colour252' >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-left-length 60 >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-right-length 60 >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-left \
    '#[bg=colour99,fg=colour234,bold] supercode #[bg=colour238,fg=colour99]>#[bg=colour238,fg=colour252] #{session_name} #[bg=colour234,fg=colour238]> ' >/dev/null 2>&1 || true
  tmux set-option -t "$session" status-right \
    '#[fg=colour238]<#[bg=colour238,fg=colour252] #(whoami)@#h #[fg=colour120]<#[bg=colour120,fg=colour234,bold] %H:%M ' >/dev/null 2>&1 || true
  tmux set-option -t "$session" window-status-separator '' >/dev/null 2>&1 || true
  tmux set-option -t "$session" window-status-format '#[bg=colour234,fg=colour244]  #I.#W  ' >/dev/null 2>&1 || true
  tmux set-option -t "$session" window-status-current-format \
    '#[bg=colour234,fg=colour39]>#[bg=colour39,fg=colour234,bold] #I.#W #[bg=colour234,fg=colour39]<' >/dev/null 2>&1 || true

  tmux set-option -t "$session" message-style 'bg=colour39,fg=colour234,bold' >/dev/null 2>&1 || true
  tmux set-option -t "$session" message-command-style 'bg=colour99,fg=colour234,bold' >/dev/null 2>&1 || true
}
