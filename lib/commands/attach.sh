#!/usr/bin/env bash
# Attach to a running session.

cmd_attach() {
  require_repo
  tmux has-session -t "$SESSION_NAME" 2>/dev/null \
    || die "no session '$SESSION_NAME' running. Start one with 'supercode \"task1\" ... \"taskN\"'."
  if [[ -t 0 && -t 1 ]]; then
    exec tmux attach -t "$SESSION_NAME"
  else
    die "no TTY -- run 'supercode attach' from a real terminal"
  fi
}
