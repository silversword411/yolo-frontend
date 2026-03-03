#!/bin/bash
# uninstall.sh — Revert a TRMM server from multi-frontend back to standard production setup.
#
# Usage:
#   sudo ./uninstall.sh                 # Full uninstall (includes frontend rebuild)
#   sudo ./uninstall.sh --skip-rebuild  # Uninstall without rebuilding frontend
#
# What it does:
#   1. Reverts /var/www/rmm/dist from versioned symlink back to a regular directory
#   2. Restores original Django + Vue files from backup
#   3. Removes CLI tool symlinks from /usr/local/bin
#   4. Restarts Django services
#   5. Rebuilds and deploys the original frontend (unless --skip-rebuild)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/yolo.conf"

STATE_FILE="$SCRIPT_DIR/.yolo-state"

# ---------- Phase 0: Guards ----------

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: uninstall.sh must be run with sudo."
    echo "Usage: sudo $0 [--skip-rebuild]"
    exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
    echo "Error: yolo-frontend does not appear to be installed (no .yolo-state file)."
    exit 1
fi

# Source state file to get backup paths
source "$STATE_FILE"

echo "========================================"
echo "yolo-frontend uninstaller"
echo "========================================"
echo "Backup from:  $backup_dir"
echo "TRMM API:     $trmm_api_dir"
echo "Frontend:     $frontend_src"
echo "========================================"

# Verify backup directory exists
if [ ! -d "$backup_dir" ]; then
    echo "Error: Backup directory not found: $backup_dir"
    echo "Cannot safely uninstall without backups."
    exit 1
fi

# ---------- Phase 1: Revert filesystem ----------

echo ""
echo "Reverting filesystem to standard structure..."
if [ -L "$DIST_DIR" ]; then
    bash "$SCRIPT_DIR/frontend-revert-to-prod.sh"
else
    echo "  dist is already a regular directory, skipping."
fi

# ---------- Phase 2: Restore Django files ----------

echo ""
echo "Restoring Django views.py from backup..."
if [ -f "$backup_dir/views.py" ]; then
    cp "$backup_dir/views.py" "$core_views"
    echo "  Restored: $core_views"
else
    echo "  Warning: backup views.py not found at $backup_dir/views.py"
fi

echo "Restoring Django urls.py from backup..."
if [ -f "$backup_dir/urls.py" ]; then
    cp "$backup_dir/urls.py" "$core_urls"
    echo "  Restored: $core_urls"
else
    echo "  Warning: backup urls.py not found at $backup_dir/urls.py"
fi

# ---------- Phase 3: Restore frontend file ----------

echo ""
echo "Restoring MainLayout.vue from backup..."
if [ -f "$backup_dir/MainLayout.vue" ]; then
    cp "$backup_dir/MainLayout.vue" "$mainlayout"
    echo "  Restored: $mainlayout"
else
    echo "  Warning: backup MainLayout.vue not found at $backup_dir/MainLayout.vue"
fi

# ---------- Phase 4: Remove CLI symlinks ----------

echo ""
echo "Removing CLI symlinks..."
rm -f /usr/local/bin/trmm-frontend-build
rm -f /usr/local/bin/trmm-frontend-versions
echo "  Removed: /usr/local/bin/trmm-frontend-build"
echo "  Removed: /usr/local/bin/trmm-frontend-versions"

# ---------- Phase 5: Restart Django services ----------

echo ""
echo "Restarting Django services..."
systemctl restart rmm.service
systemctl restart daphne.service
echo "  Services restarted."

# ---------- Phase 6: Rebuild frontend ----------

if [ "$1" != "--skip-rebuild" ]; then
    echo ""
    echo "Rebuilding frontend (this may take a couple minutes)..."
    sudo -u "$DEPLOY_USER" bash -c "
        cd '$frontend_src'
        npm run build
    "

    # Copy built files to dist
    rm -rf "$DIST_DIR"/*
    cp -r "$frontend_src/dist/"* "$DIST_DIR/"

    # Restore env-config.js
    if [ -f "$ENV_CONFIG_SRC" ]; then
        cp "$ENV_CONFIG_SRC" "$DIST_DIR/env-config.js"
    fi

    # Restore ownership
    chown -R root:root "$DIST_DIR"

    echo "  Frontend rebuilt and deployed."
else
    echo ""
    echo "Skipping frontend rebuild (--skip-rebuild)."
    echo "You will need to manually rebuild and deploy the frontend."
fi

# ---------- Phase 7: Clean up state ----------

rm -f "$STATE_FILE"

echo ""
echo "========================================"
echo "yolo-frontend uninstalled successfully."
echo "========================================"
echo ""
echo "  Original files restored from: $backup_dir"
echo "  Backups preserved (delete manually if desired):"
echo "    rm -rf $backup_dir"
echo ""
echo "  Server is back to standard single-version frontend."
echo "  Use frontend-rebuild.sh for the original build process."
echo "========================================"
