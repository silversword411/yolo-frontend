# Multi-Version Frontend System

Run multiple frontend builds side by side and switch between them instantly from the dashboard.

## How It Works

Instead of a single `/var/www/rmm/dist` directory, each frontend build is stored as a named version under `/var/www/rmm/versions/`. A symlink at `/var/www/rmm/dist` points to the active one. Nginx follows the symlink transparently — no reload needed to switch.

```
/var/www/rmm/
  dist -> versions/main/          (symlink)
  versions/
    main/                         (your stable build)
    frontend-rework/              (branch build)
    custom-fields-branch/         (another branch build)
```

Switching versions = atomic symlink swap. You can do it from:
- **The dashboard** — right-click the version number in the header
- **VSCode** — Command Palette > "Run Task" > pick a Frontend task
- **The terminal** — `trmm-frontend-versions switch <name>`

---

## Initial Setup

Clone the repo and run the installer:

```bash
git clone <repo-url> ~/yolo-frontend
sudo ~/yolo-frontend/install.sh
```

The installer:
1. Backs up original Django and Vue files
2. Migrates `/var/www/rmm/dist` to a versioned symlink structure
3. Patches the Django API with version-switching endpoints
4. Patches the frontend with a right-click version menu
5. Symlinks CLI tools (`trmm-frontend-build`, `trmm-frontend-versions`) to `/usr/local/bin`
6. Restarts Django services
7. Builds and deploys the current frontend as the initial "main" version

Verify it worked:
```bash
ls -la /var/www/rmm/dist
# Should show: dist -> /var/www/rmm/versions/main
trmm-frontend-versions list
# Should show: * main  (active)
```

---

## Building and Deploying a Version

From the `tacticalrmm-web` directory, on any branch:

```bash
# Build current branch and store it (does NOT change what's live)
trmm-frontend-build

# Build with a custom name instead of the branch name
trmm-frontend-build --name my-experiment

# Build AND immediately make it the live version
trmm-frontend-build --activate
```

The script:
- Detects the git branch name automatically (sanitizes `feature/foo` to `feature-foo`)
- Runs `npm run build`
- Copies the built files to `/var/www/rmm/versions/<name>/`
- Copies `env-config.js` from `/var/www/rmm-bak/dist/env-config.js`

### Typical workflow

```bash
cd /home/tacadmin/tacticalrmm-web
git checkout my-feature-branch
trmm-frontend-build
# Now go to the dashboard, right-click the version number, and switch to "my-feature-branch"
```

---

## Managing Versions (CLI)

```bash
# List all versions (marks the active one)
trmm-frontend-versions list
#   * main  (active)
#     frontend-rework
#     custom-fields-branch

# Show which version is currently live
trmm-frontend-versions active

# Switch the live version
trmm-frontend-versions switch frontend-rework

# Remove a version (cannot remove the active one)
trmm-frontend-versions remove old-experiment
```

---

## VSCode Tasks

Open the Command Palette (`Ctrl+Shift+P`) > **Tasks: Run Task** to access these:

| Task | What it does |
|------|-------------|
| **Frontend: Build & Deploy** | Builds current branch, deploys to `versions/<branch>`. Prompts for optional custom name. Does NOT change what's live. |
| **Frontend: Build, Deploy & Activate** | Same as above, but also switches the live symlink to the new build immediately. |
| **Frontend: Switch Version** | Prompts for a version name from the deployed list, switches the live symlink. |
| **Frontend: List Versions** | Prints all deployed versions and marks the active one. |
| **Frontend: Delete Version** | Prompts for a version name, removes it (refuses if it's the active one). |

These tasks call the same shell scripts in `~/yolo-frontend/`, so the terminal and VSCode workflows are interchangeable.

---

## Switching from the Dashboard (Right-Click Menu)

1. Log into the TacticalRMM dashboard
2. Right-click the version number in the top-left header (e.g., "v1.4.0")
3. A context menu appears listing all available versions with a checkmark on the active one
4. Click any version to switch — the page reloads with the new frontend

This calls the Django API endpoints:
- `GET /core/frontendversions/` — lists versions
- `POST /core/frontendversions/switch/` — switches the symlink

Requires `Core Settings` view/edit permissions.

---

## Files Involved

| File | Purpose |
|------|---------|
| `install.sh` | Install everything on a production TRMM server |
| `uninstall.sh` | Revert all changes, restore to stock |
| `yolo.conf` | Configuration (paths, users, groups) |
| `trmm-frontend-build` | Build and deploy a branch as a named version |
| `trmm-frontend-versions` | CLI version management (list/switch/remove) |
| `frontend-migrate-to-versioned.sh` | Filesystem migration (called by install.sh) |
| `frontend-revert-to-prod.sh` | Filesystem revert (called by uninstall.sh) |
| `patches/` | Patch files for Django API and Vue frontend |

---

## Undoing Everything (Reverting to Standard Single-Version Setup)

Run the uninstaller to revert all changes:

```bash
sudo ~/yolo-frontend/uninstall.sh
```

What it does:
1. Reverts `/var/www/rmm/dist` from symlink back to a regular directory
2. Restores original Django and Vue files from backup
3. Removes CLI tool symlinks from `/usr/local/bin`
4. Restarts Django services
5. Rebuilds and deploys the original frontend (skip with `--skip-rebuild`)

After running this you're back to the original setup — single dist directory, no symlinks, no version-switching API or UI.

---

## Troubleshooting

**Frontend returns 404 / blank page after switching:**
```bash
# Check the symlink is valid
ls -la /var/www/rmm/dist
readlink -f /var/www/rmm/dist
# Make sure the target directory exists and has index.html
ls /var/www/rmm/dist/index.html
```

**Permission denied when switching versions from the UI:**
```bash
# The /var/www/rmm/ directory must be owned by tacadmin
ls -la /var/www/rmm/
# Fix if needed:
sudo chown -R tacadmin:www-data /var/www/rmm/
```

**Build script can't find env-config.js:**
```bash
# Check the backup file exists
cat /var/www/rmm-bak/dist/env-config.js
# Should contain: window._env_ = {PROD_URL: "https://api.davidthegeek.com"}
```

**Version not appearing in right-click menu:**
```bash
# Verify the version directory exists
ls /var/www/rmm/versions/
# Check the API endpoint directly
curl -H "Authorization: Token YOUR_TOKEN" https://api.davidthegeek.com/core/frontendversions/
```
