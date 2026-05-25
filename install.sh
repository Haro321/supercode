#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
LIB_DIR="${LIB_DIR:-$HOME/.local/share/supercode/lib}"
AGENTS_DIR="${AGENTS_DIR:-$HOME/.local/share/supercode/agents}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check bash version
if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: supercode requires Bash 4+. Current: $BASH_VERSION" >&2
  exit 1
fi

# Check required dependencies
for cmd in git tmux; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: missing required dependency: $cmd" >&2
    exit 1
  fi
done

if ! command -v claude >/dev/null 2>&1; then
  echo "warning: 'claude' not found in PATH. Install Claude Code CLI before using supercode." >&2
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR/commands"
mkdir -p "$AGENTS_DIR"

# Copy main script
cp "$SCRIPT_DIR/supercode" "$INSTALL_DIR/supercode"
chmod +x "$INSTALL_DIR/supercode"

# Copy lib files
cp "$SCRIPT_DIR"/lib/*.sh "$LIB_DIR/"
cp "$SCRIPT_DIR"/lib/commands/*.sh "$LIB_DIR/commands/"

# Copy per-role skill files (agents/<role>.md). Optional — only if present
# in the repo. The runtime falls back to bash descriptions if these are
# missing, so an old checkout still works.
if [[ -d "$SCRIPT_DIR/agents" ]] && compgen -G "$SCRIPT_DIR/agents/*.md" > /dev/null; then
  cp "$SCRIPT_DIR"/agents/*.md "$AGENTS_DIR/"
fi

# Create a symlink so the installed script can find lib/
# The script looks for lib/ relative to itself, so we symlink it
ln -sfn "$LIB_DIR/.." "$INSTALL_DIR/supercode-lib" 2>/dev/null || true

echo "supercode installed:"
echo "  script:  $INSTALL_DIR/supercode"
echo "  lib:     $LIB_DIR/"
echo "  agents:  $AGENTS_DIR/"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo "NOTE: $INSTALL_DIR is not in your PATH. Add it:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
echo "Run 'supercode doctor' to verify your setup."
