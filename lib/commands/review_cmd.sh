#!/usr/bin/env bash
# Launch a reviewer agent to inspect all agent diffs.

cmd_review() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"

  [[ -d "$WORKTREE_BASE" ]] && compgen -G "$WORKTREE_BASE/agent-*" >/dev/null \
    || die "no agent worktrees found"

  local current
  current="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

  # Build a summary of what each agent changed
  local changes_summary=""
  while IFS= read -r wt; do
    local agent agent_num branch role stat
    agent=$(basename "$wt")
    agent_num="${agent#agent-}"
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || continue)
    role=$(session_get_agent "$agent_num" role 2>/dev/null || echo "worker")
    stat=$(git -C "$REPO_ROOT" diff --stat "$current...$branch" 2>/dev/null || echo "(no changes)")
    local files
    files=$(git -C "$REPO_ROOT" diff --name-only "$current...$branch" 2>/dev/null || echo "")

    changes_summary+="$agent ($role):"$'\n'
    changes_summary+="  Branch: $branch"$'\n'
    if [[ -n "$files" ]]; then
      changes_summary+="  Files changed:"$'\n'
      echo "$files" | while read -r f; do
        changes_summary+="    $f"$'\n'
      done
      changes_summary+="  Stats: $stat"$'\n'
    else
      changes_summary+="  (no committed changes)"$'\n'
    fi
    changes_summary+=$'\n'
  done < <(_sorted_worktrees)

  # Create or reuse a reviewer pane
  local reviewer_pane=""
  local existing_brain
  existing_brain=$(_brain_pane_id "$SESSION_NAME")

  # Add a new pane for the reviewer
  tmux split-window -t "$SESSION_NAME:0" -v -f -c "$REPO_ROOT"
  local new_idx
  new_idx=$(tmux list-panes -t "$SESSION_NAME:0" -F '#{pane_index}' | sort -n | tail -1)
  reviewer_pane=$(tmux list-panes -t "$SESSION_NAME:0" -F '#{pane_index} #{pane_id}' \
    | awk -v i="$new_idx" '$1==i {print $2; exit}')
  tmux select-pane -t "$reviewer_pane" -T "reviewer"

  local win_h
  win_h=$(tmux display-message -t "$SESSION_NAME:0" -p '#{window_height}')
  tmux resize-pane -t "$reviewer_pane" -y "$(( win_h * 40 / 100 ))"

  local claude_cmd="clear && claude ${SUPERCODE_CLAUDE_ARGS:-}"
  tmux send-keys -t "$reviewer_pane" "$claude_cmd" Enter

  local logdir="$WORKTREE_BASE/logs"
  mkdir -p "$logdir"
  tmux pipe-pane -t "$reviewer_pane" -o "cat >> '$logdir/reviewer.log'" 2>/dev/null || true

  # Build the review prompt
  local prompt=""
  prompt+="You are the REVIEWER agent. Your job is to review ALL changes made by the other agents in this supercode session."$'\n\n'
  prompt+="REVIEW CHECKLIST:"$'\n'
  prompt+="1. Read all diffs: for each agent branch listed below, run 'git diff $current...<branch>' to see the full changes."$'\n'
  prompt+="2. If .supercode/SPEC.md exists, verify the implementation matches the spec requirements."$'\n'
  prompt+="3. If .supercode/CONTRACTS.md exists, verify agents followed the shared interfaces."$'\n'
  prompt+="4. Check for:"$'\n'
  prompt+="   - Duplicated work across agents"$'\n'
  prompt+="   - Broken imports or missing dependencies between agent changes"$'\n'
  prompt+="   - Security issues (injection, XSS, auth bypass, secrets exposure)"$'\n'
  prompt+="   - Missing error handling"$'\n'
  prompt+="   - Missing tests"$'\n'
  prompt+="   - Style inconsistencies"$'\n'
  prompt+="5. Write a structured review to .supercode/REVIEW.md with:"$'\n'
  prompt+="   - A summary line (pass/warn/fail)"$'\n'
  prompt+="   - Per-agent findings (ok / warning / issue)"$'\n'
  prompt+="   - Cross-agent issues (conflicts, duplications, broken contracts)"$'\n'
  prompt+="   - Recommended fixes (which agent should fix what)"$'\n\n'

  prompt+="AGENT CHANGES TO REVIEW:"$'\n'
  prompt+="$changes_summary"$'\n'

  prompt+="IMPORTANT: Do NOT modify any code. Only read, review, and write REVIEW.md."$'\n'
  prompt+="After writing REVIEW.md, summarize your findings aloud so the user can see them."

  (
    sleep "$BOOT_DELAY"
    _send_multiline_to_pane "$reviewer_pane" "$prompt"
  ) >/dev/null 2>&1 &
  disown || true

  _do_rebalance "$SESSION_NAME" >/dev/null 2>&1 || true

  ok "Reviewer launched. It will inspect all agent diffs and write .supercode/REVIEW.md"
}
