#!/usr/bin/env bash
# Output helpers and color detection.

if [[ -t 1 ]]; then
  C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
  C_RED=$'\e[31m'; C_CYAN=$'\e[36m'; C_RESET=$'\e[0m'
else
  C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_RESET=""
fi

# die()/warn() write to stderr, so gate their color on stderr being a TTY --
# otherwise raw escape codes leak into a redirected stderr log (supercode ... 2>file).
if [[ -t 2 ]]; then
  CE_RED=$'\e[31m'; CE_YELLOW=$'\e[33m'; CE_RESET=$'\e[0m'
else
  CE_RED=""; CE_YELLOW=""; CE_RESET=""
fi

die()  { echo "${CE_RED}supercode:${CE_RESET} $*" >&2; exit 1; }
info() { echo "${C_CYAN}->${C_RESET} $*"; }
ok()   { echo "  ${C_GREEN}ok${C_RESET} $*"; }
warn() { echo "${CE_YELLOW}!${CE_RESET} $*" >&2; }
