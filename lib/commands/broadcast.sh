#!/usr/bin/env bash
# Send a message to all agents (multiline-safe).

cmd_broadcast() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"
  local msg="${*:-}"
  [[ -n "$msg" ]] || die 'usage: supercode broadcast "message"'
  local n=0
  while read -r pidx; do
    n=$(( n + 1 ))
    _send_multiline_to_pane "$SESSION_NAME:0.$pidx" "$msg"
    ok "-> agent-$n"
  done < <(_agent_pane_indices "$SESSION_NAME")
}
