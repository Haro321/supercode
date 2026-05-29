#!/usr/bin/env bash
# Save (merge) all agent work into the current branch.

cmd_save() {
  require_repo

  local dry_run=0
  local into_branch=""
  local strategy=""

  while (( $# )); do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --into)    shift; into_branch="${1:-}"; shift ;;
      --strategy)
        shift
        strategy="${1:-}"
        case "$strategy" in
          theirs|ours) ;;
          *) die "--strategy must be 'theirs' or 'ours' (got: '$strategy')" ;;
        esac
        shift
        ;;
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

  # Build merge args -- include -X theirs/ours if strategy is set
  local merge_args=(--no-ff)
  [[ -n "$strategy" ]] && merge_args+=(-X "$strategy")

  local skipped=()
  # Merge each agent branch
  for branch in "${to_merge[@]}"; do
    if git -C "$REPO_ROOT" merge "${merge_args[@]}" "$branch" -m "supercode: merge $branch" >/dev/null 2>&1; then
      ok "merged $branch"
      continue
    fi

    # Conflict -- drop into the interactive resolver
    warn "merge conflict on $branch"
    local rc=0
    _resolve_merge_conflict "$branch" || rc=$?
    case "$rc" in
      0)
        ok "merged $branch (with manual conflict resolution)"
        ;;
      1)
        skipped+=("$branch")
        warn "skipped $branch -- continuing with remaining agents"
        ;;
      2)
        warn "aborting entire save -- rolling back to pre-save state"
        git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
        git -C "$REPO_ROOT" reset --hard "$cur_sha" >/dev/null
        die "save aborted by user. Successful merges have been rolled back."
        ;;
    esac
  done

  printf "%s\n%s\n" "$cur_sha" "$current" > "$savefile"
  echo ""
  ok "Saved into $current. Run ${C_BOLD}supercode unsave${C_RESET} to undo."

  if (( ${#skipped[@]} > 0 )); then
    echo ""
    warn "skipped branches (not merged): ${skipped[*]}"
    echo "  Resolve manually in the worktree, then rerun ${C_BOLD}supercode save${C_RESET}."
  fi

  # Multi-head check: parallel agents often write migrations against the
  # same down_revision and we just merged them all together.
  if ! migrations_audit "$REPO_ROOT" >/tmp/.supercode_audit.$$ 2>&1; then
    echo ""
    warn "alembic chain has multi-head or fork issues:"
    cat /tmp/.supercode_audit.$$
    echo ""
    echo "  Run ${C_BOLD}supercode migrations fix${C_RESET} to auto-linearize."
  fi
  rm -f /tmp/.supercode_audit.$$
}

# Drop into an interactive prompt when a merge conflicts mid-save.
# Returns: 0 = resolved & committed, 1 = skip this branch, 2 = abort entire save.
_resolve_merge_conflict() {
  local branch=$1
  local conflicted
  conflicted=$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null)

  echo ""
  echo "${C_BOLD}Conflicted files (merging ${C_YELLOW}$branch${C_RESET}${C_BOLD} into HEAD):${C_RESET}"
  if [[ -n "$conflicted" ]]; then
    echo "$conflicted" | sed 's/^/  /'
  else
    echo "  ${C_DIM}(none detected -- merge may have failed for another reason)${C_RESET}"
  fi
  echo ""

  while true; do
    local action=""
    if ! read -r -p "[t]heirs [o]urs [m]anual [s]kip-branch [a]bort-all [?]help: " action; then
      # stdin EOF (non-interactive context with no more input) -- abort cleanly
      echo ""
      warn "stdin closed; treating as abort-all"
      git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
      return 2
    fi
    case "$action" in
      t|T|theirs)
        if _apply_side_resolution theirs "$branch"; then
          return 0
        fi
        ;;
      o|O|ours)
        if _apply_side_resolution ours "$branch"; then
          return 0
        fi
        ;;
      m|M|manual)
        echo ""
        echo "Dropping to a shell in ${C_BOLD}$REPO_ROOT${C_RESET}."
        echo "  - Resolve conflicts however you like (edit files, git add, etc)."
        echo "  - When done, ${C_BOLD}exit 0${C_RESET} to commit & continue (or just 'exit')."
        echo "  - ${C_BOLD}exit 1${C_RESET} to skip this branch (we'll 'git merge --abort')."
        echo "  - ${C_BOLD}exit 2${C_RESET} to abort the entire save."
        echo ""
        local shell_rc=0
        ( cd "$REPO_ROOT" && "${SHELL:-/bin/bash}" ) || shell_rc=$?
        case "$shell_rc" in
          0)
            # Try to commit the merge if it's still in progress
            if [[ -f "$REPO_ROOT/.git/MERGE_HEAD" ]]; then
              if [[ -n "$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null)" ]]; then
                warn "conflicts still unresolved -- choose again"
                continue
              fi
              if ! git -C "$REPO_ROOT" -c core.editor=true commit --no-edit >/dev/null 2>&1; then
                warn "commit failed -- choose again"
                continue
              fi
            fi
            return 0
            ;;
          1)
            git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
            return 1
            ;;
          2)
            git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
            return 2
            ;;
          *)
            warn "shell exited with code $shell_rc -- treating as 'choose again'"
            ;;
        esac
        ;;
      s|S|skip)
        git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
        return 1
        ;;
      a|A|abort)
        git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
        return 2
        ;;
      \?|h|help)
        cat <<HLP
  ${C_BOLD}[t] theirs${C_RESET}        -- take incoming branch ('$branch') for every conflicted file
  ${C_BOLD}[o] ours${C_RESET}          -- keep current HEAD's version for every conflicted file
  ${C_BOLD}[m] manual${C_RESET}        -- drop to a shell in the repo to resolve by hand
  ${C_BOLD}[s] skip-branch${C_RESET}   -- abort just this merge; continue with remaining agents
  ${C_BOLD}[a] abort-all${C_RESET}     -- roll back every successful merge & exit
