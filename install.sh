#!/usr/bin/env bash
set -euo pipefail

DEST="${AGENT_MAC_GC_HOME:-$HOME/.agent-mac-gc}"
BIN_DIR="${HOME}/.local/bin"

if [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" pull --rebase
else
  git clone https://github.com/andyleimc-source/agent-mac-gc.git "$DEST"
fi

chmod +x "$DEST/bin/agent-mac-gc"
mkdir -p "$BIN_DIR"
ln -sf "$DEST/bin/agent-mac-gc" "$BIN_DIR/agent-mac-gc"

echo "Linked agent-mac-gc -> $BIN_DIR/agent-mac-gc"
"$DEST/bin/agent-mac-gc" install
