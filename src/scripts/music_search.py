#!/usr/bin/env python3

import json
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request


USER_AGENT = "Caelestia/1.0"


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=8) as response:
        return json.load(response)


def search(query: str) -> None:
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
    print(json.dumps({"query": query, "results": results}, ensure_ascii=False))


def spotify_links(url: str) -> tuple[str, str]:
    params = urllib.parse.urlencode({"url": url, "userCountry": "US"})
    data = fetch_json(f"https://api.song.link/v1-alpha.1/links?{params}")
    spotify = data.get("linksByPlatform", {}).get("spotify", {}).get("url", "")
    if "/track/" not in spotify:
        return "", ""
    track_id = spotify.split("/track/", 1)[1].split("?", 1)[0]
    return "spotify:track:" + track_id, spotify


def open_spotify(url: str, query: str) -> None:
    try:
        uri, web_url = spotify_links(url)
    except Exception:
        uri, web_url = "", ""
    uri = uri or "spotify:search:" + query
    web_url = web_url or "https://open.spotify.com/search/" + urllib.parse.quote(query)

    if not shutil.which("spotify"):
        subprocess.Popen(["xdg-open", web_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
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


def resolve_platform(url: str, platform: str) -> str:
    params = urllib.parse.urlencode({"url": url, "userCountry": "US"})
    data = fetch_json(f"https://api.song.link/v1-alpha.1/links?{params}")
    return data.get("linksByPlatform", {}).get(platform, {}).get("url", "")


def play(provider: str, url: str, artist: str, title: str) -> None:
    query = f"{artist} {title}".strip()
    if provider == "spotify":
        open_spotify(url, query)
    else:
        platform = {"youtube": "youtubeMusic", "deezer": "deezer"}[provider]
        try:
            target = resolve_platform(url, platform)
        except Exception:
            target = ""
        if not target:
            encoded = urllib.parse.quote(query)
            target = {
                "youtube": f"https://music.youtube.com/search?q={encoded}",
                "deezer": f"https://www.deezer.com/search/{encoded}",
            }[provider]
        subprocess.Popen(["xdg-open", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print(json.dumps({"ok": True}))


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(2)
    if sys.argv[1] == "search":
        search(sys.argv[2])
    elif sys.argv[1] == "play" and len(sys.argv) == 6:
        play(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        raise SystemExit(2)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"error": str(error), "results": []}, ensure_ascii=False))
