#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
SHELL_DIR=${CAELESTIA_SHELL_DIR:-"$CONFIG_HOME/quickshell/caelestia"}
STATE_DIR="$STATE_HOME/caelestia-music-search"
DASHBOARD="$SHELL_DIR/modules/dashboard"
CONTENT_WINDOW="$SHELL_DIR/modules/drawers/ContentWindow.qml"

if [[ ! -e "$SHELL_DIR/shell.qml" ]]; then
    echo "Caelestia Shell was not found at $SHELL_DIR" >&2
    exit 1
fi

if [[ -e "$STATE_DIR/installed" ]]; then
    echo "Caelestia Music Search is already installed."
    exit 0
fi

mkdir -p "$STATE_DIR/backups"

if [[ -L "$DASHBOARD" ]]; then
    dashboard_source=$(readlink -f "$DASHBOARD")
    printf 'symlink\n' > "$STATE_DIR/dashboard-mode"
    printf '%s\n' "$dashboard_source" > "$STATE_DIR/dashboard-source"
    unlink "$DASHBOARD"
    mkdir -p "$DASHBOARD/media"

    for path in "$dashboard_source"/*.qml; do
        name=$(basename "$path")
        [[ "$name" == "Media.qml" ]] || ln -s "$path" "$DASHBOARD/$name"
    done
    for name in dash performance; do
        [[ -e "$dashboard_source/$name" ]] && ln -s "$dashboard_source/$name" "$DASHBOARD/$name"
    done
    for path in "$dashboard_source"/media/*.qml; do
        name=$(basename "$path")
        [[ "$name" == "Details.qml" || "$name" == "SearchOverlay.qml" ]] || ln -s "$path" "$DASHBOARD/media/$name"
    done
else
    printf 'directory\n' > "$STATE_DIR/dashboard-mode"
    for relative in Media.qml media/Details.qml media/SearchOverlay.qml; do
        if [[ -e "$DASHBOARD/$relative" || -L "$DASHBOARD/$relative" ]]; then
            mkdir -p "$STATE_DIR/backups/$(dirname "$relative")"
            cp -a "$DASHBOARD/$relative" "$STATE_DIR/backups/$relative"
            printf '%s\n' "$relative" >> "$STATE_DIR/backed-up-files"
        fi
    done
fi

mkdir -p "$DASHBOARD/media" "$SHELL_DIR/scripts"
rm -f "$DASHBOARD/Media.qml" "$DASHBOARD/media/Details.qml" "$DASHBOARD/media/SearchOverlay.qml"
cp "$PROJECT_DIR/src/modules/dashboard/Media.qml" "$DASHBOARD/Media.qml"
cp "$PROJECT_DIR/src/modules/dashboard/media/Details.qml" "$DASHBOARD/media/Details.qml"
cp "$PROJECT_DIR/src/modules/dashboard/media/SearchOverlay.qml" "$DASHBOARD/media/SearchOverlay.qml"
if [[ -e "$SHELL_DIR/scripts/music_search.py" ]]; then
    cp -a "$SHELL_DIR/scripts/music_search.py" "$STATE_DIR/backups/music_search.py"
    touch "$STATE_DIR/had-search-helper"
fi
cp "$PROJECT_DIR/src/scripts/music_search.py" "$SHELL_DIR/scripts/music_search.py"
chmod 755 "$SHELL_DIR/scripts/music_search.py"

python3 - "$CONTENT_WINDOW" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "property bool dashboardSearchActive" not in text:
    anchor = "    readonly property alias interactionWrapper: interactions\n"
    if anchor not in text:
        raise SystemExit("Could not locate the ContentWindow property section")
    text = text.replace(anchor, anchor + "    property bool dashboardSearchActive\n", 1)

line_start = "    WlrLayershell.keyboardFocus: "
for line in text.splitlines():
    if line.startswith(line_start) and "dashboardSearchActive" not in line:
        condition = line[len(line_start):]
        replacement = line_start + "dashboardSearchActive || " + condition
        text = text.replace(line, replacement, 1)
        break

for line in text.splitlines():
    if "active:" in line and "visibilities.launcher" in line and "dashboardSearchActive" not in line:
        replacement = line.rstrip() + " || (root.dashboardSearchActive && visibilities.dashboard)"
        text = text.replace(line, replacement, 1)
        break

dashboard_close = "            visibilities.dashboard = false;\n"
focus_reset = "            root.dashboardSearchActive = false;\n"
if focus_reset not in text:
    if dashboard_close not in text:
        raise SystemExit("Could not locate the focus-grab cleanup section")
    text = text.replace(dashboard_close, dashboard_close + focus_reset, 1)

path.write_text(text)
PY

touch "$STATE_DIR/installed"

if quickshell list --all 2>/dev/null | grep -q 'Config path:.*caelestia/shell.qml'; then
    caelestia shell -k >/dev/null 2>&1 || true
    caelestia shell -d >/dev/null 2>&1
fi

echo "Caelestia Music Search installed successfully."
