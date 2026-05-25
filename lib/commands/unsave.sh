#!/usr/bin/env bash
# Undo the last save.

cmd_unsave() {
  require_repo
  local savefile="$WORKTREE_BASE/.last-save"
  [[ -f "$savefile" ]] || die "nothing to unsave (no save point recorded)"

  local pre_sha saved_branch current cur_sha
  pre_sha=$(sed -n 1p "$savefile")
  saved_branch=$(sed -n 2p "$savefile")
  current=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  cur_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)

  if [[ "$current" != "$saved_branch" ]]; then
    warn "save was made on '$saved_branch' but you're currently on '$current'"
    local ans=""
    read -r -p "Switch to '$saved_branch' and rewind it? [y/N] " ans
    [[ "$ans" =~ ^[yY]$ ]] || die "aborted"
    if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
      die "current branch has uncommitted changes -- commit or stash before switching"
    fi
    git -C "$REPO_ROOT" checkout "$saved_branch" >/dev/null
    current=$saved_branch
    cur_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)
  fi

  if [[ "$cur_sha" == "$pre_sha" ]]; then
    warn "$current is already at the pre-save state -- nothing to undo"
    rm -f "$savefile"
    return 0
  fi

  echo "${C_BOLD}This will rewind${C_RESET} ${C_GREEN}$current${C_RESET}"
  echo "  from: ${C_DIM}$cur_sha${C_RESET}"
  echo "  to:   ${C_DIM}$pre_sha${C_RESET}"
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
  [[ -n "$pushed_one" ]] && warn "some commits have already been pushed to a remote -- unsave is local only"

  local ans=""
  read -r -p "Confirm unsave? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || die "aborted"

  git -C "$REPO_ROOT" reset --hard "$pre_sha" >/dev/null
  rm -f "$savefile"
  ok "$current rewound. Agent worktrees and branches are untouched."
}