HLP
        ;;
      *)
        echo "Unknown choice: '$action'. Type ? for help."
        ;;
    esac
  done
}

# Apply 'theirs' or 'ours' to every conflicted path, then commit the merge.
# Falls back gracefully on delete/modify and add/add cases. Returns 0 on success.
_apply_side_resolution() {
  local side=$1   # theirs | ours
  local branch=$2
  local files f
  files=$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null)

  if [[ -z "$files" ]]; then
    warn "no conflicted files to resolve"
    return 1
  fi

  local failed=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if git -C "$REPO_ROOT" checkout --"$side" -- "$f" 2>/dev/null; then
      git -C "$REPO_ROOT" add -- "$f" 2>/dev/null || failed=1
    else
      # delete/modify: checkout failed -- try rm if the side wants deletion
      if [[ "$side" == "theirs" ]] && ! git -C "$REPO_ROOT" cat-file -e ":3:$f" 2>/dev/null; then
        git -C "$REPO_ROOT" rm -- "$f" >/dev/null 2>&1 || failed=1
      elif [[ "$side" == "ours" ]] && ! git -C "$REPO_ROOT" cat-file -e ":2:$f" 2>/dev/null; then
        git -C "$REPO_ROOT" rm -- "$f" >/dev/null 2>&1 || failed=1
      else
        warn "could not auto-resolve '$f' -- try [m]anual"
        failed=1
      fi
    fi
  done <<< "$files"

  if (( failed )); then
    return 1
  fi

  if ! git -C "$REPO_ROOT" -c core.editor=true commit \
        -m "supercode: merge $branch (resolved with --$side)" >/dev/null 2>&1; then
    warn "commit failed after applying --$side -- try [m]anual"
    return 1
  fi
  return 0
}
