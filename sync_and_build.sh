#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

WIN_DIR="/mnt/c/AntiDarkSword"
WSL_DIR="$HOME/AntiDarkSword"
WIN_PACKAGES="$WIN_DIR/packages"

echo "→ [0/4] Preparing environment..."
rm -rf "$WSL_DIR/output"
mkdir -p "$WSL_DIR/output"

echo "→ [1/4] Cleaning Windows packages..."
rm -rf "$WIN_PACKAGES"
mkdir -p "$WIN_PACKAGES"

echo "→ [2/4] Syncing WSL workspace..."
# Exclude .git because Windows is now the sole Git master
rsync -a --delete --exclude='.git/' --exclude='.theos/' --exclude='packages/' --exclude='output/' "$WIN_DIR/" "$WSL_DIR/"

echo "→ [3/4] Fixing permissions & Building..."
find "$WSL_DIR" -type d -exec chmod 755 {} \;
find "$WSL_DIR" -type f -exec chmod 644 {} \;
[ -d "$WSL_DIR/layout/DEBIAN" ] && chmod -R 755 "$WSL_DIR/layout/DEBIAN"

chmod +x "$WSL_DIR/build_all.sh" "$WSL_DIR/sync_and_build.sh" "$WSL_DIR/deploy.sh" 2>/dev/null || true
cd "$WSL_DIR"
./build_all.sh

echo "→ [4/4] Exporting directly to Windows..."
for file in "$WSL_DIR/output/"*.{deb,dylib}; do
    cp "$file" "$WIN_PACKAGES/"
done

echo "→ Clean up WSL build artifacts..."
rm -rf "$WSL_DIR/output"

echo "→ Done. Build exported to Windows."