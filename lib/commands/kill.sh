#!/usr/bin/env bash
# Kill the tmux session (worktrees kept).

cmd_kill() {
  require_repo
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME"
    ok "killed session '$SESSION_NAME' (worktrees still on disk -- run 'supercode clean' to remove)"
  else
    warn "no session '$SESSION_NAME' running"
  fi
}
