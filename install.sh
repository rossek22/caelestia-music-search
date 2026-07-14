#!/usr/bin/env bash

set -euo pipefail

REPO_URL=${CAELESTIA_MUSIC_SEARCH_REPO:-https://github.com/rossek22/caelestia-music-search.git}
BRANCH=${CAELESTIA_MUSIC_SEARCH_BRANCH:-main}
INSTALL_DIR=${CAELESTIA_MUSIC_SEARCH_ROOT:-"$HOME/.local/share/caelestia-music-search"}
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
SHELL_DIR=${CAELESTIA_SHELL_DIR:-"$CONFIG_HOME/quickshell/caelestia"}
STATE_DIR="$STATE_HOME/caelestia-music-search"

self_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    self_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
elif [[ -n "${0:-}" && -f "$0" ]]; then
    case $(basename -- "$0") in
        sh|bash|dash|zsh) ;;
        *) self_dir=$(cd -- "$(dirname -- "$0")" && pwd) ;;
    esac
fi

is_repository() {
    [[ -f "$1/src/modules/dashboard/Media.qml" \
        && -f "$1/src/modules/dashboard/media/SearchOverlay.qml" \
        && -f "$1/src/scripts/music_search.py" ]]
}

repository=""
if [[ -n "$self_dir" ]] && is_repository "$self_dir"; then
    repository="$self_dir"
    echo "==> Caelestia Music Search install (local checkout)"
else
    echo "==> Caelestia Music Search install (bootstrap from GitHub)"
    echo "    destination: $INSTALL_DIR"

    if command -v git >/dev/null 2>&1; then
        if [[ -d "$INSTALL_DIR/.git" ]] && is_repository "$INSTALL_DIR"; then
            git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
            git -C "$INSTALL_DIR" checkout -q "$BRANCH" 2>/dev/null \
                || git -C "$INSTALL_DIR" checkout -q -B "$BRANCH" "origin/$BRANCH"
            git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
        else
            if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
                echo "The install directory exists and is not a git clone: $INSTALL_DIR" >&2
                echo "Move it aside or set CAELESTIA_MUSIC_SEARCH_ROOT." >&2
                exit 1
            fi
            rm -rf "$INSTALL_DIR"
            mkdir -p "$(dirname -- "$INSTALL_DIR")"
            git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
        fi
    else
        command -v curl >/dev/null 2>&1 || { echo "curl or git is required" >&2; exit 1; }
        command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }
        temporary=$(mktemp -d)
        trap 'rm -rf "$temporary"' EXIT
        curl -fsSL "https://github.com/rossek22/caelestia-music-search/archive/refs/heads/$BRANCH.tar.gz" \
            | tar -xz -C "$temporary"
        source_dir=$(find "$temporary" -mindepth 1 -maxdepth 1 -type d -name 'caelestia-music-search-*' -print -quit)
        [[ -n "$source_dir" ]] || { echo "Failed to unpack the repository archive" >&2; exit 1; }
        rm -rf "$INSTALL_DIR"
        mkdir -p "$(dirname -- "$INSTALL_DIR")"
        mv "$source_dir" "$INSTALL_DIR"
        trap - EXIT
        rm -rf "$temporary"
    fi
    repository="$INSTALL_DIR"
fi

