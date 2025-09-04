#!/usr/bin/env bash
# install.sh - Install zsh-filepg

set -euo pipefail

echo "Installing zsh-filepg..."

INSTALL_DIR="${HOME}/.zsh-filepg"
SCRIPT_URL="https://raw.githubusercontent.com/2O48/zsh-filepg/main/filepg.zsh"
INSTALL_SCRIPT="${INSTALL_DIR}/filepg.zsh"

mkdir -p "$INSTALL_DIR"

echo "Downloading filepg.zsh..."
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_SCRIPT"

ZSHRC="${HOME}/.zshrc"
if ! grep -q "zsh-filepg/filepg.zsh" "$ZSHRC" 2>/dev/null; then
  echo "" >> "$ZSHRC"
  echo "# Load zsh-filepg (cppg/mvpg/rmpg)" >> "$ZSHRC"
  echo "source $INSTALL_SCRIPT" >> "$ZSHRC"
  echo "Added source to ~/.zshrc"
else
  echo "Source already in ~/.zshrc"
fi

echo ""
echo "Installation complete!"
echo "Please run: source ~/.zshrc or restart your terminal"
echo ""
echo "Examples:"
echo "  cppg --x='*.tmp' /src/* /dst/"
echo "  mvpg file.txt /backup/"
echo "  rmpg --x='*.log' /tmp/*"