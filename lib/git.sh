#!/usr/bin/env bash
# Git helpers: repo detection, worktree enumeration, safety guards.

require_repo() {
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "not inside a git repository"
  REPO_NAME="$(basename "$REPO_ROOT")"
  SESSION_NAME="supercode-$REPO_NAME"
  WORKTREE_BASE="$SUPERCODE_HOME/$REPO_NAME"
}

_sorted_worktrees() {
  [[ -d "$WORKTREE_BASE" ]] || return 0
  # Numeric sort on the trailing agent index (agent-1..agent-16). Portable to
  # BSD/macOS sort, which lacks GNU's `sort -V`. Key off the basename's number
  # so dashes anywhere in the base path can't skew the ordering.
  find "$WORKTREE_BASE" -maxdepth 1 -mindepth 1 -name 'agent-*' -type d 2>/dev/null \
    | awk -F/ '{ n=$NF; sub(/^agent-/, "", n); print n "\t" $0 }' \
    | sort -n -k1,1 | cut -f2-
}

_safe_refs() {
  git -C "$REPO_ROOT" for-each-ref --format='%(refname)' refs/heads/ refs/remotes/ \
    | grep -v '^refs/heads/supercode/' || true
}

_unmerged_count() {
  local branch=$1
  local refs
  refs=$(_safe_refs | tr '\n' ' ')
  if [[ -z "$refs" ]]; then
    git -C "$REPO_ROOT" rev-list --count "$branch" 2>/dev/null || echo 0
  else
    git -C "$REPO_ROOT" rev-list --count "$branch" --not $refs 2>/dev/null || echo 0
  fi
}

assert_safe_worktree_path() {
  local path base
  path="$(realpath -m "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null || echo "$1")"
  base="$(realpath -m "$SUPERCODE_HOME" 2>/dev/null || readlink -f "$SUPERCODE_HOME" 2>/dev/null || echo "$SUPERCODE_HOME")"
  [[ "$path" == "$base"/* ]] || die "unsafe path outside SUPERCODE_HOME: $path"
  [[ "$path" != "/" ]] || die "refusing to operate on /"
  [[ "$path" != "$HOME" ]] || die "refusing to operate on HOME"
}
