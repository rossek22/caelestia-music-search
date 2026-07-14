#!/usr/bin/env python3

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path


USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36"
CACHE_PATH = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "caelestia" / "music-links.json"


def fetch_text(url: str, headers: dict | None = None) -> str:
    request_headers = {"User-Agent": USER_AGENT, "Accept-Language": "en-US,en;q=0.8"}
    request_headers.update(headers or {})
    request = urllib.request.Request(url, headers=request_headers)
    with urllib.request.urlopen(request, timeout=6) as response:
        return response.read().decode("utf-8", "replace")


def fetch_json(url: str, headers: dict | None = None) -> dict:
    return json.loads(fetch_text(url, headers))


def post_json(url: str, payload: dict, headers: dict | None = None) -> dict:
    request_headers = {
        "User-Agent": USER_AGENT,
        "Accept-Language": "en-US,en;q=0.8",
        "Content-Type": "application/json",
        "Origin": "https://music.youtube.com",
    }
    request_headers.update(headers or {})
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers=request_headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def load_cache() -> dict:
    try:
        return json.loads(CACHE_PATH.read_text())
    except (OSError, ValueError):
        return {}


def save_cache(cache: dict) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = CACHE_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps(cache, ensure_ascii=False))
    temporary.replace(CACHE_PATH)


def cache_key(provider: str, url: str) -> str:
    return f"{provider}:{url}"


def spotify_url(url: str) -> str:
    params = urllib.parse.urlencode({"url": url, "userCountry": "US"})
    data = fetch_json(f"https://api.song.link/v1-alpha.1/links?{params}")
    return data.get("linksByPlatform", {}).get("spotify", {}).get("url", "")


def youtube_music_url(query: str) -> str:
    encoded = urllib.parse.quote_plus(query)
    page = fetch_text(f"https://www.youtube.com/results?search_query={encoded}")
    video_id = re.search(r'"videoId":"([\w-]{11})"', page)
    return f"https://music.youtube.com/watch?v={video_id.group(1)}&autoplay=1" if video_id else ""


def deezer_url(query: str) -> str:
    params = urllib.parse.urlencode({"q": query, "limit": 1})
    tracks = fetch_json(f"https://api.deezer.com/search?{params}").get("data", [])
    return tracks[0].get("link", "") if tracks else ""


def resolve_target(provider: str, url: str, query: str) -> str:
    native_hosts = {
        "spotify": "open.spotify.com/",
        "youtube": "music.youtube.com/",
        "deezer": "deezer.com/",
    }
    if native_hosts[provider] in url:
        return playback_url(provider, url)

    key = cache_key(provider, url)
    cache = load_cache()
    if cache.get(key):
        return playback_url(provider, cache[key])

    target = {
        "spotify": lambda: spotify_url(url),
        "youtube": lambda: youtube_music_url(query),
        "deezer": lambda: deezer_url(query),
    }[provider]()
    if target:
        cache[key] = target
        save_cache(cache)
    return playback_url(provider, target)


def playback_url(provider: str, url: str) -> str:
    """Add the provider's opt-in playback flag without losing URL parameters."""
    if not url or provider == "spotify":
        return url
    parsed = urllib.parse.urlsplit(url)
    query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
    if provider == "youtube" and "/watch" in parsed.path:
        query["autoplay"] = "1"
    elif provider == "deezer" and "/track/" in parsed.path:
        # Honoured by Deezer clients and some web-player versions. Browsers may
        # still require one click when their own media autoplay policy blocks it.
        query["autoplay"] = "true"
    return urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(query)))


def fallback_url(provider: str, query: str) -> str:
    encoded = urllib.parse.quote(query)
    return {
        "spotify": f"https://open.spotify.com/search/{encoded}",
        "youtube": f"https://music.youtube.com/search?q={encoded}",
        "deezer": f"https://www.deezer.com/search/{encoded}",
    }[provider]


def prefetch(provider: str, tracks: list[dict]) -> None:
    for track in tracks[:4]:
        query = f"{track.get('artist', '')} {track.get('title', '')}".strip()
        try:
            resolve_target(provider, track.get("url", ""), query)
        except Exception:
            continue


def spotify_search(query: str) -> list[dict]:
    # Spotify no longer exposes a working anonymous catalogue token. iTunes is
    # used only as metadata lookup; play() resolves the selected result to
    # Spotify when the desktop client is installed.
    params = urllib.parse.urlencode({
        "term": query, "media": "music", "entity": "song", "limit": 8, "country": "US",
    })
    tracks = fetch_json(f"https://itunes.apple.com/search?{params}").get("results", [])
    return [{
        "title": track.get("trackName", ""),
        "artist": track.get("artistName", ""),
        "album": track.get("collectionName", ""),
        "artwork": track.get("artworkUrl100", "").replace("100x100", "200x200"),
        "url": track.get("trackViewUrl", ""),
        "duration": round(track.get("trackTimeMillis", 0) / 1000),
    } for track in tracks]


