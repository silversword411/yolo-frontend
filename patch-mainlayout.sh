#!/bin/bash
# patch-mainlayout.sh — Inject yolo version-switching UI into a stock MainLayout.vue
#
# Usage: patch-mainlayout.sh <path-to-MainLayout.vue>
#
# Uses anchor-based sed/awk injection instead of patch files, so it works
# across TRMM versions as long as core anchor strings exist.
set -e

TARGET="$1"

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
    echo "Error: MainLayout.vue not found: $TARGET"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SNIPPETS_DIR="$SCRIPT_DIR/snippets"

# --- Idempotency check ---
if grep -q "loadFrontendVersions" "$TARGET"; then
    echo "  MainLayout.vue already patched, skipping."
    exit 0
fi

# --- Validate anchors exist ---
ERRORS=0
check_anchor() {
    if ! grep -q "$1" "$TARGET"; then
        echo "  ERROR: Anchor not found: $1"
        ERRORS=$((ERRORS + 1))
    fi
}

check_anchor 'text-overline q-ml-sm'
check_anchor 'import { computed, onMounted'
check_anchor 'checkWebTermPerms.*openWebTerminal'
check_anchor 'ResetPass.vue'
check_anchor 'onMounted(() =>'

if [ "$ERRORS" -gt 0 ]; then
    echo "  FAILED: $ERRORS anchor(s) not found in $TARGET"
    exit 1
fi

# --- Helper: insert file contents AFTER matching line ---
inject_after() {
    local pattern="$1" snippet_file="$2" target="$3"
    awk -v pat="$pattern" -v sfile="$snippet_file" '
        { print }
        $0 ~ pat { while ((getline line < sfile) > 0) print line; close(sfile) }
    ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
}

# --- Helper: insert file contents BEFORE matching line ---
inject_before() {
    local pattern="$1" snippet_file="$2" target="$3"
    awk -v pat="$pattern" -v sfile="$snippet_file" '
        $0 ~ pat { while ((getline line < sfile) > 0) print line; close(sfile) }
        { print }
    ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
}

# --- Anchor 1: Replace version span with context-menu version ---
# Stock line:  <span class="text-overline q-ml-sm">v{{ currentTRMMVersion }}</span>
# Result:      <span class="text-overline q-ml-sm cursor-pointer">v{{ currentTRMMVersion }}
#              (followed by snippet contents: feVersion span + context menu + closing </span>)
sed -i 's|<span class="text-overline q-ml-sm">v{{ currentTRMMVersion }}</span>|<span class="text-overline q-ml-sm cursor-pointer">v{{ currentTRMMVersion }}|' "$TARGET"
inject_after 'text-overline q-ml-sm cursor-pointer' "$SNIPPETS_DIR/mainlayout-template-menu.vue" "$TARGET"

# --- Anchor 2: Add ref to Vue imports (skip if already present) ---
if ! grep -q 'ref' <<< "$(grep 'import.*computed.*onMounted' "$TARGET")"; then
    sed -i 's|import { computed, onMounted }|import { computed, onMounted, ref }|' "$TARGET"
fi

# --- Anchor 3: Add axios import after webterm import (skip if already present) ---
if ! grep -q 'import axios' "$TARGET"; then
    sed -i '/checkWebTermPerms.*openWebTerminal/a import axios from "axios";' "$TARGET"
fi

# --- Anchor 4: Add feVersion import after ResetPass import (skip if already present) ---
if ! grep -q 'feVersion' "$TARGET"; then
    sed -i '/ResetPass.vue/a import { version as feVersion } from "../../package.json";' "$TARGET"
fi

# --- Anchor 5: Insert version-switching functions before onMounted ---
inject_before 'onMounted\(\(\) =>' "$SNIPPETS_DIR/mainlayout-version-funcs.ts" "$TARGET"

echo "  MainLayout.vue patched successfully."
