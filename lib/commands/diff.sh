#!/usr/bin/env bash
# Show files changed by each agent.

cmd_diff() {
  require_repo

  local target=${1:-all}
  [[ -d "$WORKTREE_BASE" ]] && compgen -G "$WORKTREE_BASE/agent-*" >/dev/null \
    || die "no supercode worktrees found"

  local current
  current="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"

  _diff_one() {
    local agent_n=$1
    local wt="$WORKTREE_BASE/agent-$agent_n"
    [[ -d "$wt" ]] || die "no agent-$agent_n worktree"
    local branch
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
    local files uncommitted

    # Committed changes vs base
    files=$(git -C "$REPO_ROOT" diff --name-only "$current...$branch" 2>/dev/null || true)
    # Uncommitted changes in worktree
    uncommitted=$(git -C "$wt" diff --name-only 2>/dev/null || true)
    local unstaged
    unstaged=$(git -C "$wt" diff --cached --name-only 2>/dev/null || true)
    local untracked
    untracked=$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null || true)

    echo "${C_BOLD}agent-$agent_n${C_RESET} ${C_DIM}($branch)${C_RESET}"
    if [[ -n "$files" ]]; then
      echo "${C_GREEN}  committed:${C_RESET}"
      echo "$files" | sed 's/^/    /'
    fi
    if [[ -n "$uncommitted$unstaged" ]]; then
      echo "${C_YELLOW}  modified:${C_RESET}"
      { echo "$uncommitted"; echo "$unstaged"; } | sort -u | grep -v '^$' | sed 's/^/    /'
    fi
    if [[ -n "$untracked" ]]; then
      echo "${C_CYAN}  new:${C_RESET}"
      echo "$untracked" | sed 's/^/    /'
    fi
    if [[ -z "$files" && -z "$uncommitted" && -z "$unstaged" && -z "$untracked" ]]; then
      echo "  ${C_DIM}(no changes)${C_RESET}"
    fi
  }

  if [[ "$target" == "all" ]]; then
    while IFS= read -r wt; do
      local agent_n="${wt##*agent-}"
      echo
      _diff_one "$agent_n"
    done < <(_sorted_worktrees)
  else
    _diff_one "$target"
  fi
}
