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

# Escape a string for safe interpolation into a JSON string literal (used only
# on the no-jq fallback path).
_json_esc() {
  local s=$1
  s=${s//\\/\\\\}   # backslash first
  s=${s//\"/\\\"}   # then double-quote
  s=${s//$'\n'/ }   # collapse control chars that can't appear raw in JSON
  s=${s//$'\r'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

signal_write() {
  local role=$1 status=$2 message=${3:-""} role_n=${4:-""} agent_n=${5:-"$role_n"}
  local status_dir
  status_dir="$(_status_dir)"
  mkdir -p "$status_dir"
  # Epoch seconds: portable across GNU and BSD/macOS date (no -Iseconds/-d).
  local timestamp
  timestamp=$(date +%s)
  local key="$role"
  [[ -n "$role_n" ]] && key="${role}_${role_n}"
  if command -v jq >/dev/null 2>&1; then
    # -c = compact single-line output so the no-jq grep readers can parse it too.
    jq -nc \
      --arg role "$role" \
      --arg status "$status" \
      --arg message "$message" \
      --arg timestamp "$timestamp" \
      --arg agent "$agent_n" \
      '{"role": $role, "status": $status, "message": $message, "timestamp": $timestamp, "agent": $agent}' \
      > "$status_dir/$key.json"
  else
    printf '{"role":"%s","status":"%s","message":"%s","timestamp":"%s","agent":"%s"}\n' \
      "$(_json_esc "$role")" "$(_json_esc "$status")" "$(_json_esc "$message")" \
      "$(_json_esc "$timestamp")" "$(_json_esc "$agent_n")" > "$status_dir/$key.json"
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
    ((++count))
    local s
    s=$(signal_read_status "$(basename "$f" .json)")
    [[ "$s" == "done" ]] && ((++done_count))
  done
  (( count > 0 && count == done_count ))
}

signal_check_deps() {
  local -a deps=("$@")
  local status_dir
  status_dir="$(_status_dir)"
  for dep in "${deps[@]}"; do
    local found=0
    for f in "$status_dir/${dep}_"*.json "$status_dir/${dep}.json"; do
      [[ -f "$f" ]] || continue
      found=1
      local s
      s=$(signal_read_status "$(basename "$f" .json)")
      [[ "$s" == "done" ]] || return 1
    done
    (( found )) || return 1
  done
  return 0
}

signal_age_seconds() {
  local role=$1
  local f="$(_status_dir)/$role.json"
  [[ -f "$f" ]] || { echo "-1"; return; }
  local ts
  if command -v jq >/dev/null 2>&1; then
    ts=$(jq -r '.timestamp // ""' "$f" 2>/dev/null)
  else
    ts=$(grep -o '"timestamp":"[^"]*"' "$f" 2>/dev/null | head -1 | cut -d'"' -f4)
  fi
  # Primary: self-reported epoch timestamp. Fallback: the status file's mtime,
  # which is rewritten on every status update -- so staleness still works even
  # when an agent's hand-written JSON omits/garbles the timestamp field.
  if ! [[ "$ts" =~ ^[0-9]+$ ]]; then
    ts=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "")
  fi
  [[ "$ts" =~ ^[0-9]+$ ]] || { echo "-1"; return; }
  echo $(( $(date +%s) - ts ))
}

signal_blocked_agents() {
  local status_dir
  status_dir="$(_status_dir)"
  [[ -d "$status_dir" ]] || return
  for f in "$status_dir"/*.json; do
    [[ -f "$f" ]] || continue
    local role
    role=$(basename "$f" .json)
    local s
    s=$(signal_read_status "$role")
    [[ "$s" == "blocked" ]] && echo "$role"
  done
}

signal_stale_agents() {
  local threshold=${1:-180}
  local status_dir
  status_dir="$(_status_dir)"
  [[ -d "$status_dir" ]] || return
  for f in "$status_dir"/*.json; do
    [[ -f "$f" ]] || continue
    local role
    role=$(basename "$f" .json)
    local s
    s=$(signal_read_status "$role")
    [[ "$s" == "done" ]] && continue
    local age
    age=$(signal_age_seconds "$role")
    (( age >= threshold )) && echo "$role"
  done
}

signal_silent_agents() {
  local expected_count=${1:-0}
  local status_dir
  status_dir="$(_status_dir)"
  local found=0
  if [[ -d "$status_dir" ]]; then
    for f in "$status_dir"/*.json; do
      [[ -f "$f" ]] && ((++found))
    done
  fi
  echo $(( expected_count - found ))
}

signal_health_report() {
  local threshold=${1:-180}
  local status_dir
  status_dir="$(_status_dir)"
  local report=""
  local has_issues=0

  local -a blocked=() stale=() working=() done_agents=() silent=()

  if [[ -d "$status_dir" ]] && compgen -G "$status_dir/*.json" >/dev/null 2>&1; then
    for f in "$status_dir"/*.json; do
      [[ -f "$f" ]] || continue
      local role s age msg
      role=$(basename "$f" .json)
      s=$(signal_read_status "$role")
      age=$(signal_age_seconds "$role")

      if command -v jq >/dev/null 2>&1; then
        msg=$(jq -r '.message // ""' "$f" 2>/dev/null)
      else
        msg=$(grep -o '"message":"[^"]*"' "$f" 2>/dev/null | head -1 | cut -d'"' -f4)
      fi

      case "$s" in
        blocked) blocked+=("$role|$age|$msg"); has_issues=1 ;;
        done)    done_agents+=("$role") ;;
        *)
          if (( age >= threshold )); then
            stale+=("$role|$age|$msg"); has_issues=1
          else
            working+=("$role|$age|$msg")
          fi
          ;;
      esac
    done
  fi

  report+="AGENT HEALTH REPORT (stale threshold: ${threshold}s)"$'\n'
  report+="================================================"$'\n'

  if (( ${#blocked[@]} )); then
    report+=$'\n'"BLOCKED (need immediate help):"$'\n'
    for entry in "${blocked[@]}"; do
      IFS='|' read -r r a m <<< "$entry"
      report+="  $r — blocked ${a}s ago: $m"$'\n'
    done
  fi

  if (( ${#stale[@]} )); then
    report+=$'\n'"STALE (no update in >${threshold}s — may be stuck):"$'\n'
    for entry in "${stale[@]}"; do
      IFS='|' read -r r a m <<< "$entry"
      report+="  $r — last update ${a}s ago: $m"$'\n'
    done
  fi

  if (( ${#working[@]} )); then
    report+=$'\n'"WORKING (healthy):"$'\n'
    for entry in "${working[@]}"; do
      IFS='|' read -r r a m <<< "$entry"
      report+="  $r — updated ${a}s ago: $m"$'\n'
    done
  fi

  if (( ${#done_agents[@]} )); then
    report+=$'\n'"DONE: ${done_agents[*]}"$'\n'
  fi

  if (( has_issues )); then
    report+=$'\n'"ACTION NEEDED: ${#blocked[@]} blocked, ${#stale[@]} stale"$'\n'
  else
    report+=$'\n'"ALL HEALTHY: ${#working[@]} working, ${#done_agents[@]} done"$'\n'
  fi

  printf '%s' "$report"
}
