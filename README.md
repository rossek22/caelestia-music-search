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
- Responsive search layout that follows Caelestia's own container size and display scale.

## How search works

Search metadata comes from Apple's public iTunes Search API. Provider links for the first results are resolved and cached in the background while the result list is visible, so selecting a prepared track does not wait for another network round trip.

- Spotify uses Songlink/Odesli for exact cross-platform matching and sends the resulting track URI to the installed client through MPRIS. If the client is not installed, the exact web track opens in the default browser.
- YouTube Music resolves a concrete video ID and opens a `/watch?v=...` URL, which starts the selected track instead of displaying another search page.
- Deezer searches its catalog directly and opens the exact track URL.

YouTube Music and Deezer use HTTPS links, so the desktop opens an installed handler when available and otherwise falls back to the browser.

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
curl -fsSL https://raw.githubusercontent.com/rossek22/caelestia-music-search/main/install.sh | bash
```

Or clone the repository manually:

```bash
git clone https://github.com/rossek22/caelestia-music-search.git
cd caelestia-music-search
./install.sh
```

The same command updates an existing remote installation. A remote install is kept at `~/.local/share/caelestia-music-search` by default; override it with `CAELESTIA_MUSIC_SEARCH_ROOT`.

The installer:

1. Detects a local checkout or bootstraps the repository from GitHub.
2. Locates Caelestia in the user configuration, `/etc/xdg`, or `/usr/share`.
3. Creates a user overlay when Caelestia is installed system-wide only.
4. Preserves the distribution-provided symlink layout.
5. Installs only the modified dashboard and search files.
6. Applies the minimal keyboard-focus integration required by the modal.
7. Stores installation state under `${XDG_STATE_HOME:-~/.local/state}/caelestia-music-search`.
8. Stops every old Caelestia instance, regardless of whether it was loaded from `/etc` or the user overlay, and starts exactly one replacement instance.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/rossek22/caelestia-music-search/main/uninstall.sh | bash
```

From a local checkout, `./uninstall.sh` works as well. The uninstaller restores previous files and original system symlinks, then removes only the keyboard-focus changes made by the installer.

## License

Copyright (C) 2026 rossek22

Licensed under the GNU Affero General Public License v3.0. You may use, modify, and redistribute this project, including commercially, provided that covered source code and modifications remain available under the same license. See [LICENSE](LICENSE) for the complete terms.

This project contains modified portions of Caelestia Shell, which is licensed under GNU GPLv3. Copyright for those portions remains with the Caelestia Shell contributors. GPLv3 and AGPLv3 may be combined under section 13 of the AGPLv3.
