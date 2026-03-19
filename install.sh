#!/bin/bash
# install.sh — Set up multi-frontend version switching on a production TRMM server.
#
# Usage (bootstrap — run from anywhere):
#   wget https://raw.githubusercontent.com/<user>/yolo-frontend/main/install.sh
#   chmod +x install.sh
#   sudo ./install.sh
#
# Usage (from inside the repo):
#   sudo ./install.sh            # First-time install
#   sudo ./install.sh --force    # Reinstall (overwrites previous state)
#
# What it does:
#   1. Clones the yolo-frontend repo (if running standalone)
#   2. Clones the default frontend repo
#   3. Backs up original Django + Vue files
#   4. Migrates /var/www/rmm/dist to a versioned symlink structure
#   5. Patches Django API (views.py, urls.py) with version-switching endpoints
#   6. Patches frontend (MainLayout.vue) with right-click version menu
#   7. Symlinks CLI tools to /usr/local/bin
#   8. Restarts Django services
#   9. Builds and deploys the current frontend as the initial "main" version
set -e

# ---------- Bootstrap: clone repo if running standalone ----------

YOLO_REPO_URL="${YOLO_REPO_URL:-https://github.com/<user>/yolo-frontend.git}"
YOLO_INSTALL_DIR="${YOLO_INSTALL_DIR:-$HOME/yolo-frontend}"

if [ ! -f "$(dirname "$(readlink -f "$0")")/yolo.conf" ]; then
    echo "========================================"
    echo "yolo-frontend bootstrap"
    echo "========================================"

    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: install.sh must be run with sudo."
        echo "Usage: sudo $0"
        exit 1
    fi

    DEPLOY_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    DEPLOY_HOME=$(eval echo "~$DEPLOY_USER")
    YOLO_INSTALL_DIR="$DEPLOY_HOME/yolo-frontend"

    echo ""
    echo "This will:"
    echo "  1. Clone yolo-frontend repo to $YOLO_INSTALL_DIR"
    echo "  2. Clone the default frontend source repo"
    echo "  3. Patch Django API and Vue frontend for version switching"
    echo "  4. Migrate /var/www/rmm/dist to a versioned symlink structure"
    echo "  5. Build and deploy the initial frontend version"
    echo ""
    echo "  Repo:   $YOLO_REPO_URL"
    echo "  User:   $DEPLOY_USER"
    echo ""
    read -p "Continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""

    if [ -d "$YOLO_INSTALL_DIR" ]; then
        echo "yolo-frontend repo already exists at $YOLO_INSTALL_DIR"
        echo "Running install from existing repo..."
    else
        echo "Cloning yolo-frontend -> $YOLO_INSTALL_DIR"
        sudo -u "$DEPLOY_USER" git clone "$YOLO_REPO_URL" "$YOLO_INSTALL_DIR"
    fi

    echo "Handing off to $YOLO_INSTALL_DIR/install.sh..."
    echo ""
    exec "$YOLO_INSTALL_DIR/install.sh" "$@"
fi

# ---------- Normal install (running from inside the repo) ----------

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
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
DEFAULT_REPO_PATH="$REPOS_DIR/$DEFAULT_REPO_NAME"
MAINLAYOUT="$DEFAULT_REPO_PATH/src/layouts/MainLayout.vue"

echo "========================================"
echo "yolo-frontend installer"
echo "========================================"
echo "TRMM API:    $TRMM_API_DIR"
echo "Repos:       $REPOS_DIR"
echo "Default:     $DEFAULT_REPO_NAME ($DEFAULT_REPO_URL)"
echo "Versions:    $VERSIONS_DIR"
echo "Dist:        $DIST_DIR"
echo "========================================"

# Validate Django files exist
for f in "$CORE_VIEWS" "$CORE_URLS"; do
    if [ ! -f "$f" ]; then
        echo "Error: Required file not found: $f"
        echo "Check yolo.conf paths and try again."
        exit 1
    fi
done

# ---------- Phase 1b: Detect TRMM version ----------

TRMM_VERSION=$(grep -oP 'TRMM_VERSION\s*=\s*"\K[^"]+' "$TRMM_API_DIR/tacticalrmm/settings.py")
PROD_VERSION_NAME="PROD-v${TRMM_VERSION}"
echo "TRMM Version: $TRMM_VERSION  (will preserve current frontend as $PROD_VERSION_NAME)"

