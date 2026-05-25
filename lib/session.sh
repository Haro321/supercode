#!/usr/bin/env bash
# Session state tracking.

_session_dir() {
  echo "$WORKTREE_BASE/.session"
}

session_init() {
  local n=$1 base_branch=$2 stamp=$3
  shift 3
  local tasks=("$@")
  local sdir
  sdir="$(_session_dir)"
  mkdir -p "$sdir"
  echo "$REPO_NAME" > "$sdir/repo"
  echo "$base_branch" > "$sdir/base_branch"
  echo "$stamp" > "$sdir/stamp"
  echo "$n" > "$sdir/agent_count"
  echo "running" > "$sdir/status"
  for ((i=1; i<=n; i++)); do
    local adir="$sdir/agent-$i"
    mkdir -p "$adir"
    echo "supercode/agent-$i-$stamp" > "$adir/branch"
    echo "$WORKTREE_BASE/agent-$i" > "$adir/worktree"
    echo "running" > "$adir/status"
    local task_idx=$((i - 1))
    if (( task_idx < ${#tasks[@]} )); then
      echo "${tasks[$task_idx]}" > "$adir/task"
    else
      echo "" > "$adir/task"
    fi
  done
}

session_update_agent() {
  local agent_n=$1 key=$2 value=$3
  local adir
  adir="$(_session_dir)/agent-$agent_n"
  [[ -d "$adir" ]] || return 1
  echo "$value" > "$adir/$key"
}

session_get_agent() {
  local agent_n=$1 key=$2
  local f
  f="$(_session_dir)/agent-$agent_n/$key"
  [[ -f "$f" ]] && cat "$f" || echo ""
}

session_agent_count() {
  local f="$(_session_dir)/agent_count"
  [[ -f "$f" ]] && cat "$f" || echo 0
}

session_get() {
  local key=$1
  local f="$(_session_dir)/$key"
  [[ -f "$f" ]] && cat "$f" || echo ""
}

session_to_json() {
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not installed -- cannot output JSON"
    return 1
  fi
  local sdir
  sdir="$(_session_dir)"
  [[ -d "$sdir" ]] || { echo "{}"; return 0; }
  local n repo base status
  n=$(session_agent_count)
  repo=$(session_get repo)
  base=$(session_get base_branch)
  status=$(session_get status)
  local agents="[]"
  for ((i=1; i<=n; i++)); do
    local branch task astatus worktree role
    branch=$(session_get_agent "$i" branch)
    task=$(session_get_agent "$i" task)
    astatus=$(session_get_agent "$i" status)
    worktree=$(session_get_agent "$i" worktree)
    role=$(session_get_agent "$i" role)
    agents=$(echo "$agents" | jq \
      --arg id "$i" \
      --arg branch "$branch" \
      --arg task "$task" \
      --arg status "$astatus" \
      --arg worktree "$worktree" \
      --arg role "$role" \
      '. + [{"id": ($id|tonumber), "role": $role, "branch": $branch, "task": $task, "status": $status, "worktree": $worktree}]')
  done
  jq -n \
    --arg repo "$repo" \
    --arg base "$base" \
    --arg status "$status" \
    --argjson agents "$agents" \
    '{"repo": $repo, "base_branch": $base, "status": $status, "agents": $agents}'
}