find_caelestia_source() {
    local candidate resolved
    if [[ -n "${CAELESTIA_SOURCE_DIR:-}" && -e "$CAELESTIA_SOURCE_DIR/shell.qml" ]]; then
        printf '%s\n' "$CAELESTIA_SOURCE_DIR"
        return
    fi
    if [[ -e "$SHELL_DIR/shell.qml" ]]; then
        resolved=$(readlink -f "$SHELL_DIR/shell.qml")
        [[ -n "$resolved" ]] && dirname -- "$resolved"
        return
    fi
    for candidate in /etc/xdg/quickshell/caelestia /usr/share/quickshell/caelestia; do
        if [[ -e "$candidate/shell.qml" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

source_root=$(find_caelestia_source || true)
if [[ -z "$source_root" ]]; then
    echo "Caelestia Shell QML was not found." >&2
    echo "Checked the user config, /etc/xdg/quickshell/caelestia, and /usr/share/quickshell/caelestia." >&2
    exit 1
fi

first_install=true
if [[ -e "$STATE_DIR/installed" ]]; then
    first_install=false
    echo "==> Updating an existing installation"
else
    mkdir -p "$STATE_DIR/backups"
fi

if [[ ! -d "$SHELL_DIR" ]]; then
    mkdir -p "$SHELL_DIR"
    touch "$STATE_DIR/created-shell-overlay"
fi

if [[ ! -e "$SHELL_DIR/shell.qml" ]]; then
    ln -s "$source_root/shell.qml" "$SHELL_DIR/shell.qml"
fi

for name in LICENSE assets components services utils; do
    if [[ ! -e "$SHELL_DIR/$name" && -e "$source_root/$name" ]]; then
        ln -s "$source_root/$name" "$SHELL_DIR/$name"
    fi
done

mkdir -p "$SHELL_DIR/modules"
if [[ -d "$source_root/modules" ]]; then
    for path in "$source_root"/modules/*; do
        name=$(basename -- "$path")
        [[ "$name" == dashboard || "$name" == drawers ]] && continue
        [[ -e "$SHELL_DIR/modules/$name" || -L "$SHELL_DIR/modules/$name" ]] \
            || ln -s "$path" "$SHELL_DIR/modules/$name"
    done
fi

materialize_directory() {
    local name=$1 target=$2 source=$3 path item
    if $first_install; then
        if [[ -L "$target" ]]; then
            printf 'symlink\n' > "$STATE_DIR/$name-mode"
            readlink -f "$target" > "$STATE_DIR/$name-source"
        elif [[ -d "$target" ]]; then
            printf 'directory\n' > "$STATE_DIR/$name-mode"
        else
            printf 'absent\n' > "$STATE_DIR/$name-mode"
        fi
    fi

    if [[ -L "$target" ]]; then
        source=$(readlink -f "$target")
        unlink "$target"
    fi
    mkdir -p "$target"
    if [[ -d "$source" ]]; then
        for path in "$source"/*; do
            item=$(basename -- "$path")
            [[ -e "$target/$item" || -L "$target/$item" ]] || ln -s "$path" "$target/$item"
        done
    fi
}

dashboard="$SHELL_DIR/modules/dashboard"
drawers="$SHELL_DIR/modules/drawers"
scripts="$SHELL_DIR/scripts"
materialize_directory dashboard "$dashboard" "$source_root/modules/dashboard"
materialize_directory drawers "$drawers" "$source_root/modules/drawers"
materialize_directory scripts "$scripts" "$source_root/scripts"
materialize_directory dashboard-media "$dashboard/media" "$source_root/modules/dashboard/media"

backup_file() {
    local relative=$1 path=$2
    $first_install || return 0
    if [[ -e "$path" || -L "$path" ]]; then
        mkdir -p "$STATE_DIR/backups/$(dirname -- "$relative")"
        cp -a "$path" "$STATE_DIR/backups/$relative"
        printf '%s\n' "$relative" >> "$STATE_DIR/backed-up-files"
    fi
}

backup_file dashboard/Media.qml "$dashboard/Media.qml"
backup_file dashboard/media/Details.qml "$dashboard/media/Details.qml"
backup_file dashboard/media/SearchOverlay.qml "$dashboard/media/SearchOverlay.qml"
backup_file drawers/ContentWindow.qml "$drawers/ContentWindow.qml"
backup_file scripts/music_search.py "$scripts/music_search.py"

rm -f "$dashboard/Media.qml" "$dashboard/media/Details.qml" "$dashboard/media/SearchOverlay.qml" "$scripts/music_search.py"
cp "$repository/src/modules/dashboard/Media.qml" "$dashboard/Media.qml"
cp "$repository/src/modules/dashboard/media/Details.qml" "$dashboard/media/Details.qml"
cp "$repository/src/modules/dashboard/media/SearchOverlay.qml" "$dashboard/media/SearchOverlay.qml"
cp "$repository/src/scripts/music_search.py" "$scripts/music_search.py"
chmod 755 "$scripts/music_search.py"

content_window="$drawers/ContentWindow.qml"
if [[ -L "$content_window" ]]; then
    content_source=$(readlink -f "$content_window")
    rm -f "$content_window"
    cp "$content_source" "$content_window"
fi
if [[ ! -f "$content_window" ]]; then
    echo "ContentWindow.qml was not found at $content_window" >&2
    exit 1
fi

python3 - "$content_window" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "property bool dashboardSearchActive" not in text:
    anchor = "    readonly property alias interactionWrapper: interactions\n"
    if anchor not in text:
        raise SystemExit("Could not locate the ContentWindow property section")
    text = text.replace(anchor, anchor + "    property bool dashboardSearchActive\n", 1)

prefix = "    WlrLayershell.keyboardFocus: "
for line in text.splitlines():
    if line.startswith(prefix) and "dashboardSearchActive" not in line:
        text = text.replace(line, prefix + "dashboardSearchActive || " + line[len(prefix):], 1)
        break

for line in text.splitlines():
    if "active:" in line and "visibilities.launcher" in line and "dashboardSearchActive" not in line:
        text = text.replace(line, line.rstrip() + " || (root.dashboardSearchActive && visibilities.dashboard)", 1)
        break

close_line = "            visibilities.dashboard = false;\n"
reset_line = "            root.dashboardSearchActive = false;\n"
if reset_line not in text:
    if close_line not in text:
        raise SystemExit("Could not locate the focus-grab cleanup section")
    text = text.replace(close_line, close_line + reset_line, 1)

path.write_text(text)
PY

touch "$STATE_DIR/installed"
chmod 755 "$repository/install.sh" "$repository/uninstall.sh" "$repository/src/scripts/music_search.py"

if command -v caelestia >/dev/null 2>&1; then
    caelestia shell -k >/dev/null 2>&1 || true
    caelestia shell -d >/dev/null 2>&1 || true
fi

echo ""
echo "Installed Caelestia Music Search."
echo "  Source: $repository"
echo "  Shell:  $SHELL_DIR"
echo ""
echo "Uninstall with:"
echo "  curl -fsSL https://raw.githubusercontent.com/rossek22/caelestia-music-search/main/uninstall.sh | bash"
