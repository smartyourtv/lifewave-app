#!/usr/bin/env bash
# sync_assets.sh — copy the canonical Lifewave database + brand assets into
# this Flutter app's assets/ folder. Run after any db/ or assets/ update in
# ~/workspace/lifewave/ so the bundled copies match in one command.
#   bash tool/sync_assets.sh
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="$(cd "$APP_DIR/.." && pwd)"   # ~/workspace/lifewave/
echo "Syncing DB from $SRC_ROOT/db -> $APP_DIR/assets/db"
rm -rf "$APP_DIR/assets/db"
mkdir -p "$APP_DIR/assets/db"
cp -r "$SRC_ROOT/db/." "$APP_DIR/assets/db/"
echo "Syncing brand assets from $SRC_ROOT/assets -> $APP_DIR/assets"
rm -rf "$APP_DIR/assets/brand"
mkdir -p "$APP_DIR/assets/brand"
cp -r "$SRC_ROOT/assets/brand/." "$APP_DIR/assets/brand/"
cp "$SRC_ROOT/assets/assets.json" "$APP_DIR/assets/assets.json"
echo "Done. DB files:"
find "$APP_DIR/assets/db" -type f | sort
echo "Brand files: $(find "$APP_DIR/assets/brand" -type f | wc -l) files, $(du -sb "$APP_DIR/assets/brand" | cut -f1) bytes total"
