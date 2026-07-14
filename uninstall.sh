#!/usr/bin/env bash

set -euo pipefail

CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
SHELL_DIR=${CAELESTIA_SHELL_DIR:-"$CONFIG_HOME/quickshell/caelestia"}
STATE_DIR="$STATE_HOME/caelestia-music-search"
DASHBOARD="$SHELL_DIR/modules/dashboard"
CONTENT_WINDOW="$SHELL_DIR/modules/drawers/ContentWindow.qml"

if [[ ! -e "$STATE_DIR/installed" ]]; then
    echo "Caelestia Music Search is not installed."
    exit 0
fi

python3 - "$CONTENT_WINDOW" <<'PY'
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

mode=$(<"$STATE_DIR/dashboard-mode")
if [[ "$mode" == "symlink" ]]; then
    source_path=$(<"$STATE_DIR/dashboard-source")
    rm -rf "$DASHBOARD"
    ln -s "$source_path" "$DASHBOARD"
else
    rm -f "$DASHBOARD/Media.qml" "$DASHBOARD/media/Details.qml" "$DASHBOARD/media/SearchOverlay.qml"
    if [[ -e "$STATE_DIR/backed-up-files" ]]; then
        while IFS= read -r relative; do
            mkdir -p "$DASHBOARD/$(dirname "$relative")"
            cp -a "$STATE_DIR/backups/$relative" "$DASHBOARD/$relative"
        done < "$STATE_DIR/backed-up-files"
    fi
fi

if [[ -e "$STATE_DIR/had-search-helper" ]]; then
    cp -a "$STATE_DIR/backups/music_search.py" "$SHELL_DIR/scripts/music_search.py"
else
    rm -f "$SHELL_DIR/scripts/music_search.py"
fi
rm -rf "$STATE_DIR"

if quickshell list --all 2>/dev/null | grep -q 'Config path:.*caelestia/shell.qml'; then
    caelestia shell -k >/dev/null 2>&1 || true
    caelestia shell -d >/dev/null 2>&1
fi

echo "Caelestia Music Search uninstalled successfully."
