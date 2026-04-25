#!/usr/bin/env bash
set -euo pipefail

WIN_DIR="/mnt/c/AntiDarkSword"

# 1. Local Sync & Build
"/home/owner/sync_and_build.sh"

# 2. Git Operations → Target WINDOWS directory directly
cd "$WIN_DIR"

if [ ! -d ".git" ]; then
    echo "→ [Git] Error: No .git directory found in $WIN_DIR."
    exit 1
fi

echo "→ [Git] Configuring environment..."
git config --global --add safe.directory "$WIN_DIR"
# Prevent Git from throwing errors over Windows vs Linux file permission differences
git config core.filemode false

echo "→ [Git] Ensuring packages folder is untracked..."
git rm -r -f --cached packages/ 2>/dev/null || true

echo "→ [Git] Staging source files..."
git add -A

if git diff --staged --quiet; then
    echo "→ [Git] No source changes to push."
else
    echo "→ [Git] Changes detected. Committing..."
    git commit -m "Auto-build → Source update"
    
    echo "→ [Git] Syncing upstream history (Pull)..."
    git rebase --abort 2>/dev/null || true
    git pull --rebase origin main -X ours
    
    echo "→ [Git] Uploading to repository (Push)..."
    git push origin main
fi