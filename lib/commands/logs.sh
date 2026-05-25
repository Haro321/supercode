#!/usr/bin/env bash
# View per-agent logs.

cmd_logs() {
  require_repo
  local target=${1:-}
  [[ -n "$target" ]] || die "usage: supercode logs <N|all|brain> [--tail LINES]"
  shift || true

  local tail_lines=50
  while (( $# )); do
    case "$1" in
      --tail) shift; tail_lines="${1:-50}"; shift ;;
      *)      shift ;;
    esac
  done

  local logdir="$WORKTREE_BASE/logs"
  [[ -d "$logdir" ]] || die "no logs found -- logs are captured during active sessions"

  _show_log() {
    local name=$1
    local logfile="$logdir/$name.log"
    if [[ -f "$logfile" ]]; then
      echo "${C_BOLD}-- $name --${C_RESET}"
      tail -n "$tail_lines" "$logfile"
    else
      echo "${C_DIM}$name: no log file${C_RESET}"
    fi
  }

  case "$target" in
    all)
      for logfile in "$logdir"/*.log; do
        [[ -f "$logfile" ]] || continue
        local name
        name=$(basename "$logfile" .log)
        echo
        _show_log "$name"
      done
      ;;
    brain)
      _show_log "brain"
      ;;
    *)
      [[ "$target" =~ ^[0-9]+$ ]] || die "expected agent number, got '$target'"
      _show_log "agent-$target"
      ;;
  esac
}
