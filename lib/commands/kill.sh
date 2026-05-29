#!/usr/bin/env bash
# Kill agent panes (brain kept alive). Use --force to kill everything.

cmd_kill() {
  require_repo
  local force=0
  while (( $# )); do
    case "$1" in
      -f|--force) force=1; shift ;;
      *)          shift ;;
    esac
  done

  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    warn "no session '$SESSION_NAME' running"
    return
  fi

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")

  if [[ -n "$brain_id" && $force -eq 0 ]]; then
    local killed=0
    while read -r pid; do
      [[ "$pid" == "$brain_id" ]] && continue
      tmux kill-pane -t "$pid" 2>/dev/null || true
      ((++killed))
    done < <(tmux list-panes -t "$SESSION_NAME:0" -F '#{pane_id}' 2>/dev/null)
    ok "killed $killed agent pane(s) — brain kept alive (use --force to kill everything)"
  else
    tmux kill-session -t "$SESSION_NAME"
    ok "killed session '$SESSION_NAME' (worktrees still on disk -- run 'supercode clean' to remove)"
  fi
}