def walk_json(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_json(child)


def runs_text(value: dict) -> str:
    return "".join(run.get("text", "") for run in value.get("runs", [])) or value.get("simpleText", "")


def parse_duration(values: list[str]) -> int:
    for value in reversed(values):
        if not re.fullmatch(r"\d{1,2}:\d{2}(?::\d{2})?", value):
            continue
        parts = [int(part) for part in value.split(":")]
        return sum(part * (60 ** index) for index, part in enumerate(reversed(parts)))
    return 0


def youtube_artwork(video_id: str) -> str:
    # The search response often contains a 60–120 px thumbnail. YouTube's
    # canonical high-quality endpoint avoids scaling that tiny image in QML.
    return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"


def youtube_search(query: str) -> list[dict]:
    # Anonymous Innertube request used by the YouTube Music web client. The
    # filter limits results to songs rather than videos/playlists/artists.
    data = post_json(
        "https://music.youtube.com/youtubei/v1/search?alt=json&key="
        "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30",
        {
            "query": query,
            "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF",
            "context": {"client": {
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20260701.01.00",
                "hl": "en",
                "gl": "US",
            }, "user": {}},
        },
    )
    results = []
    seen = set()
    for node in walk_json(data):
        renderer = node.get("musicResponsiveListItemRenderer")
        if not renderer:
            continue
        endpoint = renderer.get("overlay", {}).get("musicItemThumbnailOverlayRenderer", {}).get(
            "content", {}).get("musicPlayButtonRenderer", {}).get("playNavigationEndpoint", {})
        video_id = endpoint.get("watchEndpoint", {}).get("videoId", "")
        columns = renderer.get("flexColumns", [])
        texts = [runs_text(column.get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {})) for column in columns]
        if not video_id or video_id in seen or not texts:
            continue
        seen.add(video_id)
        secondary_runs = columns[1].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", []) if len(columns) > 1 else []
        secondary = [run.get("text", "") for run in secondary_runs if run.get("text") not in ("", " • ")]
        results.append({
            "title": texts[0], "artist": secondary[0] if secondary else "YouTube Music",
            "album": secondary[1] if len(secondary) > 1 and not re.fullmatch(r"\d{1,2}:\d{2}(?::\d{2})?", secondary[1]) else "",
            "artwork": youtube_artwork(video_id),
            "url": f"https://music.youtube.com/watch?v={video_id}", "duration": parse_duration(secondary),
        })
        if len(results) == 8:
            break
    return results


def deezer_search(query: str) -> list[dict]:
    params = urllib.parse.urlencode({
        "q": query,
        "limit": 8,
    })
    tracks = fetch_json(f"https://api.deezer.com/search?{params}").get("data", [])
    return [{
        "title": track.get("title", ""), "artist": track.get("artist", {}).get("name", ""),
        "album": track.get("album", {}).get("title", ""), "artwork": track.get("album", {}).get("cover_xl", "") or track.get("album", {}).get("cover_big", ""),
        "url": track.get("link", ""), "duration": track.get("duration", 0),
    } for track in tracks]


def search(query: str, provider: str) -> None:
    searcher = {"spotify": spotify_search, "youtube": youtube_search, "deezer": deezer_search}[provider]
    try:
        results = searcher(query)
    except Exception:
        # Spotify's anonymous token and YouTube Music's page data are not
        # available in every region. Keep the request provider-specific: the
        # fallback opens that provider's own search instead of mixing in iTunes
        # or another catalogue.
        labels = {"spotify": "Spotify", "youtube": "YouTube Music", "deezer": "Deezer"}
        results = [{
            "title": query,
            "artist": f"Search on {labels[provider]}",
            "album": "",
            "artwork": "",
            "url": fallback_url(provider, query),
            "duration": 0,
        }]
    for result in results:
        result["provider"] = provider
    print(json.dumps({"query": query, "provider": provider, "results": results}, ensure_ascii=False), flush=True)
    subprocess.Popen(
        [sys.executable, __file__, "prefetch", provider, json.dumps(results, ensure_ascii=False)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def spotify_client_available() -> bool:
    if shutil.which("spotify"):
        return True
    if shutil.which("flatpak"):
        result = subprocess.run(
            ["flatpak", "info", "com.spotify.Client"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return True
    return False


def open_spotify(target: str, query: str) -> None:
    if "/track/" in target:
        track_id = target.split("/track/", 1)[1].split("?", 1)[0]
        uri = "spotify:track:" + track_id
    else:
        uri = "spotify:search:" + query

    if not spotify_client_available():
        subprocess.Popen(["xdg-open", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return

    call = [
        "gdbus", "call", "--session",
        "--dest", "org.mpris.MediaPlayer2.spotify",
        "--object-path", "/org/mpris/MediaPlayer2",
        "--method", "org.mpris.MediaPlayer2.Player.OpenUri",
        uri,
    ]
    result = subprocess.run(call, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        if shutil.which("spotify"):
            subprocess.Popen(["spotify", f"--uri={uri}"], start_new_session=True)
        else:
            subprocess.Popen(
                ["flatpak", "run", "com.spotify.Client", f"--uri={uri}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )


def play(provider: str, url: str, artist: str, title: str) -> None:
    query = f"{artist} {title}".strip()
    try:
        target = resolve_target(provider, url, query)
    except Exception:
        target = ""
    target = target or fallback_url(provider, query)

    if provider == "spotify":
        open_spotify(target, query)
    else:
        subprocess.Popen(["xdg-open", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print(json.dumps({"ok": True, "target": target}))


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(2)
    if sys.argv[1] == "search":
        search(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "spotify")
    elif sys.argv[1] == "prefetch" and len(sys.argv) == 4:
        prefetch(sys.argv[2], json.loads(sys.argv[3]))
    elif sys.argv[1] == "play" and len(sys.argv) == 6:
        play(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        raise SystemExit(2)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"error": str(error), "results": []}, ensure_ascii=False))
