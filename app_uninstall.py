#!/usr/bin/env python3
################################################################################
# Script:       app_uninstall.py
# Description:  Uninstalls an application completely: the app and what it left
#               in ~/Library (preferences, caches, Application Support,
#               containers, saved state, logs, cookies, launch agents...).
#               Leftovers are matched on the exact bundle identifier or the
#               exact app name only, never on a partial word. Everything is
#               listed with its size, then moved to the Trash after
#               confirmation (recoverable). System-wide leftovers (/Library)
#               need an administrator: the commands are printed, not run.
#               Refuses Apple apps and running apps. Apps installed with
#               Homebrew are redirected to "brew uninstall --cask --zap".
# Usage:        python3 ~/Documents/scripts/app_uninstall.py NAME|PATH [--dry-run]
#               python3 ~/Documents/scripts/app_uninstall.py --list
#               python3 ~/Documents/scripts/app_uninstall.py --leftovers
#               NAME         "Zoom", "zoom.us.app" or /Applications/zoom.us.app
#               --list       installed apps, least recently opened first
#               --leftovers  ~/Library folders of apps that are no longer
#                            installed (review them, nothing is moved)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import difflib
import json
import plistlib
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from mac_common import (  # noqa: E402
    BOLD,
    DIM,
    GREEN,
    HOME,
    NC,
    RED,
    YELLOW,
    confirm,
    human,
    move_to_trash,
    short,
    size_of,
    spotlight_date,
)

APP_DIRS = [Path("/Applications"), Path("/Applications/Utilities"), HOME / "Applications"]
LIBRARY = HOME / "Library"
USER_PLACES = ["Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers",
               "Group Containers", "Saved Application State", "Logs", "HTTPStorages", "WebKit",
               "LaunchAgents", "Application Scripts", "Cookies", "Autosave Information", "."]
SYSTEM_PLACES = ["/Library/Application Support", "/Library/Caches", "/Library/Preferences",
                 "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
                 "/Library/Logs"]
# Names too generic to match a folder on the app name alone
GENERIC_NAMES = {"app", "apps", "code", "data", "electron", "helper", "launcher", "mail", "music", "notes",
                 "photos", "preview", "settings", "setup", "support", "tools", "update", "updater"}


class App:
    def __init__(self, path: Path):
        self.path = path
        info = {}
        try:
            with (path / "Contents" / "Info.plist").open("rb") as handle:
                info = plistlib.load(handle)
        except (OSError, plistlib.InvalidFileException, ValueError):
            pass
        self.bundle_id: str = info.get("CFBundleIdentifier", "")
        self.names = {n for n in (path.stem, info.get("CFBundleName"), info.get("CFBundleDisplayName"))
                      if isinstance(n, str) and len(n) >= 3 and n.lower() not in GENERIC_NAMES}
        self.version = info.get("CFBundleShortVersionString", "")
        self.team_id = ""
        out = subprocess.run(["codesign", "-dv", str(path)], capture_output=True, text=True).stderr
        for line in out.splitlines():
            if line.startswith("TeamIdentifier=") and line.split("=", 1)[1] != "not set":
                self.team_id = line.split("=", 1)[1]

    def matches(self, entry: str, place: str) -> bool:
        """Exact match on the bundle identifier or the app name, nothing fuzzier."""
        lower = entry.lower()
        bundle = self.bundle_id.lower()
        if bundle:
            if lower == bundle or lower.startswith(bundle + "."):        # .plist, .savedState, .binarycookies
                return True
            if place == "Group Containers" and lower in (f"group.{bundle}", f"{self.team_id.lower()}.{bundle}"):
                return True
        if place in ("Containers", "Group Containers", "Preferences", "Preferences/ByHost", "Cookies",
                     "LaunchAgents", "HTTPStorages", "WebKit", "Saved Application State"):
            return False        # these are always named after the bundle identifier
        stem = lower.rsplit(".", 1)[0] if place == "Logs" else lower
        return any(stem == name.lower() for name in self.names)


