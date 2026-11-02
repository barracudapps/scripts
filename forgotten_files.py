#!/usr/bin/env python3
################################################################################
# Script:       forgotten_files.py
# Description:  Looks through the home folder and the applications for old,
#               forgotten and non-essential files: old downloads, installers,
#               big files not opened for a long time, rebuildable folders of
#               inactive projects, old screenshots, iOS backups and debug
#               symbols, old logs, the Trash, unused applications.
#               Age = last opening known by Spotlight, else last modification.
#               Read-only by default. With --clean, each category shows its
#               detailed list, then asks: everything, one by one, or nothing.
#               Items go to the Trash (recoverable), never deleted directly.
#               Never touched: client folders (except rebuildable folders such
#               as node_modules/.venv), iCloud/Dropbox/Google Drive, the
#               applications themselves (only reported).
# Usage:        python3 ~/Documents/scripts/forgotten_files.py [--clean] [--days N]
#                   [--min-size MB] [--only CATEGORY]
#               --days N       age threshold for downloads, big files, projects
#                              (default 180)
#               --min-size MB  "big file" threshold (default 200)
#               --only         downloads, installers, big, projects, screenshots,
#                              ios, logs, trash, apps
# Notes:        Dev caches and Odoo databases: see disk_report.sh. Some folders
#               (Trash, iOS backups) need Full Disk Access for the terminal.
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from mac_common import (  # noqa: E402
    BOLD,
    DIM,
    HOME,
    NC,
    YELLOW,
    choose_and_trash,
    human,
    is_protected,
    short,
    size_of,
)

NOW = time.time()
DAY = 86400

REBUILDABLE = {"node_modules", ".venv", "venv", "Pods", ".dart_tool", ".gradle", ".next", ".nuxt",
               "build", "dist", "target"}
MIN_REBUILDABLE_SIZE = 10 * 1024 * 1024
PROJECT_MARKERS = {".git", "package.json", "pyproject.toml", "pubspec.yaml", "requirements.txt",
                   "Podfile", "build.gradle", "Cargo.toml", "composer.json", "__manifest__.py"}
INSTALLER_EXT = {".dmg", ".pkg", ".iso", ".xip", ".mpkg", ".msi", ".exe", ".apk", ".ipa"}
SKIP_WALK = {"Library", ".Trash", "node_modules", ".git", ".venv", "Applications", ".cache", ".npm",
             ".nvm", ".local", "go", "Pictures", "Music", "Movies"}


class Item:
    def __init__(self, path: Path, size: int, age_days: float, note: str = ""):
        self.path, self.size, self.age_days, self.note = path, size, age_days, note


