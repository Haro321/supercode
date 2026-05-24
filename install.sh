#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

mkdir -p "$INSTALL_DIR"
cp supercode "$INSTALL_DIR/supercode"
chmod +x "$INSTALL_DIR/supercode"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "supercode installed to $INSTALL_DIR/supercode"
  echo "NOTE: $INSTALL_DIR is not in your PATH. Add it:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
else
  echo "supercode installed to $INSTALL_DIR/supercode"
fi
