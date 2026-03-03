#!/bin/bash
# frontend-migrate-to-versioned.sh
# One-time migration: converts flat dist to versioned structure with symlink.
# Run with sudo.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/yolo.conf"

DEFAULT_VERSION="main"

if [ -L "$DIST_DIR" ]; then
    echo "Error: $DIST_DIR is already a symlink. Migration has already been done."
    exit 1
fi

if [ ! -d "$DIST_DIR" ]; then
    echo "Error: $DIST_DIR does not exist."
    exit 1
fi

echo "Migrating to versioned frontend structure..."

# Create versions directory
mkdir -p "$VERSIONS_DIR"

# Move current dist to first version
echo "Moving $DIST_DIR -> $VERSIONS_DIR/$DEFAULT_VERSION"
mv "$DIST_DIR" "$VERSIONS_DIR/$DEFAULT_VERSION"

# Create symlink
ln -s "$VERSIONS_DIR/$DEFAULT_VERSION" "$DIST_DIR"
echo "Created symlink: $DIST_DIR -> $VERSIONS_DIR/$DEFAULT_VERSION"

# Fix ownership so deploy user can manage versions
chown -R "$DEPLOY_USER:$WEB_GROUP" "$(dirname "$DIST_DIR")/"
chown -h "$DEPLOY_USER:$WEB_GROUP" "$DIST_DIR"

echo ""
echo "Migration complete."
echo "Active version: $DEFAULT_VERSION"
echo "Symlink: $(ls -la "$DIST_DIR")"
