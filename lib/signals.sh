#!/usr/bin/env bash
# Agent status signals via shared directory.

_shared_dir() {
  echo "$WORKTREE_BASE/shared"
}

_status_dir() {
  echo "$(_shared_dir)/status"
}

shared_dir_init() {
  local shared
  shared="$(_shared_dir)"
  mkdir -p "$shared/status" "$shared/contracts" "$shared/outputs"
}

shared_dir_link() {
  local wt=$1
  local shared
  shared="$(_shared_dir)"
  ln -sfn "$shared" "$wt/shared"
}

signal_write() {
  local role=$1 status=$2 message=${3:-""}
  local status_dir
  status_dir="$(_status_dir)"
  mkdir -p "$status_dir"
  local timestamp
  timestamp=$(date -Iseconds)
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg role "$role" \
      --arg status "$status" \
      --arg message "$message" \
      --arg timestamp "$timestamp" \
      '{"role": $role, "status": $status, "message": $message, "timestamp": $timestamp}' \
      > "$status_dir/$role.json"
  else
    printf '{"role":"%s","status":"%s","message":"%s","timestamp":"%s"}\n' \
      "$role" "$status" "$message" "$timestamp" > "$status_dir/$role.json"
  fi
}

signal_read() {
  local role=$1
  local f="$(_status_dir)/$role.json"
  [[ -f "$f" ]] && cat "$f" || echo ""
}

signal_read_status() {
  local role=$1
  local f="$(_status_dir)/$role.json"
  [[ -f "$f" ]] || { echo "unknown"; return; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.status // "unknown"' "$f" 2>/dev/null
  else
    grep -o '"status":"[^"]*"' "$f" 2>/dev/null | head -1 | cut -d'"' -f4
  fi
}

signal_all_done() {
  local status_dir
  status_dir="$(_status_dir)"
  [[ -d "$status_dir" ]] || return 1
  local count=0 done_count=0
  for f in "$status_dir"/*.json; do
    [[ -f "$f" ]] || continue
    ((count++))
    local s
    s=$(signal_read_status "$(basename "$f" .json)")
    [[ "$s" == "done" ]] && ((done_count++))
  done
  (( count > 0 && count == done_count ))
}

signal_check_deps() {
  local -a deps=("$@")
  for dep in "${deps[@]}"; do
    local s
    s=$(signal_read_status "$dep")
    [[ "$s" == "done" ]] || return 1
  done
  return 0
}
