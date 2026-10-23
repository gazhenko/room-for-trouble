#!/usr/bin/env bash
# Optional: lets the build machine push new builds and read game logs over SSH.
#   bash <(curl -fsSL <build machine>:8765/ssh)
# Adds the build machine's public key for the deck user and starts sshd, which
# asks for the Deck's sudo password. Undo: sudo systemctl disable --now sshd
set -euo pipefail
KEY='@KEY@'
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
grep -qxF "$KEY" "$HOME/.ssh/authorized_keys" || echo "$KEY" >> "$HOME/.ssh/authorized_keys"
echo "Starting SSH needs the Deck's password. If you have never set one, press"
echo "Ctrl+C, run  passwd  to choose one, then run this command again."
sudo systemctl enable --now sshd < /dev/tty
echo "SSH is on. Turn it off any time with: sudo systemctl disable --now sshd"
