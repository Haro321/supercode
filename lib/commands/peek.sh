#!/usr/bin/env bash
# View agent screen content.

cmd_peek() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"
  local target=${1:-}
  [[ -n "$target" ]] || die "usage: supercode peek <N|all> [--history [LINES]]"
  shift || true

  local history=0 lines=200
  while (( $# )); do
    case "$1" in
      --history)
        history=1; shift
        if [[ "${1:-}" =~ ^[0-9]+$ ]]; then lines=$1; shift; fi
        ;;
      *) shift ;;
    esac
  done

  _peek_one() {
    local n=$1
    local pidx=${2:-}
    [[ -n "$pidx" ]] || pidx=$(_agent_pane_index "$SESSION_NAME" "$n")
    local pane="$SESSION_NAME:0.$pidx"
    local title
    title=$(tmux display-message -t "$pane" -p '#{pane_title}')
    echo "${C_BOLD}-- agent-$n -- ${title}${C_RESET}"
    local wt="$WORKTREE_BASE/agent-$n"
    if [[ -d "$wt" ]]; then
      local gs
      gs=$(git -C "$wt" status --short 2>/dev/null | head -10)
      [[ -n "$gs" ]] && printf "%sgit:%s\n%s\n" "$C_DIM" "$C_RESET" "$gs"
    fi
    if (( history )); then
      tmux capture-pane -p -t "$pane" -S -"$lines" -E -
    else
      tmux capture-pane -p -t "$pane"
    fi
  }

  if [[ "$target" == "all" ]]; then
    local n=0
    while read -r pidx; do
      n=$(( n + 1 ))
      echo
      _peek_one "$n" "$pidx"
    done < <(_agent_pane_indices "$SESSION_NAME")
  else
    _peek_one "$target"
  fi
}
