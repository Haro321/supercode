#!/usr/bin/env bash
# Output helpers and color detection.

if [[ -t 1 ]]; then
  C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
  C_RED=$'\e[31m'; C_CYAN=$'\e[36m'; C_RESET=$'\e[0m'
else
  C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_RESET=""
fi

die()  { echo "${C_RED}supercode:${C_RESET} $*" >&2; exit 1; }
info() { echo "${C_CYAN}->${C_RESET} $*"; }
ok()   { echo "  ${C_GREEN}ok${C_RESET} $*"; }
warn() { echo "${C_YELLOW}!${C_RESET} $*" >&2; }
