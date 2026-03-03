#!/bin/bash
# install.sh — Set up multi-frontend version switching on a production TRMM server.
#
# Usage:
#   sudo ./install.sh            # First-time install
#   sudo ./install.sh --force    # Reinstall (overwrites previous state)
#
# What it does:
#   1. Backs up original Django + Vue files
#   2. Migrates /var/www/rmm/dist to a versioned symlink structure
#   3. Patches Django API (views.py, urls.py) with version-switching endpoints
#   4. Patches frontend (MainLayout.vue) with right-click version menu
#   5. Symlinks CLI tools (trmm-frontend-build, trmm-frontend-versions) to /usr/local/bin
#   6. Restarts Django services
#   7. Builds and deploys the current frontend as the initial "main" version
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/yolo.conf"

STATE_FILE="$SCRIPT_DIR/.yolo-state"
BACKUP_BASE="$SCRIPT_DIR/backups"
PATCHES_DIR="$SCRIPT_DIR/patches"

# ---------- Phase 0: Guards ----------

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: install.sh must be run with sudo."
    echo "Usage: sudo $0 [--force]"
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$1" != "--force" ]; then
    echo "Error: yolo-frontend is already installed."
    echo "  Installed at: $(grep 'installed_at' "$STATE_FILE" | cut -d= -f2)"
    echo "  Run with --force to reinstall, or run uninstall.sh first."
    exit 1
fi

# ---------- Phase 1: Detect TRMM installation ----------

CORE_VIEWS="$TRMM_API_DIR/core/views.py"
CORE_URLS="$TRMM_API_DIR/core/urls.py"
MAINLAYOUT="$FRONTEND_SRC/src/layouts/MainLayout.vue"

echo "========================================"
echo "yolo-frontend installer"
echo "========================================"
echo "TRMM API:    $TRMM_API_DIR"
echo "Frontend:    $FRONTEND_SRC"
echo "Versions:    $VERSIONS_DIR"
echo "Dist:        $DIST_DIR"
echo "========================================"

for f in "$CORE_VIEWS" "$CORE_URLS" "$MAINLAYOUT"; do
    if [ ! -f "$f" ]; then
        echo "Error: Required file not found: $f"
        echo "Check yolo.conf paths and try again."
        exit 1
    fi
done

# ---------- Phase 2: Backup original files ----------

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

cp "$CORE_VIEWS" "$BACKUP_DIR/views.py"
cp "$CORE_URLS" "$BACKUP_DIR/urls.py"
cp "$MAINLAYOUT" "$BACKUP_DIR/MainLayout.vue"

echo "Backed up original files to: $BACKUP_DIR"

# ---------- Phase 3: Filesystem migration ----------

if [ -L "$DIST_DIR" ]; then
    echo "Filesystem already in versioned mode (dist is symlink). Skipping migration."
else
    echo "Running filesystem migration..."
    bash "$SCRIPT_DIR/frontend-migrate-to-versioned.sh"
fi

# ---------- Phase 4: Patch Django views.py ----------

echo ""
echo "Patching Django views.py..."
if grep -q "GetFrontendVersions" "$CORE_VIEWS"; then
    echo "  Already patched, skipping."
else
    patch --forward --batch -p1 -d "$TRMM_API_DIR/../.." "$CORE_VIEWS" < "$PATCHES_DIR/core-views.patch"
    echo "  Done."
fi

# ---------- Phase 5: Patch Django urls.py ----------

echo "Patching Django urls.py..."
if grep -q "frontendversions" "$CORE_URLS"; then
    echo "  Already patched, skipping."
else
    patch --forward --batch -p1 -d "$TRMM_API_DIR/../.." "$CORE_URLS" < "$PATCHES_DIR/core-urls.patch"
    echo "  Done."
fi

# ---------- Phase 6: Patch MainLayout.vue ----------

echo "Patching MainLayout.vue..."
if grep -q "loadFrontendVersions" "$MAINLAYOUT"; then
    echo "  Already patched, skipping."
else
    patch --forward --batch -p1 -d "$FRONTEND_SRC" "$MAINLAYOUT" < "$PATCHES_DIR/mainlayout-vue.patch"
    echo "  Done."
fi

# ---------- Phase 7: Symlink CLI tools ----------

echo ""
echo "Linking CLI tools to /usr/local/bin..."
ln -sf "$SCRIPT_DIR/trmm-frontend-build" /usr/local/bin/trmm-frontend-build
ln -sf "$SCRIPT_DIR/trmm-frontend-versions" /usr/local/bin/trmm-frontend-versions
echo "  trmm-frontend-build -> $SCRIPT_DIR/trmm-frontend-build"
echo "  trmm-frontend-versions -> $SCRIPT_DIR/trmm-frontend-versions"

# ---------- Phase 8: Restart Django services ----------

echo ""
echo "Restarting Django services..."
systemctl restart rmm.service
systemctl restart daphne.service
echo "  Services restarted."

# ---------- Phase 9: Build and deploy frontend ----------

echo ""
echo "Building and deploying frontend as 'main' version..."
sudo -u "$DEPLOY_USER" bash -c "
    cd '$FRONTEND_SRC'
    '$SCRIPT_DIR/trmm-frontend-build' --name main --activate
"

# ---------- Phase 10: Write state file ----------

cat > "$STATE_FILE" <<EOF
installed_at=$TIMESTAMP
backup_dir=$BACKUP_DIR
trmm_api_dir=$TRMM_API_DIR
frontend_src=$FRONTEND_SRC
core_views=$CORE_VIEWS
core_urls=$CORE_URLS
mainlayout=$MAINLAYOUT
EOF

echo ""
echo "========================================"
echo "yolo-frontend installed successfully!"
echo "========================================"
echo ""
echo "  CLI tools available:"
echo "    trmm-frontend-build          Build & deploy a frontend version"
echo "    trmm-frontend-versions       List/switch/remove versions"
echo ""
echo "  Right-click the version number in the dashboard to switch versions."
echo ""
echo "  Backup: $BACKUP_DIR"
echo "  To uninstall: sudo $SCRIPT_DIR/uninstall.sh"
echo "========================================"
