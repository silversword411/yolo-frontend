#!/bin/bash
# uninstall.sh — Revert a TRMM server from multi-frontend back to standard production setup.
#
# Usage:
#   sudo ./uninstall.sh
#
# What it does:
#   1. Restores original /var/www/rmm/dist from backup
#   2. Restores original Django + Vue files from backup
#   3. Removes CLI tool symlinks from /usr/local/bin
#   4. Restarts all TRMM services
set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/yolo.conf"

STATE_FILE="$SCRIPT_DIR/.yolo-state"

# ---------- Phase 0: Guards ----------

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: uninstall.sh must be run with sudo."
    echo "Usage: sudo $0"
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
echo "========================================"

# Verify backup directory exists
if [ ! -d "$backup_dir" ]; then
    echo "Error: Backup directory not found: $backup_dir"
    echo "Cannot safely uninstall without backups."
    exit 1
fi

# ---------- Phase 1: Restore dist from backup ----------

echo ""
echo "Restoring frontend dist from backup..."
if [ -d "$backup_dir/dist" ]; then
    # Remove symlink or existing dist
    rm -rf "$DIST_DIR"
    # Remove versions directory
    rm -rf "$VERSIONS_DIR"
    # Restore original dist
    cp -r "$backup_dir/dist" "$DIST_DIR"
    chown -R root:root "$DIST_DIR"
    echo "  Restored: $DIST_DIR"
else
    echo "  Warning: backup dist not found at $backup_dir/dist"
    # Fallback: if dist is a symlink, copy the active version back
    if [ -L "$DIST_DIR" ]; then
        ACTIVE_PATH=$(readlink -f "$DIST_DIR")
        rm "$DIST_DIR"
        cp -r "$ACTIVE_PATH" "$DIST_DIR"
        rm -rf "$VERSIONS_DIR"
        chown -R root:root "$DIST_DIR"
        echo "  Restored from active version (no backup dist found)."
    fi
fi

# ---------- Phase 2: Restore Django files ----------

echo ""
echo "Restoring Django files from backup..."
if [ -f "$backup_dir/views.py" ]; then
    cp "$backup_dir/views.py" "$core_views"
    echo "  Restored: $core_views"
else
    echo "  Warning: backup views.py not found"
fi

if [ -f "$backup_dir/urls.py" ]; then
    cp "$backup_dir/urls.py" "$core_urls"
    echo "  Restored: $core_urls"
else
    echo "  Warning: backup urls.py not found"
fi

# ---------- Phase 3: Restore frontend source file ----------

echo ""
echo "Restoring MainLayout.vue from backup..."
if [ -f "$backup_dir/MainLayout.vue" ]; then
    if [ -d "$(dirname "$mainlayout")" ]; then
        cp "$backup_dir/MainLayout.vue" "$mainlayout"
        echo "  Restored: $mainlayout"
    else
        echo "  Skipped: target directory does not exist: $(dirname "$mainlayout")"
    fi
else
    echo "  Warning: backup MainLayout.vue not found"
fi

# ---------- Phase 4: Remove CLI symlinks ----------

echo ""
echo "Removing CLI symlinks..."
rm -f /usr/local/bin/trmm-frontend-build
rm -f /usr/local/bin/trmm-frontend-versions
rm -f /usr/local/bin/trmm-frontend-repo
echo "  Done."

# ---------- Phase 5: Restart TRMM services ----------

echo ""
echo "Restarting TRMM services..."
systemctl restart rmm.service
systemctl restart daphne.service
systemctl restart celery.service
systemctl restart celerybeat.service
echo "  Services restarted."

# ---------- Phase 6: Clean up state ----------

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
echo "  Cloned repos preserved at: $repos_dir"
echo "  To remove them: rm -rf $repos_dir"
echo ""
echo "  Server is back to standard production frontend."
echo "========================================"
