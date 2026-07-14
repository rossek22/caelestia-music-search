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

stop_caelestia_instances() {
    local quickshell_command pid attempt
    quickshell_command=$(command -v quickshell || command -v qs || true)
    [[ -n "$quickshell_command" ]] || return 0
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill "$pid" >/dev/null 2>&1 || true
    done < <(
        "$quickshell_command" list --all 2>/dev/null \
            | awk '/Process ID:/ { pid=$3 } /Config path: .*\/caelestia\/shell.qml"?$/ { print pid }'
    )
    for attempt in {1..20}; do
        sleep 0.1
        [[ $(count_caelestia_instances "$quickshell_command") -eq 0 ]] && return 0
    done
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -KILL "$pid" >/dev/null 2>&1 || true
    done < <(
        "$quickshell_command" list --all 2>/dev/null \
            | awk '/Process ID:/ { pid=$3 } /Config path: .*\/caelestia\/shell.qml"?$/ { print pid }'
    )
}

count_caelestia_instances() {
    local quickshell_command=$1
    "$quickshell_command" list --all 2>/dev/null \
        | awk '/Config path: .*\/caelestia\/shell.qml"?$/ { count++ } END { print count+0 }'
}

stop_caelestia_instances
quickshell_command=$(command -v quickshell || command -v qs || true)
if [[ -n "$quickshell_command" ]]; then
    "$quickshell_command" --no-duplicate --daemonize --config caelestia >/dev/null 2>&1 || true
    sleep 0.5
    shell_count=$(count_caelestia_instances "$quickshell_command")
    echo "    running Caelestia instances: $shell_count"
    if [[ "$shell_count" -ne 1 ]]; then
        echo "Warning: expected one Caelestia instance, found $shell_count." >&2
        echo "Run 'qs list --all' to inspect the remaining instances." >&2
    fi
fi

echo "Caelestia Music Search uninstalled successfully."