def last_used_days(path: Path) -> float:
    """Days since last opening (Spotlight), else since last modification."""
    timestamp = None
    try:
        out = subprocess.run(["mdls", "-raw", "-name", "kMDItemLastUsedDate", str(path)],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        if out and out != "(null)":
            timestamp = datetime.strptime(out[:19], "%Y-%m-%d %H:%M:%S").timestamp()
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    try:
        modified = path.stat().st_mtime
    except OSError:
        return 0
    return (NOW - max(timestamp or 0, modified)) / DAY


def newest_mtime(path: Path, max_files: int = 4000) -> float:
    """Most recent modification inside a project, ignoring rebuildable folders."""
    newest, seen = 0.0, 0
    for dirpath, dirs, files in os.walk(path, onerror=lambda e: None):
        dirs[:] = [d for d in dirs if d not in REBUILDABLE and d != ".git"]
        for name in files:
            try:
                newest = max(newest, os.lstat(os.path.join(dirpath, name)).st_mtime)
            except OSError:
                pass
            seen += 1
            if seen >= max_files:
                return newest
    return newest


# ------------------------------------------------------------------ categories

def cat_downloads(args) -> list[Item]:
    items = []
    folder = HOME / "Downloads"
    for path in folder.iterdir() if folder.is_dir() else []:
        if path.name.startswith("."):
            continue
        age = last_used_days(path)
        if age >= args.days:
            items.append(Item(path, size_of(path), age))
    return items


def cat_installers(args) -> list[Item]:
    items = []
    for root in (HOME / "Downloads", HOME / "Desktop", HOME / "Documents"):
        for dirpath, dirs, files in os.walk(root, onerror=lambda e: None):
            dirs[:] = [d for d in dirs if d not in SKIP_WALK and not d.startswith(".")]
            current = Path(dirpath)
            if is_protected(current):
                dirs[:] = []
                continue
            for name in files:
                path = current / name
                if path.suffix.lower() in INSTALLER_EXT:
                    age = last_used_days(path)
                    if age >= 30:
                        items.append(Item(path, size_of(path), age))
    return items


def cat_big(args) -> list[Item]:
    query = f"kMDItemFSSize > {args.min_size * 1024 * 1024}"
    out = subprocess.run(["mdfind", "-onlyin", str(HOME), query], capture_output=True, text=True).stdout
    items = []
    for line in out.splitlines():
        path = Path(line)
        parts = set(path.parts)
        if (not path.is_file() or is_protected(path) or "Library" in parts or ".Trash" in parts
                or path.suffix.lower() in INSTALLER_EXT or path.is_relative_to(HOME / "Downloads")):
            continue
        age = last_used_days(path)
        if age >= args.days:
            items.append(Item(path, size_of(path), age))
    return items


def cat_projects(args) -> list[Item]:
    items = []
    for root in (HOME / "Documents", HOME / "Desktop", HOME / "Downloads"):
        for dirpath, dirs, files in os.walk(root, onerror=lambda e: None):
            current = Path(dirpath)
            if len(current.relative_to(root).parts) > 5 or current.name in {"Library", ".Trash"}:
                dirs[:] = []
                continue
            if not (PROJECT_MARKERS & (set(files) | set(dirs))):
                continue
            heavy = [d for d in dirs if d in REBUILDABLE]
            if not heavy:
                continue
            inactive_days = (NOW - newest_mtime(current)) / DAY
            if inactive_days >= args.days:
                for name in heavy:
                    target = current / name
                    size = size_of(target)
                    if size >= MIN_REBUILDABLE_SIZE:
                        items.append(Item(target, size, inactive_days, "project inactive, rebuildable"))
            dirs[:] = [d for d in dirs if d not in REBUILDABLE and d not in SKIP_WALK and not d.startswith(".")]
    return items


def cat_screenshots(args) -> list[Item]:
    items = []
    prefixes = ("Capture d", "Screenshot", "Screen Shot", "Enregistrement de l", "Screen Recording")
    for folder in (HOME / "Desktop", HOME / "Documents", HOME / "Downloads"):
        for path in folder.iterdir() if folder.is_dir() else []:
            if path.is_file() and path.name.startswith(prefixes):
                age = last_used_days(path)
                if age >= 90:
                    items.append(Item(path, size_of(path), age))
    return items


def cat_ios(args) -> list[Item]:
    items = []
    support = HOME / "Library" / "Developer" / "Xcode"
    for kind in ("iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport"):
        folder = support / kind
        versions = sorted((p for p in folder.iterdir() if p.is_dir()), key=lambda p: p.stat().st_mtime) \
            if folder.is_dir() else []
        for path in versions[:-1]:     # keep the most recent one
            items.append(Item(path, size_of(path), (NOW - path.stat().st_mtime) / DAY, f"old {kind}"))
    archives = support / "Archives"
    for path in archives.glob("*/*.xcarchive") if archives.is_dir() else []:
        age = (NOW - path.stat().st_mtime) / DAY
        if age >= 365:
            items.append(Item(path, size_of(path), age, "Xcode archive"))
    backups = HOME / "Library" / "Application Support" / "MobileSync" / "Backup"
    try:
        for path in backups.iterdir():
            age = (NOW - path.stat().st_mtime) / DAY
            if age >= args.days:
                items.append(Item(path, size_of(path), age, "iPhone/iPad backup"))
    except PermissionError:
        print(f"  {YELLOW}!{NC} iPhone backups unreadable: give Full Disk Access to the terminal to include them")
    except FileNotFoundError:
        pass
    return items


def cat_logs(args) -> list[Item]:
    items = []
    for folder in (HOME / "Library" / "Logs", HOME / "Library" / "Logs" / "DiagnosticReports"):
        for path in folder.iterdir() if folder.is_dir() else []:
            if path.name in {"DiagnosticReports", "maintenance"}:
                continue
            try:
                age = (NOW - path.lstat().st_mtime) / DAY
            except OSError:
                continue
            if age >= 90:
                items.append(Item(path, size_of(path), age))
    return items


def cat_trash(args) -> list[Item]:
    trash = HOME / ".Trash"
    try:
        entries = list(trash.iterdir())
    except PermissionError:
        print(f"  {YELLOW}!{NC} Trash unreadable: give Full Disk Access to the terminal to measure it")
        return []
    total = sum(size_of(p) for p in entries)
    if not total:
        return []
    return [Item(trash, total, 0, f"{len(entries)} item(s): empty it from the Finder")]


def cat_apps(args) -> list[Item]:
    items = []
    for path in sorted(Path("/Applications").glob("*.app")):
        out = subprocess.run(["mdls", "-raw", "-name", "kMDItemLastUsedDate", str(path)],
                             capture_output=True, text=True).stdout.strip()
        if not out or out == "(null)":
            continue        # never opened through Launch Services: unknown, not reported
        age = (NOW - datetime.strptime(out[:19], "%Y-%m-%d %H:%M:%S").timestamp()) / DAY
        if age >= 365:
            items.append(Item(path, size_of(path), age, "not opened for a year (uninstall it yourself)"))
    return items


CATEGORIES = [
    ("downloads", "Old downloads", cat_downloads, True),
    ("installers", "Installers and disk images (.dmg, .pkg, .iso...) older than 30 days", cat_installers, True),
    ("big", "Big files not opened for a long time", cat_big, True),
    ("projects", "Rebuildable folders of inactive projects (node_modules, .venv, build...)", cat_projects, True),
    ("screenshots", "Screenshots and screen recordings older than 90 days", cat_screenshots, True),
    ("ios", "iOS debug symbols, old Xcode archives and device backups", cat_ios, True),
    ("logs", "Logs and crash reports older than 90 days", cat_logs, True),
    ("trash", "Trash", cat_trash, False),
    ("apps", "Applications not opened for a year", cat_apps, False),
]


# ------------------------------------------------------------------ cleaning

def main() -> int:
    parser = argparse.ArgumentParser(description="Find old, forgotten and non-essential files.")
    parser.add_argument("--clean", action="store_true", help="move selected items to the Trash")
    parser.add_argument("--days", type=int, default=180)
    parser.add_argument("--min-size", type=int, default=200, help="big file threshold in MB")
    parser.add_argument("--only", choices=[c[0] for c in CATEGORIES])
    args = parser.parse_args()

    grand_total, freed = 0, 0
    for key, title, finder, cleanable in CATEGORIES:
        if args.only and key != args.only:
            continue
        print(f"\n{BOLD}{title}{NC}")
        items = sorted(finder(args), key=lambda i: -i.size)
        items = [i for i in items if i.size > 0]
        if not items:
            print("  (nothing)")
            continue
        total = sum(i.size for i in items)
        for item in items:
            age = f"{item.age_days / 30:.0f} months" if item.age_days >= 60 else f"{item.age_days:.0f} days"
            note = f" {DIM}({item.note}){NC}" if item.note else ""
            print(f"  {human(item.size):>9}  {age:>10}  {short(item.path)}{note}")
        print(f"  {DIM}{len(items)} item(s), {human(total)}{NC}")
        if cleanable:
            grand_total += total
            if args.clean:
                freed += choose_and_trash([(i.path, i.size) for i in items])

    print(f"\n{BOLD}Reclaimable (categories that can be cleaned): {human(grand_total)}{NC}")
    if args.clean:
        print(f"Moved to the Trash: {human(freed)} — empty the Trash to free the space.")
    else:
        print(f"{DIM}Run with --clean to move items to the Trash after confirmation. "
              f"Dev caches and Odoo databases: disk_report.sh{NC}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