def find_app(query: str) -> Path:
    candidate = Path(query).expanduser()
    if candidate.suffix == ".app" and candidate.is_dir():
        return candidate.resolve()
    wanted = query.lower().removesuffix(".app")
    apps = [p for folder in APP_DIRS if folder.is_dir() for p in folder.glob("*.app")]
    for path in apps:
        if path.stem.lower() == wanted:
            return path
    close = difflib.get_close_matches(wanted, [p.stem.lower() for p in apps], n=5, cutoff=0.5)
    partial = [p.stem for p in apps if wanted in p.stem.lower()]
    hint = sorted(set(partial) | {p.stem for p in apps if p.stem.lower() in close})
    sys.exit(f"No application named '{query}'." + (f" Did you mean: {', '.join(hint)}?" if hint else ""))


def is_running(app: Path) -> bool:
    return subprocess.run(["pgrep", "-f", f"{app}/Contents/MacOS/"], capture_output=True).returncode == 0


def homebrew_cask(app: Path) -> str | None:
    if not shutil.which("brew"):
        return None
    out = subprocess.run(["brew", "info", "--cask", "--installed", "--json=v2"],
                         capture_output=True, text=True).stdout
    try:
        casks = json.loads(out).get("casks", [])
    except json.JSONDecodeError:
        return None
    for cask in casks:
        for artifact in cask.get("artifacts", []):
            for entry in artifact.get("app", []) if isinstance(artifact, dict) else []:
                if isinstance(entry, str) and Path(entry).name == app.name:
                    return cask.get("token")
    return None


def leftovers(app: App) -> tuple[list[Path], list[Path]]:
    user, system = [], []
    for place in USER_PLACES:
        folder = LIBRARY / place
        try:
            entries = list(folder.iterdir())
        except OSError:
            continue
        for entry in entries:
            if place == "." and entry.is_file():
                continue
            if app.matches(entry.name, place) and entry != app.path:
                user.append(entry)
    for place in SYSTEM_PLACES:
        try:
            entries = list(Path(place).iterdir())
        except OSError:
            continue
        system += [e for e in entries if app.matches(e.name, place.split("/")[-1])]
    return sorted(set(user)), sorted(set(system))


def stop_launch_agents(paths: list[Path]) -> None:
    uid = subprocess.run(["id", "-u"], capture_output=True, text=True).stdout.strip()
    for path in paths:
        if path.parent == LIBRARY / "LaunchAgents" and path.suffix == ".plist":
            subprocess.run(["launchctl", "bootout", f"gui/{uid}", str(path)], capture_output=True)


def last_opened(path: Path) -> str:
    date = spotlight_date(path)
    if not date:
        return "never/unknown"
    days = (datetime.now(timezone.utc) - date).days
    return f"{days // 30} months ago" if days >= 60 else f"{days} days ago"


def cmd_list() -> int:
    rows = []
    for folder in APP_DIRS:
        for path in folder.glob("*.app") if folder.is_dir() else []:
            date = spotlight_date(path)
            rows.append((date.timestamp() if date else 0, path))
    rows.sort(key=lambda r: r[0])
    print(f"{BOLD}{'Size':>9}  {'Last opened':<15} Application{NC}")
    for _timestamp, path in rows:
        print(f"  {human(size_of(path)):>9}  {last_opened(path):<15} {short(path)}")
    print(f"{DIM}Uninstall one with: python3 {short(Path(__file__))} NAME{NC}")
    return 0


