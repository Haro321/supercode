#!/usr/bin/env bash
# Dependency and environment checks.

cmd_doctor() {
  local all_ok=1

  _check() {
    if command -v "$1" >/dev/null 2>&1; then
      ok "$1: $($2 2>/dev/null || echo 'found')"
    else
      echo "  ${C_RED}x${C_RESET} $1: not found"
      all_ok=0
    fi
  }

  echo "${C_BOLD}supercode doctor${C_RESET}"
  echo ""

  # Bash version
  if (( BASH_VERSINFO[0] >= 4 )); then
    ok "bash: $BASH_VERSION"
  else
    echo "  ${C_RED}x${C_RESET} bash: $BASH_VERSION (need 4+)"
    all_ok=0
  fi

  _check git "git --version"
  _check tmux "tmux -V"
  _check claude "echo $(command -v claude)"

  # Optional
  echo ""
  echo "${C_BOLD}Optional:${C_RESET}"
  if command -v jq >/dev/null 2>&1; then
    ok "jq: $(jq --version 2>/dev/null) (enables session JSON export)"
  else
    echo "  ${C_DIM}-${C_RESET} jq: not found (session JSON export unavailable)"
  fi
  if command -v bats >/dev/null 2>&1; then
    ok "bats: $(bats --version 2>/dev/null) (enables test suite)"
  else
    echo "  ${C_DIM}-${C_RESET} bats: not found (test suite unavailable)"
  fi

  # Environment
  echo ""
  echo "${C_BOLD}Environment:${C_RESET}"
  ok "SUPERCODE_HOME: ${SUPERCODE_HOME}"
  ok "SUPERCODE_CLAUDE_ARGS: ${SUPERCODE_CLAUDE_ARGS:-(none)}"
  ok "SUPERCODE_BOOT_DELAY: ${BOOT_DELAY}s"

  # Git repo check
  echo ""
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    local root
    root="$(git rev-parse --show-toplevel)"
    ok "git repo: $(basename "$root") ($root)"
  else
    echo "  ${C_DIM}-${C_RESET} not inside a git repository"
  fi

  echo ""
  if (( all_ok )); then
    echo "${C_GREEN}All required dependencies found.${C_RESET}"
  else
    echo "${C_RED}Missing required dependencies. Install them before using supercode.${C_RESET}"
    return 1
  fi
}
