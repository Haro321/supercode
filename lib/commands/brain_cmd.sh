#!/usr/bin/env bash
# Brain pane management and brain subcommands.

cmd_brain_dispatch() {
  local sub="${1:-}"

  case "$sub" in
    ""|-h|--help)  cmd_brain ;;
    plan)          shift; _brain_sub_plan "$@" ;;
    status)        _brain_sub_status ;;
    reassign)      shift; _brain_sub_reassign "$@" ;;
    unblock)       _brain_sub_unblock ;;
    review)        _brain_sub_review ;;
    summarize)     _brain_sub_summarize ;;
    *)             cmd_brain ;;
  esac
}

cmd_brain() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local brain_id
  if ! brain_id=$(_create_brain_pane "$SESSION_NAME"); then
    warn "brain pane already exists -- focusing it"
    tmux select-pane -t "$brain_id"
    return 0
  fi

  local agent_count
  agent_count=$(( $(tmux list-panes -t "$SESSION_NAME:0" | wc -l) - 1 ))

  local prompt
  prompt=$(_build_posthoc_prompt "$agent_count")
  (
    sleep "$BOOT_DELAY"
    _send_multiline_to_pane "$brain_id" "$prompt"
  ) >/dev/null 2>&1 &
  disown || true

  _do_rebalance "$SESSION_NAME" >/dev/null 2>&1 || true
  _do_rebalance "$SESSION_NAME" >/dev/null 2>&1 || true

  ok "Brain pane added. Orientation prompt arrives in ${BOOT_DELAY}s."
  info "Click the brain pane or use Ctrl-b arrow to focus it."
}

_brain_sub_plan() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")
  [[ -n "$brain_id" ]] || die "no brain pane -- run 'supercode brain' first"

  local msg="Create a detailed plan for the current work. Write the following files:"$'\n'
  msg+="1. .supercode/SPEC.md -- requirements and acceptance criteria"$'\n'
  msg+="2. .supercode/CONTRACTS.md -- shared API contracts, types, and interfaces"$'\n'
  msg+="3. .supercode/STATUS.md -- current status of each agent"$'\n'
  msg+="Inspect the codebase first. Be specific about file paths and data shapes."

  _send_multiline_to_pane "$brain_id" "$msg"
  ok "asked brain to create planning docs"
}

_brain_sub_status() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")
  [[ -n "$brain_id" ]] || die "no brain pane"

  _send_multiline_to_pane "$brain_id" "Run 'supercode peek all' to check all agents. Then update .supercode/STATUS.md with current progress. Report a summary of who is done, who is working, and who is blocked."
  ok "asked brain for status update"
}

_brain_sub_reassign() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local target=${1:-}; shift || true
  local new_task="${*:-}"
  [[ -n "$target" && -n "$new_task" ]] || die "usage: supercode brain reassign <N|role> \"new task\""

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")
  [[ -n "$brain_id" ]] || die "no brain pane"

  _send_multiline_to_pane "$brain_id" "Reassign agent $target to: $new_task. Use 'supercode tell $target ...' to send the new instructions. Update .supercode/STATUS.md."
  ok "asked brain to reassign agent $target"
}

_brain_sub_unblock() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")
  [[ -n "$brain_id" ]] || die "no brain pane"

  _send_multiline_to_pane "$brain_id" "Run 'supercode peek all' to check all agents. Identify any agents that appear stuck, blocked, or making no progress. For each stuck agent, diagnose the issue and send help using 'supercode tell N \"...\"'. Update .supercode/STATUS.md."
  ok "asked brain to unblock stuck agents"
}

_brain_sub_review() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")
  [[ -n "$brain_id" ]] || die "no brain pane"

  _send_multiline_to_pane "$brain_id" "Run 'supercode peek all' and 'supercode diff all' to review what every agent has done. Check whether agents followed the contracts in .supercode/CONTRACTS.md (if it exists). Look for: duplicated work, broken imports between agents, missing tests, security issues. Summarize your findings and recommend fixes."
  ok "asked brain to review all agents"
}

_brain_sub_summarize() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  local brain_id
  brain_id=$(_brain_pane_id "$SESSION_NAME")
  [[ -n "$brain_id" ]] || die "no brain pane"

  _send_multiline_to_pane "$brain_id" "Summarize the current state of the entire session. For each agent: what they were tasked with, what they've done so far, and whether it's complete. Then give an overall project status: what's done, what's remaining, and any risks."
  ok "asked brain for summary"
}
