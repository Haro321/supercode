#!/usr/bin/env bash
# Interactive task input and file-based task reading.

prompt_tasks_interactive() {
  local n=""
  read -r -p "How many agents? [$MIN_AGENTS-$MAX_AGENTS, default $DEFAULT_AGENTS] " n
  [[ -z "$n" ]] && n=$DEFAULT_AGENTS
  [[ "$n" =~ ^[0-9]+$ ]] || die "not a number: $n"
  [[ "$n" -ge $MIN_AGENTS && "$n" -le $MAX_AGENTS ]] \
    || die "agent count must be between $MIN_AGENTS and $MAX_AGENTS (got $n)"

  echo "${C_BOLD}Enter $n tasks${C_RESET} (one per line, blank to abort):"
  local tasks=()
  for i in $(seq 1 $n); do
    local line=""
    read -r -p "  ${C_CYAN}task $i:${C_RESET} " line
    [[ -z "$line" ]] && die "task $i is empty -- aborted"
    tasks+=("$line")
  done
  cmd_start "${tasks[@]}"
}

read_tasks_from_file() {
  local f=$1
  [[ -f "$f" ]] || die "file not found: $f"
  local tasks=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == "#"* ]] && continue
    tasks+=("$line")
  done < "$f"
  local n=${#tasks[@]}
  [[ $n -ge $MIN_AGENTS && $n -le $MAX_AGENTS ]] \
    || die "$f must contain $MIN_AGENTS-$MAX_AGENTS non-empty, non-comment lines (got $n)"
  cmd_start "${tasks[@]}"
}
