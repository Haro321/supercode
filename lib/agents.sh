#!/usr/bin/env bash
# Agent label, accent color, and pane-label helpers.

_agent_accent_color() {
  local n=$1
  local -a palette=(87 120 222 213 141 81 215 207)
  echo "${palette[$(( (n - 1) % ${#palette[@]} ))]}"
}

_short_label() {
  local s=$1
  s="${s##[[:space:]]}"
  for verb in 'Build a ' 'Build an ' 'Build ' \
              'Set up the ' 'Set up a ' 'Set up ' 'Setup ' \
              'Write the ' 'Write a ' 'Write ' \
              'Add a ' 'Add an ' 'Add ' \
              'Create a ' 'Create an ' 'Create ' 'Make ' \
              'Test and ' 'Test ' 'Implement ' 'Refactor '; do
    if [[ "${s:0:${#verb}}" == "$verb" ]]; then s="${s:${#verb}}"; break; fi
  done
  local words w1 w2 w3
  read -r w1 w2 w3 _ <<<"$s"
  words="${w1:-}"
  [[ -n "${w2:-}" ]] && words="$words $w2"
  [[ -n "${w3:-}" ]] && words="$words $w3"
  printf '%.24s' "$words"
}

_set_pane_label() {
  local pane=$1 label=$2 accent_n=$3
  tmux set-option -pqt "$pane" "@label" "$label"
  if [[ -n "$accent_n" ]]; then
    tmux set-option -pqt "$pane" "@accent" "$(_agent_accent_color "$accent_n")"
  fi
}
