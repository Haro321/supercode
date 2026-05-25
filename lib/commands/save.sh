#!/usr/bin/env bash
# Save (merge) all agent work into the current branch.

cmd_save() {
  require_repo

  local dry_run=0
  local into_branch=""

  while (( $# )); do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --into)    shift; into_branch="${1:-}"; shift ;;
      *)         shift ;;
    esac
  done

  [[ -d "$WORKTREE_BASE" ]] && compgen -G "$WORKTREE_BASE/agent-*" >/dev/null \
    || die "no supercode worktrees found in this repo"

  local current
  current="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  [[ "$current" == "HEAD" ]] && die "main repo is in detached HEAD -- check out a branch first"

  # If --into specified, create or switch to that branch
  if [[ -n "$into_branch" ]]; then
    if git -C "$REPO_ROOT" rev-parse --verify "$into_branch" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" checkout "$into_branch" >/dev/null
    else
      git -C "$REPO_ROOT" checkout -b "$into_branch" >/dev/null
    fi
    current="$into_branch"
    ok "targeting branch: $current"
  fi

  if ! git -C "$REPO_ROOT" diff --quiet 2>/dev/null \
     || ! git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null; then
    die "main repo ($current) has uncommitted changes -- commit or stash them first"
  fi

  # Protected branch warning
  if [[ "$current" =~ ^(main|master|production|prod|release)$ ]]; then
    warn "you are saving directly into ${C_BOLD}$current${C_RESET}"
    if (( ! dry_run )); then
      local ans=""
      read -r -p "Continue merging into $current? [y/N] " ans
      [[ "$ans" =~ ^[yY]$ ]] || die "aborted -- use 'supercode save --into <branch>' to save elsewhere"
    fi
  fi

  # Auto-commit pending changes inside each worktree
  if (( ! dry_run )); then
    while IFS= read -r wt; do
      local agent
      agent=$(basename "$wt")
      if ! git -C "$wt" diff --quiet 2>/dev/null \
         || ! git -C "$wt" diff --cached --quiet 2>/dev/null \
         || [[ -n "$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        git -C "$wt" add -A
        git -C "$wt" -c user.name='supercode' -c user.email='supercode@local' \
          commit -m "supercode: auto-save $agent" --no-verify >/dev/null
        ok "$agent: committed pending changes"
      fi
    done < <(_sorted_worktrees)
  fi

  # Build merge list
  echo ""
  if (( dry_run )); then
    echo "${C_BOLD}Dry run -- previewing save into ${C_GREEN}$current${C_RESET}${C_BOLD}:${C_RESET}"
  else
    echo "${C_BOLD}Ready to save into ${C_GREEN}$current${C_RESET}${C_BOLD}:${C_RESET}"
  fi

  local to_merge=()
  local -A agent_files=()
  while IFS= read -r wt; do
    local agent branch ahead stat
    agent=$(basename "$wt")
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD)
    ahead=$(_unmerged_count "$branch")
    if [[ "$ahead" == "0" ]]; then
      echo "  ${C_DIM}$agent -- nothing new${C_RESET}"
    else
      stat=$(git -C "$REPO_ROOT" diff --shortstat "$current...$branch" 2>/dev/null | sed 's/^ *//')
      echo "  ${C_BOLD}$agent${C_RESET} -- $ahead commit(s), $stat"
      to_merge+=("$branch")
      agent_files["$agent"]=$(git -C "$REPO_ROOT" diff --name-only "$current...$branch" 2>/dev/null)
    fi
  done < <(_sorted_worktrees)
  echo ""

  # Conflict prediction: detect files changed by multiple agents
  if [[ ${#to_merge[@]} -gt 1 ]]; then
    local -A file_agents=()
    for agent in "${!agent_files[@]}"; do
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        if [[ -n "${file_agents[$f]:-}" ]]; then
          file_agents["$f"]="${file_agents[$f]}, $agent"
        else
          file_agents["$f"]="$agent"
        fi
      done <<< "${agent_files[$agent]}"
    done

    local conflicts_found=0
    for f in "${!file_agents[@]}"; do
      if [[ "${file_agents[$f]}" == *","* ]]; then
        if (( ! conflicts_found )); then
          echo "${C_YELLOW}Potential conflicts:${C_RESET}"
          conflicts_found=1
        fi
        echo "  ${C_BOLD}$f${C_RESET} changed by ${file_agents[$f]}"
      fi
    done
    (( conflicts_found )) && echo ""
  fi

  # Ownership violation check
  if ! ownership_check_violations "$current" 2>/dev/null; then
    echo ""
  fi

  if [[ ${#to_merge[@]} -eq 0 ]]; then
    warn "nothing to save"
    return 0
  fi

  if (( dry_run )); then
    echo "${C_GREEN}Dry run complete.${C_RESET} ${#to_merge[@]} branch(es) would be merged into $current."
    echo "Run ${C_BOLD}supercode save${C_RESET} to execute."
    return 0
  fi

  local ans=""
  read -r -p "Save all of this into ${C_BOLD}$current${C_RESET}? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || die "aborted"

  # Record pre-save HEAD
  local cur_sha
  cur_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)
  local savefile="$WORKTREE_BASE/.last-save"
  mkdir -p "$WORKTREE_BASE"

  # Merge each agent branch
  for branch in "${to_merge[@]}"; do
    if ! git -C "$REPO_ROOT" merge --no-ff "$branch" -m "supercode: merge $branch" >/dev/null 2>&1; then
      warn "merge conflict on $branch -- rolling back to pre-save state"
      git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
      git -C "$REPO_ROOT" reset --hard "$cur_sha" >/dev/null
      die "save aborted. Resolve conflicts inside the worktree and try again."
    fi
    ok "merged $branch"
  done

  printf "%s\n%s\n" "$cur_sha" "$current" > "$savefile"
  echo ""
  ok "Saved into $current. Run ${C_BOLD}supercode unsave${C_RESET} to undo."
}
