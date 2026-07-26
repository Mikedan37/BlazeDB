#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: Swift is not installed or not in PATH."
  echo "Install Swift 6+ first, then re-run this script."
  exit 1
fi

echo "==> Building blazedb"
swift build --product blazedb

BIN_PATH="$(swift build --product blazedb --show-bin-path)/blazedb"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: built binary not found at $BIN_PATH"
  exit 1
fi

choose_install_dir() {
  if [[ -w "/usr/local/bin" ]]; then
    echo "/usr/local/bin"
    return
  fi

  if [[ -w "/opt/homebrew/bin" ]]; then
    echo "/opt/homebrew/bin"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  echo "$HOME/.local/bin"
}

INSTALL_DIR="$(choose_install_dir)"
TARGET_PATH="$INSTALL_DIR/blazedb"
ALIAS_PATH="$INSTALL_DIR/blazerepl"
LOCAL_BIN_DIR="$HOME/.local/bin"
LOCAL_TARGET_PATH="$LOCAL_BIN_DIR/blazedb"
LOCAL_ALIAS_PATH="$LOCAL_BIN_DIR/blazerepl"

echo "==> Installing to $TARGET_PATH"
ln -sf "$BIN_PATH" "$TARGET_PATH"
ln -sf "$TARGET_PATH" "$ALIAS_PATH"

# Keep ~/.local/bin in sync as a compatibility mirror so older PATH orderings
# do not run a stale blazedb binary from previous installs.
mkdir -p "$LOCAL_BIN_DIR"
ln -sf "$BIN_PATH" "$LOCAL_TARGET_PATH"
ln -sf "$LOCAL_TARGET_PATH" "$LOCAL_ALIAS_PATH"

if ! command -v blazedb >/dev/null 2>&1; then
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      echo
      echo "Add this to your shell profile so blazedb is callable anywhere:"
      echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
fi

echo
echo "Install complete."
echo "Binary: $TARGET_PATH"
echo "Alias:  $ALIAS_PATH"
if [[ "$TARGET_PATH" != "$LOCAL_TARGET_PATH" ]]; then
  echo "Mirror: $LOCAL_TARGET_PATH"
fi
echo
echo "Try:"
echo "  blazedb --help"
echo "  blazedb start"
echo "  blazerepl start"
