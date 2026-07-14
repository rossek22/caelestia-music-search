#!/usr/bin/env bash

set -euo pipefail

CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
SHELL_DIR=${CAELESTIA_SHELL_DIR:-"$CONFIG_HOME/quickshell/caelestia"}
STATE_DIR="$STATE_HOME/caelestia-music-search"

if [[ ! -e "$STATE_DIR/installed" ]]; then
    echo "Caelestia Music Search is not installed."
    exit 0
fi

dashboard="$SHELL_DIR/modules/dashboard"
drawers="$SHELL_DIR/modules/drawers"
scripts="$SHELL_DIR/scripts"
content_window="$drawers/ContentWindow.qml"

if [[ -f "$content_window" ]]; then
    python3 - "$content_window" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("    property bool dashboardSearchActive\n", "", 1)
text = text.replace("dashboardSearchActive || ", "", 1)
text = text.replace(" || (root.dashboardSearchActive && visibilities.dashboard)", "", 1)
text = text.replace("            root.dashboardSearchActive = false;\n", "", 1)
path.write_text(text)
PY
fi

rm -f "$dashboard/Media.qml" "$dashboard/media/Details.qml" "$dashboard/media/SearchOverlay.qml" "$scripts/music_search.py"

if [[ -f "$STATE_DIR/backed-up-files" ]]; then
    while IFS= read -r relative; do
        case "$relative" in
            dashboard/*) destination="$SHELL_DIR/modules/$relative" ;;
            drawers/*) destination="$SHELL_DIR/modules/$relative" ;;
            scripts/*) destination="$SHELL_DIR/$relative" ;;
            *) continue ;;
        esac
        mkdir -p "$(dirname -- "$destination")"
        rm -f "$destination"
        cp -a "$STATE_DIR/backups/$relative" "$destination"
    done < "$STATE_DIR/backed-up-files"
fi

restore_directory() {
    local name=$1 target=$2 mode source
    [[ -f "$STATE_DIR/$name-mode" ]] || return 0
    mode=$(<"$STATE_DIR/$name-mode")
    case "$mode" in
        symlink)
            source=$(<"$STATE_DIR/$name-source")
            rm -rf "$target"
            ln -s "$source" "$target"
            ;;
        absent)
            rm -rf "$target"
            ;;
        directory) ;;
    esac
}

restore_directory dashboard-media "$dashboard/media"
restore_directory dashboard "$dashboard"
restore_directory drawers "$drawers"
restore_directory scripts "$scripts"

if [[ -e "$STATE_DIR/created-shell-overlay" ]]; then
    rm -rf "$SHELL_DIR"
fi
rm -rf "$STATE_DIR"

if command -v caelestia >/dev/null 2>&1; then
    caelestia shell -k >/dev/null 2>&1 || true
    caelestia shell -d >/dev/null 2>&1 || true
fi

echo "Caelestia Music Search uninstalled successfully."
