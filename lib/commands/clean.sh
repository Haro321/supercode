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
      printf "$blockers"
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
    tmux kill-session -t "$SESSION_NAME"
    ok "killed session '$SESSION_NAME'"
  fi
  if [[ -d "$WORKTREE_BASE" ]]; then
    while IFS= read -r wt; do
      assert_safe_worktree_path "$wt"
      local branch
      branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
      git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
      if [[ "$branch" == supercode/* ]]; then
        git -C "$REPO_ROOT" branch -D "$branch" 2>/dev/null || true
      fi
      ok "removed $(basename "$wt") ${C_DIM}($branch)${C_RESET}"
    done < <(_sorted_worktrees)
    # Remove logs and session state
    rm -rf "$WORKTREE_BASE/logs" "$WORKTREE_BASE/.session" 2>/dev/null || true
    rmdir "$WORKTREE_BASE" 2>/dev/null || true
  else
    warn "no worktrees to clean"
  fi
}