# ---------- Phase 2: Clone default frontend repo ----------

echo ""
echo "Setting up default frontend repo..."
mkdir -p "$REPOS_DIR"

if [ -d "$DEFAULT_REPO_PATH" ]; then
    echo "  Repo already exists at $DEFAULT_REPO_PATH, skipping clone."
else
    echo "  Cloning $DEFAULT_REPO_URL -> $DEFAULT_REPO_PATH"
    sudo -u "$DEPLOY_USER" git clone "$DEFAULT_REPO_URL" "$DEFAULT_REPO_PATH"
fi

echo "  Running npm install..."
sudo -u "$DEPLOY_USER" bash -c "cd '$DEFAULT_REPO_PATH' && npm install"

# Validate frontend file exists after clone
if [ ! -f "$MAINLAYOUT" ]; then
    echo "Error: MainLayout.vue not found at $MAINLAYOUT"
    echo "Check that the repo was cloned correctly."
    exit 1
fi

# ---------- Phase 3: Backup original files ----------

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

cp "$CORE_VIEWS" "$BACKUP_DIR/views.py"
cp "$CORE_URLS" "$BACKUP_DIR/urls.py"
cp "$MAINLAYOUT" "$BACKUP_DIR/MainLayout.vue"

# Backup the original dist folder
if [ -d "$DIST_DIR" ] && [ ! -L "$DIST_DIR" ]; then
    echo "  Backing up $DIST_DIR..."
    cp -r "$DIST_DIR" "$BACKUP_DIR/dist"
elif [ -f "$STATE_FILE" ]; then
    # --force reinstall: dist is already a symlink, carry forward the original backup
    PREV_BACKUP=$(grep 'backup_dir=' "$STATE_FILE" | cut -d= -f2)
    if [ -d "$PREV_BACKUP/dist" ]; then
        echo "  Carrying forward dist backup from $PREV_BACKUP..."
        cp -r "$PREV_BACKUP/dist" "$BACKUP_DIR/dist"
    fi
fi

echo "Backed up original files to: $BACKUP_DIR"

# ---------- Phase 4: Filesystem migration ----------

if [ -L "$DIST_DIR" ]; then
    echo "Filesystem already in versioned mode (dist is symlink). Skipping migration."
else
    echo "Migrating to versioned frontend structure..."
    mkdir -p "$VERSIONS_DIR"
    mv "$DIST_DIR" "$VERSIONS_DIR/$PROD_VERSION_NAME"
    ln -s "$VERSIONS_DIR/$PROD_VERSION_NAME" "$DIST_DIR"
    chown -R "$DEPLOY_USER:$WEB_GROUP" "$(dirname "$DIST_DIR")/"
    chown -h "$DEPLOY_USER:$WEB_GROUP" "$DIST_DIR"
    echo "  Done. Preserved production frontend as: $PROD_VERSION_NAME"
    echo "  Symlink: $DIST_DIR -> $VERSIONS_DIR/$PROD_VERSION_NAME"
fi

# ---------- Phase 5: Patch Django views.py ----------

echo ""
echo "Patching Django views.py..."
if grep -q "GetFrontendVersions" "$CORE_VIEWS"; then
    echo "  Already patched, skipping."
else
    patch --forward --batch -p1 -d "$TRMM_API_DIR/../.." < "$PATCHES_DIR/core-views.patch"
    echo "  Done."
fi

# ---------- Phase 6: Patch Django urls.py ----------

echo "Patching Django urls.py..."
if grep -q "frontendversions" "$CORE_URLS"; then
    echo "  Already patched, skipping."
else
    patch --forward --batch -p1 -d "$TRMM_API_DIR/../.." < "$PATCHES_DIR/core-urls.patch"
    echo "  Done."
fi

# ---------- Phase 7: Patch MainLayout.vue ----------

echo "Patching MainLayout.vue..."
if grep -q "loadFrontendVersions" "$MAINLAYOUT"; then
    echo "  Already patched, skipping."
else
    patch --forward --batch -p1 -d "$DEFAULT_REPO_PATH" < "$PATCHES_DIR/mainlayout-vue.patch"
    echo "  Done."
fi

# ---------- Phase 8: Symlink CLI tools ----------

