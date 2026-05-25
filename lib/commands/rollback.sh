#!/usr/bin/env bash
# Rewind branch to the pre-launch snapshot.

cmd_rollback() {
  require_repo
  local prefile="$WORKTREE_BASE/.pre-launch"
  [[ -f "$prefile" ]] || die "no rollback point recorded -- either supercode hasn't been run here, or it was cleaned"

  local pre_sha pre_branch current cur_sha
  pre_sha=$(sed -n 1p "$prefile")
  pre_branch=$(sed -n 2p "$prefile")
  current=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  cur_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)

  if [[ "$current" != "$pre_branch" ]]; then
    warn "supercode was launched on '$pre_branch' but you're currently on '$current'"
    local ans=""
    read -r -p "Switch to '$pre_branch' and rewind it? [y/N] " ans
    [[ "$ans" =~ ^[yY]$ ]] || die "aborted"
    if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
      die "current branch has uncommitted changes -- commit or stash before switching"
    fi
    git -C "$REPO_ROOT" checkout "$pre_branch" >/dev/null
    current=$pre_branch
    cur_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)
  fi

  if [[ "$cur_sha" == "$pre_sha" ]]; then
    warn "$current is already at the pre-launch state -- nothing to roll back"
    rm -f "$prefile"
    return 0
  fi

  echo "${C_BOLD}This will rewind${C_RESET} ${C_GREEN}$current${C_RESET}"
  echo "  from: ${C_DIM}$cur_sha${C_RESET}"
  echo "  to:   ${C_DIM}$pre_sha${C_RESET} ${C_DIM}(pre-supercode state)${C_RESET}"
  echo ""
  echo "${C_BOLD}Commits being removed:${C_RESET}"
  git -C "$REPO_ROOT" log "$pre_sha..$cur_sha" --oneline 2>/dev/null | sed 's/^/  /'
  echo ""
  warn "this is a hard reset -- uncommitted changes in $current will be lost too"

  local pushed_one
  pushed_one=$(git -C "$REPO_ROOT" rev-list "$pre_sha..$cur_sha" 2>/dev/null \
    | while read -r sha; do
        if [[ -n "$(git -C "$REPO_ROOT" branch -r --contains "$sha" 2>/dev/null)" ]]; then
          echo "$sha"; break
        fi
      done)
  [[ -n "$pushed_one" ]] && warn "some commits have already been pushed to a remote -- rollback is local only"

  local ans=""
  read -r -p "Confirm rollback? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || die "aborted"

  git -C "$REPO_ROOT" reset --hard "$pre_sha" >/dev/null
  rm -f "$prefile"
  rm -f "$WORKTREE_BASE/.last-save"
  ok "$current rewound to pre-supercode state. Agent worktrees and branches are untouched -- 'supercode clean --force' to drop them."
}
