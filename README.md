# Caelestia Music Search

A focused media-player enhancement for [Caelestia Shell](https://github.com/caelestia-dots/shell). It adds an animated search dialog, live track suggestions, provider selection, direct playback, and an MPRIS volume slider to the Media dashboard.

## Features

- Click the current track title to open a modal search layer.
- Search results include artwork, title, artist, and album.
- Choose Spotify, YouTube Music, or Deezer as the playback provider.
- Close the dialog with `Escape`, the close button, or a click outside the dialog.
- Navigate results with the keyboard and play with `Enter`.
- Control the active player's volume through MPRIS.
- Smooth opening and closing animations with rounded result cards and artwork.

## How search works

Search metadata comes from Apple's public iTunes Search API. Selecting a result sends its Apple Music URL to Songlink/Odesli to resolve the equivalent track for the selected provider. Spotify tracks are sent to the installed client through MPRIS. If the Spotify client is not installed, the exact track opens in the default browser instead. YouTube Music and Deezer use their HTTPS links, so the desktop opens an installed handler when available and otherwise falls back to the browser.

Songlink's public `v1-alpha.1` endpoint is scheduled for retirement on July 31, 2026. The helper falls back to a provider search URL when exact cross-platform resolution is unavailable.

## Requirements

- Caelestia Shell
- Quickshell
- Python 3
- `gdbus`
- `xdg-open`
- Spotify desktop client for direct Spotify playback
- Internet access for search and provider resolution

## Install

Install directly with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/rossek22/caelestia-music-search/main/bootstrap.sh | bash
```

Or clone the repository manually:

```bash
git clone https://github.com/rossek22/caelestia-music-search.git
cd caelestia-music-search
./install.sh
```

The installer:

1. Locates the active Caelestia configuration.
2. Preserves the distribution-provided symlink layout.
3. Installs only the modified dashboard and search files.
4. Applies the minimal keyboard-focus integration required by the modal.
5. Stores installation state under `${XDG_STATE_HOME:-~/.local/state}/caelestia-music-search`.
6. Restarts Caelestia Shell when it is running.

## Uninstall

```bash
./uninstall.sh
```

The uninstaller restores the previous files or the original system dashboard symlink and removes only the keyboard-focus changes made by the installer.

## License

Copyright (C) 2026 rossek22

Licensed under the GNU Affero General Public License v3.0. You may use, modify, and redistribute this project, including commercially, provided that covered source code and modifications remain available under the same license. See [LICENSE](LICENSE) for the complete terms.

This project contains modified portions of Caelestia Shell, which is licensed under GNU GPLv3. Copyright for those portions remains with the Caelestia Shell contributors. GPLv3 and AGPLv3 may be combined under section 13 of the AGPLv3.
