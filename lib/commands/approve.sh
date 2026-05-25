#!/usr/bin/env bash
# Human approval gates for dangerous changes.

cmd_approve() {
  require_repo

  local target=${1:-}
  [[ -n "$target" ]] || die "usage: supercode approve <N|role>  or  supercode reject <N|role> \"reason\""

  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  # Resolve target to agent number
  local agent_n=""
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    agent_n="$target"
  else
    # Find agent by role
    local count
    count=$(session_agent_count)
    for ((i=1; i<=count; i++)); do
      local r
      r=$(session_get_agent "$i" role 2>/dev/null || echo "")
      if [[ "$r" == "$target" ]]; then
        agent_n="$i"
        break
      fi
    done
    [[ -n "$agent_n" ]] || die "no agent found with role '$target'"
  fi

  session_update_agent "$agent_n" "status" "approved"
  local pidx
  pidx=$(_agent_pane_index "$SESSION_NAME" "$agent_n")
  _send_multiline_to_pane "$SESSION_NAME:0.$pidx" "APPROVED: You may proceed with your current approach."
  ok "approved agent-$agent_n"
}

cmd_reject() {
  require_repo

  local target=${1:-}; shift || true
  local reason="${*:-}"
  [[ -n "$target" ]] || die "usage: supercode reject <N|role> \"reason\""

  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local agent_n=""
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    agent_n="$target"
  else
    local count
    count=$(session_agent_count)
    for ((i=1; i<=count; i++)); do
      local r
      r=$(session_get_agent "$i" role 2>/dev/null || echo "")
      if [[ "$r" == "$target" ]]; then
        agent_n="$i"
        break
      fi
    done
    [[ -n "$agent_n" ]] || die "no agent found with role '$target'"
  fi

  session_update_agent "$agent_n" "status" "rejected"
  local msg="REJECTED: $reason"
  [[ -z "$reason" ]] && msg="REJECTED: Your current approach was rejected. Stop and wait for further instructions."
  local pidx
  pidx=$(_agent_pane_index "$SESSION_NAME" "$agent_n")
  _send_multiline_to_pane "$SESSION_NAME:0.$pidx" "$msg"
  ok "rejected agent-$agent_n${reason:+ -- $reason}"
}
