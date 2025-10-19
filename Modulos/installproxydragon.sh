#!/usr/bin/env bash
# DragonX Installer
# Original author: Danilo (refactored for DragonX)
set -e

INSTALL_DIR="$HOME/DragonX"
REPO_URL="https://git.dr2.site/penguinehis/DragonX-SSH-Proxy"

echo "Installing DragonX into $INSTALL_DIR..."

# Update apt and install dependencies
if command -v apt >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y git unzip wget screen
fi

# Fetch code
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Existing repo detected. Pulling latest..."
  git -C "$INSTALL_DIR" pull --rebase --autostash || true
else
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# Ensure executables are present & executable
chmod +x "$INSTALL_DIR/proxy.sh" 2>/dev/null || true
chmod +x "$INSTALL_DIR/dragon_go-ARM" 2>/dev/null || true
chmod +x "$INSTALL_DIR/dragon_go-x86" 2>/dev/null || true

# Create global command
sudo ln -sf "$INSTALL_DIR/proxy.sh" /usr/local/bin/dragonx

echo "✅ Installation finished! Use 'dragonx' to open the menu."
echo "Tip: Start ports from the menu; each port runs as its own systemd service."
