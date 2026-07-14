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


def fetch_text(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": "en-US,en;q=0.8"})
    with urllib.request.urlopen(request, timeout=6) as response:
        return response.read().decode("utf-8", "replace")


def fetch_json(url: str) -> dict:
    return json.loads(fetch_text(url))


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
    key = cache_key(provider, url)
    cache = load_cache()
    if cache.get(key):
        return cache[key]

    target = {
        "spotify": lambda: spotify_url(url),
        "youtube": lambda: youtube_music_url(query),
        "deezer": lambda: deezer_url(query),
    }[provider]()
    if target:
        cache[key] = target
        save_cache(cache)
    return target


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


def search(query: str, provider: str) -> None:
    params = urllib.parse.urlencode({
        "term": query,
        "media": "music",
        "entity": "song",
        "limit": 8,
        "country": "US",
    })
    data = fetch_json(f"https://itunes.apple.com/search?{params}")
    results = []
    for track in data.get("results", []):
        results.append({
            "title": track.get("trackName", ""),
            "artist": track.get("artistName", ""),
            "album": track.get("collectionName", ""),
            "artwork": track.get("artworkUrl100", "").replace("100x100", "200x200"),
            "url": track.get("trackViewUrl", ""),
            "duration": round(track.get("trackTimeMillis", 0) / 1000),
        })
    print(json.dumps({"query": query, "results": results}, ensure_ascii=False), flush=True)
    subprocess.Popen(
        [sys.executable, __file__, "prefetch", provider, json.dumps(results, ensure_ascii=False)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def open_spotify(target: str, query: str) -> None:
    if "/track/" in target:
        track_id = target.split("/track/", 1)[1].split("?", 1)[0]
        uri = "spotify:track:" + track_id
    else:
        uri = "spotify:search:" + query

    if not shutil.which("spotify"):
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
        subprocess.Popen(["spotify", f"--uri={uri}"], start_new_session=True)


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
