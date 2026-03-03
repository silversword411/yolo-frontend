#!/bin/bash
# frontend-revert-to-prod.sh
# Reverts the versioned frontend structure back to a standard flat dist directory.
# Run with sudo.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/yolo.conf"

if [ ! -L "$DIST_DIR" ]; then
    echo "Error: $DIST_DIR is not a symlink. Already in standard (non-versioned) mode."
    exit 1
fi

# Find the currently active version
ACTIVE_PATH=$(readlink -f "$DIST_DIR")
ACTIVE_NAME=$(basename "$ACTIVE_PATH")

echo "Currently active version: $ACTIVE_NAME"
echo "Reverting to standard single-version setup..."

# Remove the symlink
rm "$DIST_DIR"

# Copy the active version back as a real directory
cp -r "$ACTIVE_PATH" "$DIST_DIR"
echo "Restored $DIST_DIR from version: $ACTIVE_NAME"

# Remove the versions directory
rm -rf "$VERSIONS_DIR"
echo "Removed $VERSIONS_DIR"

# Restore original ownership
chown -R root:root "$(dirname "$DIST_DIR")/"

echo ""
echo "Revert complete. $DIST_DIR is now a regular directory."
echo "You can use the original frontend-rebuild.sh process again."