def cmd_leftovers() -> int:
    """Library folders named after a bundle identifier with no matching app."""
    installed = set()
    for folder in APP_DIRS + [Path("/System/Applications"), Path("/System/Applications/Utilities")]:
        for path in folder.glob("*.app") if folder.is_dir() else []:
            bundle = App(path).bundle_id.lower()
            if bundle:
                installed.add(bundle)
    out = subprocess.run(["mdfind", "kMDItemContentType == com.apple.application-bundle"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        try:
            with open(Path(line) / "Contents" / "Info.plist", "rb") as handle:
                installed.add(str(plistlib.load(handle).get("CFBundleIdentifier", "")).lower())
        except (OSError, plistlib.InvalidFileException, ValueError):
            pass
    found = []
    for place in ("Containers", "Application Support", "Caches", "Saved Application State", "HTTPStorages"):
        folder = LIBRARY / place
        try:
            entries = list(folder.iterdir())
        except OSError:
            continue
        for entry in entries:
            name = entry.name.lower().removesuffix(".savedstate")
            if name.count(".") < 2 or name.startswith(("com.apple.", "group.com.apple.")):
                continue
            if not any(name == b or name.startswith(b + ".") or b.startswith(name + ".") for b in installed):
                size = size_of(entry)
                if size >= 1024 * 1024:
                    found.append((size, entry))
    found.sort(key=lambda f: -f[0])
    print(f"{BOLD}Possible leftovers of apps no longer installed (>= 1 MB){NC}")
    for size, entry in found:
        print(f"  {human(size):>9}  {short(entry)}")
    print(f"{DIM}{len(found)} folder(s), {human(sum(f[0] for f in found))}. Check each name before deleting: "
          f"helpers and command-line tools also use such folders.{NC}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Uninstall an application and its leftovers.")
    parser.add_argument("app", nargs="?")
    parser.add_argument("--dry-run", action="store_true", help="only show what would be moved")
    parser.add_argument("--list", action="store_true", help="installed apps, least recently opened first")
    parser.add_argument("--leftovers", action="store_true", help="folders of apps no longer installed")
    args = parser.parse_args()
    if args.list:
        return cmd_list()
    if args.leftovers:
        return cmd_leftovers()
    if not args.app:
        parser.error("give an application name, --list or --leftovers")

    path = find_app(args.app)
    app = App(path)
    if app.bundle_id.startswith("com.apple.") or str(path).startswith("/System/"):
        sys.exit(f"{path.name} is part of macOS: not uninstalled.")
    if is_running(path):
        sys.exit(f"{path.name} is running: quit it first (Cmd-Q), then run this again.")
    cask = homebrew_cask(path)
    if cask:
        print(f"{YELLOW}{path.name} was installed with Homebrew.{NC} Uninstall it with:\n"
              f"  brew uninstall --cask --zap {cask}")
        return 0

    user, system = leftovers(app)
    print(f"{BOLD}{path.stem}{NC} {app.version}  {DIM}{app.bundle_id or 'no bundle identifier'}"
          f"{f', team {app.team_id}' if app.team_id else ''}, last opened {last_opened(path)}{NC}\n")
    items = [(path, size_of(path))] + [(p, size_of(p)) for p in user]
    for item, size in items:
        print(f"  {human(size):>9}  {short(item)}")
    total = sum(size for _p, size in items)
    print(f"  {DIM}{len(items)} item(s), {human(total)}{NC}")
    if system:
        print(f"\n{YELLOW}System-wide leftovers{NC} (administrator needed, review then run yourself):")
        for item in system:
            print(f"  sudo rm -rf '{item}'")
    if args.dry_run:
        return 0
    if not confirm(f"\nMove these {len(items)} item(s) to the Trash?"):
        print("Nothing moved.")
        return 0

    stop_launch_agents(user)
    moved = 0
    for item, size in items:
        if move_to_trash(item):
            moved += size
        elif item == path:
            print(f"  {RED}The app itself could not be moved{NC} (owned by the system or the App Store): "
                  f"drag it to the Trash in the Finder.")
            subprocess.run(["open", "-R", str(path)])
    print(f"\n{GREEN}Moved to the Trash: {human(moved)}{NC} - empty the Trash to free the space.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
