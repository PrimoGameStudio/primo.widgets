#!/usr/bin/env python3
"""primo.widgets Steam recents helper — local files only, no network, no API key.

Reads playtime recency from Steam's localconfig.vdf, resolves display names
from installed appmanifests (with manual config overrides, then "App <id>"),
resolves capsule art from the local
librarycache, and prints a JSON array to stdout:

  [{"appid": 108600, "name": "Project Zomboid", "lastPlayed": 1789504277,
    "playtimeMin": 165123, "playtime2wksMin": 705, "art": "file:///...",
    "source": "steam", "rungameid": 108600}]

Non-Steam shortcuts (userdata/*/config/shortcuts.vdf) are merged into the
same recency-sorted list with source "shortcut": names and LastPlayTime come
from shortcuts.vdf itself, playtime merges from localconfig.vdf (tracked
under the signed shortcut id), art comes from the local config/grid custom
artwork (hero first, monogram fallback when unset). They launch through
Steam via steam://rungameid/<64-bit shortcut id>, where the id is
(unsigned 32-bit shortcuts.vdf appid << 32) | 0x02000000; it is emitted as
a JSON string because 64-bit ids exceed JavaScript's safe integer range.

Battle.net games (umu-launcher prefix, e.g. ~/Games/battlenet) merge in with
source "battlenet": recency comes from the client's Battle.net.config
(Games.<uid>.LastPlayed, LastActioned fallback), names/launch codes come
from a local uid table, art comes from the local Lutris coverart
(~/.local/share/lutris/coverart, monogram fallback when unset). Launch
via umu-run Battle.net.exe --exec="launch <CODE>".

Art candidates prefer landscape tiles (capsule/header) and support both the
old librarycache layout (<appid>/header.jpg) and the new hashed layout
(<appid>/<hash>/library_capsule.jpg).
"""

import argparse
import glob
import json
import os
import re
import struct
import sys


def default_steam_root():
    home = os.path.expanduser("~")
    for cand in (os.path.join(home, ".local/share/Steam"),
                 os.path.join(home, ".steam/steam")):
        if os.path.isdir(cand):
            return cand
    return os.path.join(home, ".local/share/Steam")


def extract_apps_section(text):
    """Return the raw text of the top-level "apps" block in localconfig.vdf."""
    m = re.search(r'"apps"\s*\{', text)
    if not m:
        return ""
    depth = 0
    start = m.end() - 1
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return ""


def parse_recents(localconfig_paths):
    """Merge {appid: {lastPlayed, playtimeMin, playtime2wksMin}} across files."""
    merged = {}
    for path in localconfig_paths:
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                apps = extract_apps_section(f.read())
        except OSError:
            continue
        if not apps:
            continue
        # Top-level entries look like: "108600"\n { ...}
        # (shortcuts are tracked under their signed id: "-1012443162")
        for m in re.finditer(r'"(-?\d+)"\s*\{', apps):
            appid = m.group(1)
            # Brace-match this app's block (may contain nested "cloud" blocks)
            depth = 0
            end = -1
            for i in range(m.end() - 1, len(apps)):
                if apps[i] == "{":
                    depth += 1
                elif apps[i] == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            if end == -1:
                continue
            block = apps[m.end():end]
            lp = re.search(r'"LastPlayed"\s+"(\d+)"', block)
            pt = re.search(r'"Playtime"\s+"(\d+)"', block)
            p2 = re.search(r'"Playtime2wks"\s+"(\d+)"', block)
            last = int(lp.group(1)) if lp else 0
            cur = merged.get(appid, {"lastPlayed": 0})
            if last >= cur["lastPlayed"]:
                merged[appid] = {
                    "lastPlayed": last,
                    "playtimeMin": int(pt.group(1)) if pt else 0,
                    "playtime2wksMin": int(p2.group(1)) if p2 else 0,
                }
    return merged


def library_paths(steam_root):
    """All Steam library folders from libraryfolders.vdf + the default one."""
    paths = [os.path.join(steam_root, "steamapps")]
    try:
        with open(os.path.join(steam_root, "steamapps/libraryfolders.vdf"),
                  encoding="utf-8", errors="ignore") as f:
            text = f.read()
    except OSError:
        text = ""
    for m in re.finditer(r'"path"\s+"([^"]+)"', text):
        p = os.path.join(m.group(1), "steamapps")
        if p not in paths:
            paths.append(p)
    return [p for p in paths if os.path.isdir(p)]


