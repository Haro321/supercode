#!/usr/bin/env bash
# Send a message to a specific agent (multiline-safe).

cmd_tell() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"
  local n=${1:-}; shift || true
  local msg="${*:-}"
  [[ -n "$n" && -n "$msg" ]] || die 'usage: supercode tell <N> "message"'
  local pidx
  pidx=$(_agent_pane_index "$SESSION_NAME" "$n")
  _send_multiline_to_pane "$SESSION_NAME:0.$pidx" "$msg"
  ok "delivered to agent-$n"
}
