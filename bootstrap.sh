#!/usr/bin/env bash

set -euo pipefail

REPOSITORY=${CAELESTIA_MUSIC_SEARCH_REPOSITORY:-"rossek22/caelestia-music-search"}
REVISION=${CAELESTIA_MUSIC_SEARCH_REVISION:-"main"}
ARCHIVE_URL="https://github.com/$REPOSITORY/archive/refs/heads/$REVISION.tar.gz"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

echo "Downloading Caelestia Music Search..."
curl -fsSL --retry 3 "$ARCHIVE_URL" -o "$TEMP_DIR/source.tar.gz"
tar -xzf "$TEMP_DIR/source.tar.gz" -C "$TEMP_DIR"

SOURCE_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)
if [[ -z "$SOURCE_DIR" || ! -x "$SOURCE_DIR/install.sh" ]]; then
    echo "The downloaded archive does not contain install.sh" >&2
    exit 1
fi

"$SOURCE_DIR/install.sh"
