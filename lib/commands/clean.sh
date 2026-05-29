#!/usr/bin/env bash
# Kill session and remove worktrees.

cmd_clean() {
  require_repo
  local force=0 dry_run=0
  while (( $# )); do
    case "$1" in
      -f|--force)   force=1; shift ;;
      --dry-run)    dry_run=1; shift ;;
      *)            shift ;;
    esac
  done

  # Pre-flight: scan for unmerged work or uncommitted changes
  if [[ $force -eq 0 && -d "$WORKTREE_BASE" ]]; then
    local blockers=""
    while IFS= read -r wt; do
      local branch unmerged dirty
      branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')
      dirty=""
      if ! git -C "$wt" diff --quiet 2>/dev/null \
         || ! git -C "$wt" diff --cached --quiet 2>/dev/null \
         || [[ -n "$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        dirty="uncommitted"
      fi
      unmerged=0
      [[ -n "$branch" ]] && unmerged=$(_unmerged_count "$branch")
      if [[ -n "$dirty" || "$unmerged" != "0" ]]; then
        blockers+="  $(basename "$wt") ($branch): ${unmerged} unmerged commit(s)${dirty:+, $dirty changes}\n"
      fi
    done < <(_sorted_worktrees)
    if [[ -n "$blockers" ]]; then
      echo "${C_YELLOW}Refusing to clean -- these agents still have work that isn't saved anywhere else:${C_RESET}"
      printf '%b' "$blockers"
      echo ""
      echo "Run ${C_BOLD}supercode save${C_RESET} first, or re-run with ${C_BOLD}--force${C_RESET} to drop everything."
      exit 1
    fi
  fi

  if (( dry_run )); then
    echo "${C_BOLD}Dry run -- would clean:${C_RESET}"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      echo "  kill tmux session '$SESSION_NAME'"
    fi
    if [[ -d "$WORKTREE_BASE" ]]; then
      while IFS= read -r wt; do
        local branch
        branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
        echo "  remove $(basename "$wt") ($branch)"
      done < <(_sorted_worktrees)
    fi
    return 0
  fi

  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    local brain_id
    brain_id=$(_brain_pane_id "$SESSION_NAME")
    if [[ -n "$brain_id" && $force -eq 0 ]]; then
      while read -r pid; do
        [[ "$pid" == "$brain_id" ]] && continue
        tmux kill-pane -t "$pid" 2>/dev/null || true
      done < <(tmux list-panes -t "$SESSION_NAME:0" -F '#{pane_id}' 2>/dev/null)
      ok "killed agent panes (brain kept alive)"
    else
      tmux kill-session -t "$SESSION_NAME"
      ok "killed session '$SESSION_NAME'"
    fi
  fi
  if [[ -d "$WORKTREE_BASE" ]]; then
    while IFS= read -r wt; do
      assert_safe_worktree_path "$wt"
      local branch
      branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
      if ! git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null; then
        assert_safe_worktree_path "$wt"
        rm -rf "$wt"
      fi
      if [[ "$branch" == supercode/* ]]; then
        git -C "$REPO_ROOT" branch -D "$branch" 2>/dev/null || true
      fi
      ok "removed $(basename "$wt") ${C_DIM}($branch)${C_RESET}"
    done < <(_sorted_worktrees)
    # Prune any stale worktree admin entries left in .git/worktrees so a reused
    # agent-N path/branch never hits "already checked out" on the next launch.
    git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
    # Remove logs, session state, shared dir, and the rewind points -- otherwise
    # a stale .pre-launch/.last-save lets a later rollback/unsave reset a branch
    # to a snapshot from this already-cleaned session.
    rm -rf "$WORKTREE_BASE/logs" "$WORKTREE_BASE/.session" "$WORKTREE_BASE/shared" 2>/dev/null || true
    rm -f "$WORKTREE_BASE/.pre-launch" "$WORKTREE_BASE/.last-save" 2>/dev/null || true
    rmdir "$WORKTREE_BASE" 2>/dev/null || true
  else
    warn "no worktrees to clean"
  fi
}
