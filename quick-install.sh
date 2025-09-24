#!/usr/bin/env bash
set -euo pipefail

# One-liner bootstrapper: fetches the latest full installer from GitHub and runs it with sudo.
# Repo: https://github.com/skaisser/bitcoinii-node-installer

RAW_URL="https://raw.githubusercontent.com/skaisser/bitcoinii-node-installer/main/bitcoinii-full-install.sh"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$RAW_URL" | sudo bash
else
  wget -qO- "$RAW_URL" | sudo bash
fi