def parse_manifest_names(lib_paths):
    names = {}
    for lib in lib_paths:
        for acf in glob.glob(os.path.join(lib, "appmanifest_*.acf")):
            try:
                with open(acf, encoding="utf-8", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            a = re.search(r'"appid"\s+"(\d+)"', text)
            n = re.search(r'"name"\s+"([^"]+)"', text)
            if a and n:
                names[a.group(1)] = n.group(1)
    return names


def parse_shortcuts(shortcut_paths):
    """Merge {unsigned_id: {name, lastPlayed}} from shortcuts.vdf files.

    Binary VDF: top-level "shortcuts" section holds numbered entries, each a
    blob with 0x01-prefixed string keys and 0x02-prefixed int32 keys.
    Returns {} on any read failure; a corrupt file never breaks the widget.
    """
    merged = {}
    for path in shortcut_paths:
        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            continue
        try:
            body = data.split(b"\x00shortcuts\x00", 1)[1]
        except IndexError:
            continue
        # Split numbered entries: b"\x00<index>\x00<blob>"
        chunks = re.split(rb"\x00(\d+)\x00", body)
        for idx in range(1, len(chunks) - 1, 2):
            blob = chunks[idx + 1]
            # Stop at the next entry: blob runs to end of data, so bound the
            # key search to a window (entries are small; names sit up front).
            blob = blob[:8192]

            def get_str(key):
                m = re.search(rb"\x01" + key + rb"\x00([^\x00]*)\x00", blob)
                return m.group(1).decode("utf-8", errors="replace") if m else ""

            def get_i32(key):
                m = re.search(rb"\x02" + key + rb"\x00(.{4})", blob, re.S)
                return struct.unpack("<i", m.group(1))[0] if m else 0

            try:
                signed = get_i32(b"appid")
            except struct.error:
                continue
            if not signed:
                continue
            unsigned_int = signed % 2**32
            unsigned = str(unsigned_int)
            name = get_str(b"AppName").strip()
            if not name:
                continue
            last = get_i32(b"LastPlayTime")
            cur = merged.get(unsigned)
            if cur is None or last > cur["lastPlayed"]:
                # Steam's URI for a non-Steam shortcut uses a 64-bit id:
                # (unsigned 32-bit shortcuts.vdf appid << 32) | 0x02000000.
                # Keep it as a string: 64-bit ids are beyond JavaScript's
                # safe integer range, so QML's JSON.parse would round it.
                long_id = (unsigned_int << 32) | 0x02000000
                merged[unsigned] = {
                    "name": name,
                    "lastPlayed": last,
                    "signed": str(signed),  # localconfig.vdf playtime key
                    "rungameid": str(long_id),
                }
    return merged


def find_shortcut_art(grid_dirs, unsigned):
    """Best landscape tile from config/grid custom artwork, or ''."""
    candidates = ["%s_hero.jpg" % unsigned, "%sp.jpg" % unsigned,
                  "%s.jpg" % unsigned, "%s_logo.png" % unsigned]
    for grid in grid_dirs:
        for name in candidates:
            p = os.path.join(grid, name)
            if os.path.isfile(p):
                return "file://" + p
    return ""


def find_art(steam_root, appid):
    """Best landscape tile for appid from the local librarycache, or ''."""
    base = os.path.join(steam_root, "appcache/librarycache", str(appid))
    if not os.path.isdir(base):
        return ""
    # Old layout: files directly under <appid>/
    direct = ["library_capsule.jpg", "header.jpg", "library_header.jpg",
              "library_600x900.jpg", "library_hero.jpg"]
    for name in direct:
        p = os.path.join(base, name)
        if os.path.isfile(p):
            return "file://" + p
    # New layout: <appid>/<hash>/<asset>.jpg
    for name in direct:
        for p in glob.glob(os.path.join(base, "*", name)):
            if os.path.isfile(p):
                return "file://" + p
    return ""


# Battle.net: internal config uid -> (launch CODE, display name, art slug).
# Covers both raw config keys (hs_beta, s1, ...) and already-normalized
# flavor codes (WTCG, S1, ...) so future client key renames still resolve.
BNET_MAP = {
    "hs_beta": ("WTCG", "Hearthstone", "hearthstone"),
    "wtcg": ("WTCG", "Hearthstone", "hearthstone"),
    "s1": ("S1", "StarCraft", "starcraft-remastered"),
    "s2": ("S2", "StarCraft II", "starcraft-ii"),
    "wow": ("WoW", "World of Warcraft", "world-of-warcraft"),
    "wow_classic": ("WoWC", "World of Warcraft Classic",
                    "world-of-warcraft-classic"),
    "wow_classic_era": ("WoWC", "World of Warcraft Classic Era",
                        "world-of-warcraft-classic"),
    "diablo3": ("D3", "Diablo III", "diablo-iii"),
    "d3": ("D3", "Diablo III", "diablo-iii"),
    "fenris": ("Fen", "Diablo IV", "diablo-iv"),
    "fen": ("Fen", "Diablo IV", "diablo-iv"),
    "prometheus": ("Pro", "Overwatch 2", "overwatch-2"),
    "pro": ("Pro", "Overwatch 2", "overwatch-2"),
    "heroes": ("Hero", "Heroes of the Storm", "heroes-of-the-storm"),
    "hero": ("Hero", "Heroes of the Storm", "heroes-of-the-storm"),
    "w3": ("W3", "Warcraft III", "warcraft-iii"),
    "odin": ("ODIN", "Call of Duty: Modern Warfare",
             "call-of-duty-modern-warfare"),
    "zeus": ("ZEUS", "Call of Duty: Black Ops Cold War",
             "call-of-duty-black-ops-cold-war"),
    "viper": ("VIPR", "Call of Duty: Black Ops 4",
              "call-of-duty-black-ops-4"),
    "lazarus": ("LAZR", "Call of Duty: MW2 Remastered",
                "call-of-duty-mw2-remastered"),
    "rtro": ("RTRO", "Blizzard Arcade Collection",
             "blizzard-arcade-collection"),
    "cb4": ("CB4", "Crash Bandicoot 4", "crash-bandicoot-4"),
    "gryphon": ("GRY", "Warcraft Rumble", "warcraft-rumble"),
    "gry": ("GRY", "Warcraft Rumble", "warcraft-rumble"),
}


def default_battlenet_prefix():
    return os.path.join(os.path.expanduser("~"), "Games/battlenet")


def default_lutris_cover_dir():
    return os.path.join(os.path.expanduser("~"),
                         ".local/share/lutris/coverart")


def battlenet_config_path(prefix, override=""):
    """Local Battle.net.config path: explicit override, else newest match
    under <prefix>/drive_c/users/*/AppData/... (username varies)."""
    if override and os.path.isfile(override):
        return override
    rel = os.path.join("drive_c/users/*/AppData/Roaming/Battle.net",
                        "Battle.net.config")
    cands = sorted(glob.glob(os.path.join(prefix, rel)),
                   key=lambda p: os.path.getmtime(p), reverse=True)
    return cands[0] if cands else ""


def parse_battlenet_games(config_path):
    """{uid: {lastPlayed}} from Battle.net.config's Games section.

    Skips the battle_net client entry. LastPlayed wins, LastActioned is
    the fallback. Returns {} on any read failure; a corrupt config never
    breaks the widget.
    """
    if not config_path or not os.path.isfile(config_path):
        return {}
    try:
        with open(config_path, encoding="utf-8-sig",
                  errors="replace") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    games = data.get("Games") if isinstance(data, dict) else None
    if not isinstance(games, dict):
        return {}
    out = {}
    for uid, info in games.items():
        if uid == "battle_net" or not isinstance(info, dict):
            continue
        if "Resumable" not in info:
            continue
        try:
            last = int(info.get("LastPlayed") or 0)
        except (TypeError, ValueError):
            last = 0
        if last <= 0:
            try:
                last = int(info.get("LastActioned") or 0)
            except (TypeError, ValueError):
                last = 0
        if last > 0:
            out[uid] = {"lastPlayed": last}
    return out


def find_bnet_art(cover_dir, slug, code, uid):
    """Best tile from the local Lutris coverart, or '' (QML monogram)."""
    if not cover_dir or not os.path.isdir(cover_dir):
        return ""
    for name in ("%s.jpg" % slug, "%s.png" % slug,
                 "%s.jpg" % code.lower(), "%s.jpg" % uid.lower()):
        p = os.path.join(cover_dir, name)
        if os.path.isfile(p):
            return "file://" + p
    return ""


def main():
    ap = argparse.ArgumentParser(description="Steam recent games for primo.widgets")
    ap.add_argument("--count", type=int, default=5)
    ap.add_argument("--steam-root", default="")
    ap.add_argument("--steam-id", default="", help="userdata dir id; default: merge all")
    ap.add_argument("--hide", default="480", help="comma-separated appids to skip")
    ap.add_argument("--require-art", action="store_true", default=True,
                    help="skip games with no local capsule art (default: on)")
    ap.add_argument("--no-require-art", dest="require_art", action="store_false")
    ap.add_argument("--names", default="",
                    help="JSON object of manual appid->name overrides")
    ap.add_argument("--include-shortcuts", action="store_true", default=True,
                    help="merge non-Steam shortcuts (default: on)")
    ap.add_argument("--no-shortcuts", dest="include_shortcuts",
                    action="store_false")
    ap.add_argument("--include-battlenet", action="store_true", default=True,
                    help="merge Battle.net games from the local umu prefix"
                    " (default: on)")
    ap.add_argument("--no-battlenet", dest="include_battlenet",
                    action="store_false")
    ap.add_argument("--battlenet-prefix", default="",
                    help="umu Battle.net prefix; default: ~/Games/battlenet")
    ap.add_argument("--battlenet-config", default="",
                    help="explicit Battle.net.config path; default: auto")
    ap.add_argument("--lutris-cover-dir", default="",
                    help="Lutris coverart dir for Battle.net tiles;"
                    " default: ~/.local/share/lutris/coverart")
    args = ap.parse_args()

    steam_root = args.steam_root or default_steam_root()
    hide = {h.strip() for h in args.hide.split(",") if h.strip()}

    userdata = os.path.join(steam_root, "userdata")
    if args.steam_id:
        sids = [args.steam_id]
    else:
        sids = sorted(
            (d for d in os.listdir(userdata)
             if os.path.isfile(os.path.join(userdata, d, "config",
                                             "localconfig.vdf"))),
            key=lambda s: os.path.getmtime(os.path.join(
                userdata, s, "config", "localconfig.vdf")),
            reverse=True,
        ) if os.path.isdir(userdata) else []
    lc_paths = [os.path.join(userdata, s, "config/localconfig.vdf")
                for s in sids]
    grid_dirs = [os.path.join(userdata, s, "config/grid") for s in sids]

    recents = parse_recents(lc_paths)
    lib_paths = library_paths(steam_root)
    names = parse_manifest_names(lib_paths)
    try:
        overrides = json.loads(args.names) if args.names else {}
    except json.JSONDecodeError as e:
        print("steam_recent: ignoring invalid --names: %s" % e, file=sys.stderr)
        overrides = {}

    games = []
    for appid, info in recents.items():
        if info["lastPlayed"] <= 0 or appid in hide:
            continue
        if appid.startswith("-"):
            continue  # signed shortcut ids handled below via shortcuts.vdf
        art = find_art(steam_root, appid)
        if args.require_art and not art:
            continue
        name = (overrides.get(appid) or names.get(appid)
                or "App %s" % appid)
        games.append({
            "appid": int(appid),
            "name": name,
            "lastPlayed": info["lastPlayed"],
            "playtimeMin": info["playtimeMin"],
            "playtime2wksMin": info["playtime2wksMin"],
            "art": art,
            "source": "steam",
            "rungameid": int(appid),
        })

    if args.include_shortcuts:
        sc_paths = [os.path.join(userdata, s, "config/shortcuts.vdf")
                    for s in sids]
        for unsigned, sc in parse_shortcuts(sc_paths).items():
            if sc["lastPlayed"] <= 0 or unsigned in hide:
                continue
            # Playtime is tracked under the signed id in localconfig.vdf
            pt = recents.get(sc["signed"], {})
            art = find_shortcut_art(grid_dirs, unsigned)
            # Shortcut names are always known, so monogram tiles stay
            # meaningful: requireArt only filters Steam entries.
            name = overrides.get(unsigned) or sc["name"]
            games.append({
                "appid": int(unsigned),
                "name": name,
                "lastPlayed": sc["lastPlayed"],
                "playtimeMin": pt.get("playtimeMin", 0),
                "playtime2wksMin": pt.get("playtime2wksMin", 0),
                "art": art,
                "source": "shortcut",
                "rungameid": sc["rungameid"],
            })

    if args.include_battlenet:
        bnet_prefix = args.battlenet_prefix or default_battlenet_prefix()
        cfg_path = battlenet_config_path(bnet_prefix, args.battlenet_config)
        cover_dir = args.lutris_cover_dir or default_lutris_cover_dir()
        for uid, info in parse_battlenet_games(cfg_path).items():
            code, display, slug = BNET_MAP.get(
                uid.lower(), (uid.upper(), uid, uid.lower()))
            if (uid in hide or code in hide
                    or ("bnet:" + uid) in hide):
                continue
            art = find_bnet_art(cover_dir, slug, code, uid)
            # Battle.net names are always known, so monogram tiles stay
            # meaningful: requireArt only filters Steam entries.
            name = (overrides.get("bnet:" + uid) or overrides.get(uid)
                    or overrides.get(code) or display)
            games.append({
                "appid": "bnet:" + uid,
                "name": name,
                "lastPlayed": info["lastPlayed"],
                "playtimeMin": 0,
                "playtime2wksMin": 0,
                "art": art,
                "source": "battlenet",
                "rungameid": code,
                "launchCode": code,
                "uid": uid,
                "prefix": bnet_prefix,
            })

    games.sort(key=lambda g: -g["lastPlayed"])
    print(json.dumps(games[:max(1, args.count)]))


if __name__ == "__main__":
    main()