echo ""
echo "Linking CLI tools to /usr/local/bin..."
ln -sf "$SCRIPT_DIR/trmm-frontend-build" /usr/local/bin/trmm-frontend-build
ln -sf "$SCRIPT_DIR/trmm-frontend-versions" /usr/local/bin/trmm-frontend-versions
ln -sf "$SCRIPT_DIR/trmm-frontend-repo" /usr/local/bin/trmm-frontend-repo
echo "  trmm-frontend-build -> $SCRIPT_DIR/trmm-frontend-build"
echo "  trmm-frontend-versions -> $SCRIPT_DIR/trmm-frontend-versions"
echo "  trmm-frontend-repo -> $SCRIPT_DIR/trmm-frontend-repo"

# ---------- Phase 9: Restart TRMM services ----------

echo ""
echo "Restarting TRMM services..."
systemctl restart rmm.service
systemctl restart daphne.service
systemctl restart celery.service
systemctl restart celerybeat.service
echo "  Services restarted."

# ---------- Phase 10: Build and deploy frontend ----------

echo ""
echo "Building and deploying frontend from default repo..."
sudo -u "$DEPLOY_USER" bash -c "
    '$SCRIPT_DIR/trmm-frontend-build' --repo '$DEFAULT_REPO_NAME' --activate
"

# ---------- Phase 10b: Clone, patch, and build extra repos ----------

if [ -n "$EXTRA_REPOS" ]; then
    echo ""
    echo "Setting up extra repos..."
    for EXTRA_ENTRY in $EXTRA_REPOS; do
        # Parse URL@branch format
        EXTRA_URL="${EXTRA_ENTRY%%@*}"
        EXTRA_BRANCH=""
        if [[ "$EXTRA_ENTRY" == *@* ]]; then
            EXTRA_BRANCH="${EXTRA_ENTRY#*@}"
        fi

        EXTRA_NAME=$(repo_name_from_url "$EXTRA_URL")
        EXTRA_PATH="$REPOS_DIR/$EXTRA_NAME"
        EXTRA_MAINLAYOUT="$EXTRA_PATH/src/layouts/MainLayout.vue"

        if [ -d "$EXTRA_PATH" ]; then
            echo "  Repo '$EXTRA_NAME' already exists, skipping clone."
        else
            CLONE_ARGS=("$EXTRA_URL" "$EXTRA_PATH")
            if [ -n "$EXTRA_BRANCH" ]; then
                CLONE_ARGS=(-b "$EXTRA_BRANCH" "${CLONE_ARGS[@]}")
            fi
            echo "  Cloning $EXTRA_URL${EXTRA_BRANCH:+ (branch: $EXTRA_BRANCH)} -> $EXTRA_PATH"
            sudo -u "$DEPLOY_USER" git clone "${CLONE_ARGS[@]}"
        fi

        echo "  Running npm install for $EXTRA_NAME..."
        sudo -u "$DEPLOY_USER" bash -c "cd '$EXTRA_PATH' && npm install"

        # Patch MainLayout.vue for version switching (best-effort)
        if [ -f "$EXTRA_MAINLAYOUT" ] && ! grep -q "loadFrontendVersions" "$EXTRA_MAINLAYOUT"; then
            echo "  Patching MainLayout.vue for $EXTRA_NAME..."
            if patch --forward --batch -p1 -d "$EXTRA_PATH" < "$PATCHES_DIR/mainlayout-vue.patch" 2>/dev/null; then
                echo "    Done."
            else
                echo "    Warning: Patch did not apply cleanly to $EXTRA_NAME. Version switcher may not appear in this build."
            fi
        fi

        echo "  Building $EXTRA_NAME..."
        sudo -u "$DEPLOY_USER" bash -c \
            "'$SCRIPT_DIR/trmm-frontend-build' --repo '$EXTRA_NAME'"
    done
fi

# ---------- Phase 11: Write state file ----------

cat > "$STATE_FILE" <<EOF
installed_at=$TIMESTAMP
backup_dir=$BACKUP_DIR
trmm_api_dir=$TRMM_API_DIR
repos_dir=$REPOS_DIR
default_repo_name=$DEFAULT_REPO_NAME
default_repo_path=$DEFAULT_REPO_PATH
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
echo "    trmm-frontend-repo           Manage frontend source repos"
echo ""
echo "  Right-click the version number in the dashboard to switch versions."
echo ""
echo "  Add more repos:  trmm-frontend-repo add <url> [name]"
echo "  Backup:          $BACKUP_DIR"
echo "  To uninstall:    sudo $SCRIPT_DIR/uninstall.sh"
echo "========================================"
