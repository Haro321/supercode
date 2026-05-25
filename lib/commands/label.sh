#!/usr/bin/env bash
# Manage per-agent border labels.

cmd_label() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session -- run 'supercode' first"
  local sub=${1:-list}; shift || true
  case "$sub" in
    set)
      local n=${1:-}; shift || true
      local text="${*:-}"
      [[ -n "$n" && -n "$text" ]] || die 'usage: supercode label set <N> "short text"'
      local pidx
      pidx=$(_agent_pane_index "$SESSION_NAME" "$n")
      _set_pane_label "$SESSION_NAME:0.$pidx" "$text" "$n"
      ok "agent-$n  ->  $text"
      ;;
    auto)
      while read -r pidx; do
        local n=$(( pidx + 1 ))
        local title
        title=$(tmux display-message -t "$SESSION_NAME:0.$pidx" -p '#{pane_title}')
        title="${title## }"
        title="${title#* }"; title="${title#* }"; title="${title#* }"; title="${title#* }"
        title="${title#* }"
        local lbl
        lbl=$(_short_label "$title")
        _set_pane_label "$SESSION_NAME:0.$pidx" "$lbl" "$n"
        printf '  %sagent-%s%s  ->  %s\n' "$C_BOLD" "$n" "$C_RESET" "$lbl"
      done < <(_agent_pane_indices "$SESSION_NAME")
      ;;
    clear)
      local n=${1:-}
      [[ -n "$n" ]] || die 'usage: supercode label clear <N>'
      local pidx
      pidx=$(_agent_pane_index "$SESSION_NAME" "$n")
      tmux set-option -pqt "$SESSION_NAME:0.$pidx" -u "@label"
      ok "cleared label for agent-$n"
      ;;
    list|"")
      while read -r pidx; do
        local n=$(( pidx + 1 ))
        local lbl
        lbl=$(tmux show-option -pqv -t "$SESSION_NAME:0.$pidx" "@label" 2>/dev/null || true)
        local acc
        acc=$(tmux show-option -pqv -t "$SESSION_NAME:0.$pidx" "@accent" 2>/dev/null || true)
        printf '  agent-%s  accent=%-4s  label=%s\n' "$n" "${acc:---}" "${lbl:---}"
      done < <(_agent_pane_indices "$SESSION_NAME")
      ;;
    *) die "unknown label subcommand: $sub (try: set | auto | list | clear)" ;;
  esac
}
