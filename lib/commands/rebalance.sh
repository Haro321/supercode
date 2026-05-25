#!/usr/bin/env bash
# Rebalance tmux pane layout.

_do_rebalance() {
  local session="${1:?usage: _do_rebalance <session>}"
  local win="$session:0"
  local n
  n=$(tmux list-panes -t "$win" 2>/dev/null | wc -l) || return 0
  [[ "$n" -ge 2 ]] || return 0

  local win_w win_h
  win_w=$(tmux display-message -t "$win" -p '#{window_width}')
  win_h=$(tmux display-message -t "$win" -p '#{window_height}')

  local -a rows
  mapfile -t rows < <(tmux list-panes -t "$win" -F '#{pane_top}' | sort -un)
  local row_count=${#rows[@]}
  (( row_count >= 1 )) || return 0

  local r y w i pid
  for ((r=0; r<row_count; r++)); do
    y="${rows[$r]}"
    local -a row_panes
    mapfile -t row_panes < <(tmux list-panes -t "$win" -F '#{pane_top} #{pane_left} #{pane_id}' \
      | awk -v y="$y" '$1==y {print $2" "$3}' | sort -n | awk '{print $2}')
    local rn=${#row_panes[@]}
    if (( rn > 1 )); then
      w=$(( win_w / rn ))
      for ((i=0; i<rn-1; i++)); do
        tmux resize-pane -t "${row_panes[$i]}" -x "$w" 2>/dev/null || true
      done
    fi
  done

  if (( row_count > 1 )); then
    local brain_pane_id
    brain_pane_id=$(_brain_pane_id "$session")
    local brain_row=-1
    if [[ -n "$brain_pane_id" ]]; then
      local brain_top
      brain_top=$(tmux list-panes -t "$win" -F '#{pane_id} #{pane_top}' \
        | awk -v b="$brain_pane_id" '$1==b {print $2; exit}')
      for ((r=0; r<row_count; r++)); do
        [[ "${rows[$r]}" == "$brain_top" ]] && brain_row=$r
      done
    fi

    local -a row_heights
    if (( brain_row >= 0 )); then
      local brain_h=$(( win_h * 44 / 100 ))
      local other_h=$(( (win_h - brain_h - row_count) / (row_count - 1) ))
      (( other_h < 3 )) && other_h=3
      for ((r=0; r<row_count; r++)); do
        if (( r == brain_row )); then row_heights[$r]=$brain_h
        else                          row_heights[$r]=$other_h
        fi
      done
    else
      local row_h=$(( win_h / row_count ))
      for ((r=0; r<row_count; r++)); do row_heights[$r]=$row_h; done
    fi

    for ((r=0; r<row_count-1; r++)); do
      y="${rows[$r]}"
      pid=$(tmux list-panes -t "$win" -F '#{pane_top} #{pane_id}' | awk -v y="$y" '$1==y {print $2; exit}')
      tmux resize-pane -t "$pid" -y "${row_heights[$r]}" 2>/dev/null || true
    done
  fi
}

cmd_rebalance() {
  _do_rebalance "$@"
}
