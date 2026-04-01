# yolo-frontend

Multi-version frontend system for Tactical RMM. Run multiple frontend builds from different repos and branches side by side, switching between them instantly.

## How It Works

Each frontend build is stored as a named version under `/var/www/rmm/versions/`. A symlink at `/var/www/rmm/dist` points to the active one. Nginx follows the symlink transparently — no reload needed.

```
~/yolo-frontend/                    (this repo — your workspace)
  repos/
    tacticalrmm-web/               (cloned frontend repo)
    my-fork/                       (another repo)
  installyolo.sh, trmm-frontend-*, ...

/var/www/rmm/
  dist -> versions/main/           (symlink to active version)
  versions/
    main/                          (stable build)
    frontend-rework/               (branch build)
    my-fork--feature-x/            (build from another repo)
```

Switch versions from:

- **Dashboard** — right-click the version number in the header
- **VSCode** — Command Palette > "Run Task"
- **Terminal** — `trmm-frontend-versions switch <name>`

---

## Prerequisites

A working [Tactical RMM](https://github.com/amidaware/tacticalrmm) installation.

## Setup

One command to bootstrap everything:

```bash
wget https://raw.githubusercontent.com/silversword411/yolo-frontend/master/installyolo.sh
chmod +x installyolo.sh
sudo ./installyolo.sh
```

This clones the yolo-frontend repo into `~/yolo-frontend/`, then runs the full install.

Alternatively, clone first and customize `yolo.conf` before installing:

```bash
git clone <repo-url> ~/yolo-frontend
cd ~/yolo-frontend
# Edit yolo.conf to set DEFAULT_REPO_URL, DEFAULT_REPO_NAME, etc.
sudo ./installyolo.sh
```

The installer:

1. Clones the default frontend repo into `repos/`
2. Backs up original Django and Vue files
3. Migrates `/var/www/rmm/dist` to a versioned symlink structure
4. Patches the Django API with version-switching endpoints
5. Patches the frontend with a right-click version menu
6. Symlinks CLI tools to `/usr/local/bin`
7. Restarts Django services
8. Builds and deploys the initial "main" version

Verify:

```bash
trmm-frontend-versions list
# * main  (active)
```

---

## Managing Repos

Frontend source repos are cloned under `~/yolo-frontend/repos/`. The default repo is cloned by `installyolo.sh`. Add more any time:

```bash
# Add a repo (name defaults to URL basename)
trmm-frontend-repo add https://github.com/user/tacticalrmm-web.git my-fork

# List all repos
trmm-frontend-repo list

# Fetch latest from all remotes
trmm-frontend-repo update

# Fetch a specific repo
trmm-frontend-repo update my-fork

# Remove a repo
trmm-frontend-repo remove my-fork
```

After adding a repo, switch branches and build:

```bash
cd ~/yolo-frontend/repos/my-fork
git checkout feature-branch
trmm-frontend-build
```

---

## Building Versions

```bash
# Build default repo, current branch (version name = branch name)
trmm-frontend-build

# Build from a specific repo
trmm-frontend-build --repo my-fork

# Custom version name
trmm-frontend-build --name my-experiment

# Build and immediately activate
trmm-frontend-build --activate
```

Version labels:

- **Single repo**: label = branch name (e.g., `develop`)
- **Multiple repos**: label = `reponame--branchname` (e.g., `my-fork--develop`)
- **`--name`**: always overrides the automatic label

The build script auto-detects which repo you're in if you `cd` into `repos/<name>/`.

### Typical workflow

```bash
cd ~/yolo-frontend/repos/tacticalrmm-web
git checkout my-feature-branch
trmm-frontend-build --activate
```

---

## Managing Versions

```bash
# List all versions (marks the active one)
trmm-frontend-versions list

# Show which version is currently live
trmm-frontend-versions active

# Switch the live version
trmm-frontend-versions switch frontend-rework

# Remove a version (cannot remove the active one)
trmm-frontend-versions remove old-experiment
```

---

## VSCode Tasks

Open the Command Palette (`Ctrl+Shift+P`) > **Tasks: Run Task**:

| Task                                   | What it does                                                     |
| -------------------------------------- | ---------------------------------------------------------------- |
| **Frontend: Dev Server Start (9000)**  | Start dev server for a repo                                      |
| **Frontend: Dev Server Stop**          | Stop the dev server                                              |
| **Frontend: Build & Deploy**           | Build a branch, deploy to versions. Does NOT change what's live. |
| **Frontend: Build, Deploy & Activate** | Build and immediately switch the live version.                   |
| **Frontend: Switch Version**           | Switch the active version.                                       |
| **Frontend: List Versions**            | List all deployed versions.                                      |
| **Frontend: Delete Version**           | Remove a deployed version.                                       |
| **Frontend: Add Repo**                 | Clone a new frontend repo.                                       |
| **Frontend: List Repos**               | List all cloned repos.                                           |
| **Frontend: Update Repos**             | Fetch latest from all repo remotes.                              |

---

## Dashboard Switching

1. Log into the TacticalRMM dashboard
2. Right-click the version number in the header (e.g., "v1.4.0")
3. Select a version from the context menu
4. Page reloads with the new frontend

API endpoints (requires Core Settings permissions):

- `GET /core/frontendversions/` — list versions
- `POST /core/frontendversions/switch/` — switch version

---

## Files

| File                     | Purpose                                      |
| ------------------------ | -------------------------------------------- |
| `yolo.conf`              | Configuration (paths, default repo, users)   |
| `installyolo.sh`             | Install on a production TRMM server          |
| `uninstallyolo.sh`           | Revert all changes, restore to stock         |
| `trmm-frontend-build`    | Build and deploy a branch as a named version |
| `trmm-frontend-versions` | Version management (list/switch/remove)      |
| `trmm-frontend-repo`     | Repo management (add/list/remove/update)     |
| `patches/`               | Django API and Vue frontend patches          |
| `.vscode/`               | VSCode tasks, settings, extensions           |

---

## Uninstalling

```bash
sudo ~/yolo-frontend/uninstallyolo.sh
```

This reverts everything: restores original files from backup, removes the versioned symlink structure, removes CLI symlinks, restarts services. Cloned repos in `repos/` are preserved (delete manually if desired).

---

## Troubleshooting

**Frontend returns 404 / blank page after switching:**

```bash
ls -la /var/www/rmm/dist
readlink -f /var/www/rmm/dist
ls /var/www/rmm/dist/index.html
```

**Permission denied when switching from the UI:**

```bash
ls -la /var/www/rmm/
sudo chown -R tacadmin:www-data /var/www/rmm/
```

**Build script can't find env-config.js:**

```bash
cat /var/www/rmm-bak/dist/env-config.js
```

**Version not appearing in right-click menu:**

```bash
ls /var/www/rmm/versions/
curl -H "Authorization: Token YOUR_TOKEN" https://api.your-domain.com/core/frontendversions/
```
