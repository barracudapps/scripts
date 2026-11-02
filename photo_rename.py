#!/usr/bin/env python3
################################################################################
# Script:       photo_rename.py
# Description:  Renames photos and videos after the moment they were taken:
#               IMG_4521.HEIC -> 2026-11-02_14-35-12.heic, so they sort in
#               chronological order everywhere. Optionally files them in
#               YEAR/YEAR-MONTH folders.
#               Date: when the picture was taken (exiftool if installed, else
#               Spotlight), else the file date (marked "~" in the preview).
#               Live Photos and sidecar files (.MOV, .AAE, .XMP with the same
#               name) follow their photo. Same second: _2, _3... suffix.
#               Simulation by default: nothing changes without --apply. Every
#               run with --apply writes an undo file to restore the old names.
# Usage:        python3 ~/Documents/scripts/photo_rename.py FOLDER [--apply]
#                   [--by-month] [--dest DIR] [-r]
#               python3 ~/Documents/scripts/photo_rename.py --undo UNDO_FILE
#               --by-month  move into DEST/YYYY/YYYY-MM/ (DEST = FOLDER by default)
#               --dest      destination root for --by-month
#               -r          include sub-folders
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

PHOTOS = {".jpg", ".jpeg", ".heic", ".heif", ".png", ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf",
          ".orf", ".rw2", ".gif", ".webp", ".tif", ".tiff"}
VIDEOS = {".mov", ".mp4", ".m4v", ".3gp", ".avi", ".mts"}
SIDECARS = {".aae", ".xmp"}
ALREADY_NAMED = re.compile(r"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(_\d+)?$")
COLOR = sys.stdout.isatty()
BOLD, DIM, YELLOW, GREEN, NC = (("\033[1m", "\033[2m", "\033[93m", "\033[92m", "\033[0m")
                                if COLOR else ("",) * 5)


def exiftool_dates(files: list[Path]) -> dict[Path, datetime]:
    """Shooting date of each file, in local time (QuickTime UTC dates converted)."""
    exiftool = shutil.which("exiftool")
    if not exiftool or not files:
        return {}
    dates = {}
    for start in range(0, len(files), 500):
        batch = files[start:start + 500]
        out = subprocess.run(
            [exiftool, "-j", "-fast2", "-api", "QuickTimeUTC", "-d", "%Y-%m-%d %H:%M:%S",
             "-DateTimeOriginal", "-CreationDate", "-CreateDate", *map(str, batch)],
            capture_output=True, text=True).stdout
        try:
            rows = json.loads(out or "[]")
        except json.JSONDecodeError:
            continue
        for row in rows:
            for key in ("DateTimeOriginal", "CreationDate", "CreateDate"):
                value = str(row.get(key, ""))[:19]
                if value and not value.startswith("0000"):
                    try:
                        dates[Path(row["SourceFile"])] = datetime.strptime(value, "%Y-%m-%d %H:%M:%S")
                        break
                    except ValueError:
                        continue
    return dates


def spotlight_date(path: Path) -> datetime | None:
    out = subprocess.run(["mdls", "-raw", "-name", "kMDItemContentCreationDate", str(path)],
                         capture_output=True, text=True).stdout.strip()
    try:
        utc = datetime.strptime(out[:25], "%Y-%m-%d %H:%M:%S %z")
    except ValueError:
        return None
    return utc.astimezone().replace(tzinfo=None)


def file_date(path: Path) -> datetime:
    stat = path.stat()
    return datetime.fromtimestamp(min(getattr(stat, "st_birthtime", stat.st_mtime), stat.st_mtime))


def collect(folder: Path, recursive: bool) -> dict[tuple[Path, str], list[Path]]:
    """Files grouped by (folder, name without extension): a photo and its companions."""
    groups: dict[tuple[Path, str], list[Path]] = defaultdict(list)
    iterator = folder.rglob("*") if recursive else folder.iterdir()
    for path in iterator:
        if path.is_file() and not path.name.startswith(".") and path.suffix.lower() in PHOTOS | VIDEOS | SIDECARS:
            groups[(path.parent, path.stem.lower())].append(path)
    return groups


def primary(files: list[Path]) -> Path | None:
    """The file whose date names the group: the photo, else the video."""
    for kinds in (PHOTOS, VIDEOS):
        for path in sorted(files):
            if path.suffix.lower() in kinds:
                return path
    return None


def plan(args) -> list[tuple[Path, Path, bool]]:
    groups = collect(args.folder, args.recursive)
    mains = {key: primary(files) for key, files in groups.items()}
    mains = {key: path for key, path in mains.items() if path and not ALREADY_NAMED.match(path.stem)}
    dates = exiftool_dates(list(mains.values()))
    taken = set()
    moves = []
    for key in sorted(mains, key=lambda k: str(mains[k])):
        main = mains[key]
        when, guessed = dates.get(main), False
        if when is None and not shutil.which("exiftool"):
            when = spotlight_date(main)     # without exiftool; may be the file date
        if when is None:
            when, guessed = file_date(main), True
        folder = main.parent
        if args.by_month:
            folder = (args.dest or args.folder) / when.strftime("%Y") / when.strftime("%Y-%m")
        base = when.strftime("%Y-%m-%d_%H-%M-%S")
        counter = 1
        while True:
            name = base if counter == 1 else f"{base}_{counter}"
            targets = [folder / f"{name}{normal_suffix(p)}" for p in groups[key]]
            clash = any(t in taken or (t.exists() and t not in groups[key]) for t in targets)
            if not clash:
                break
            counter += 1
        for path, target in zip(groups[key], targets):
            taken.add(target)
            if path != target:
                moves.append((path, target, guessed))
    return moves


def normal_suffix(path: Path) -> str:
    suffix = path.suffix.lower()
    return ".jpg" if suffix == ".jpeg" else suffix


def undo(log: Path) -> int:
    restored = 0
    for line in reversed(log.read_text(encoding="utf-8").splitlines()):
        new, _, old = line.partition("\t")
        if not old:
            continue
        if Path(old).exists():
            print(f"{YELLOW}skipped{NC} {old} exists again")
            continue
        if not Path(new).exists():
            print(f"{YELLOW}missing{NC} {new}")
            continue
        Path(old).parent.mkdir(parents=True, exist_ok=True)
        shutil.move(new, old)
        restored += 1
        # Remove the YEAR/YEAR-MONTH folders left empty
        for folder in (Path(new).parent, Path(new).parent.parent):
            try:
                folder.rmdir()
            except OSError:
                break
    print(f"{GREEN}{restored} file(s) got their old name back.{NC}")
    log.rename(log.with_suffix(".undone"))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Rename photos and videos after their shooting date.")
    parser.add_argument("folder", nargs="?", type=Path)
    parser.add_argument("--apply", action="store_true", help="really rename (default: simulation)")
    parser.add_argument("--by-month", action="store_true", help="file into YYYY/YYYY-MM folders")
    parser.add_argument("--dest", type=Path)
    parser.add_argument("-r", "--recursive", action="store_true")
    parser.add_argument("--undo", type=Path, help="undo file written by a previous --apply")
    args = parser.parse_args()
    if args.undo:
        return undo(args.undo)
    if not args.folder or not args.folder.is_dir():
        parser.error("give a folder")
    args.folder = args.folder.expanduser().resolve()
    if args.dest:
        args.dest = args.dest.expanduser().resolve()
    if not shutil.which("exiftool"):
        print(f"{DIM}exiftool not installed: dates come from Spotlight (brew install exiftool is more "
              f"reliable){NC}")

    moves = plan(args)
    if not moves:
        print(f"{GREEN}Nothing to rename.{NC}")
        return 0
    root = args.dest if args.by_month and args.dest else args.folder
    for path, target, guessed in moves:
        mark = f"{YELLOW}~{NC}" if guessed else " "
        shown = os.path.relpath(target, root) if args.by_month else target.name
        print(f" {mark} {os.path.relpath(path, args.folder):<40} -> {shown}")
    guessed_count = sum(1 for m in moves if m[2])
    print(f"\n{BOLD}{len(moves)} file(s) to rename.{NC}"
          + (f" {YELLOW}~{NC} {guessed_count} without shooting date (file date used)." if guessed_count else ""))
    if not args.apply:
        print(f"{DIM}Simulation only: add --apply to rename.{NC}")
        return 0

    log = root / f".photo_rename_{datetime.now():%Y%m%d-%H%M%S}.tsv"
    done = 0
    with log.open("w", encoding="utf-8") as handle:
        for path, target, _guessed in moves:
            if target.exists():
                print(f"{YELLOW}skipped{NC} {target} already exists")
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(target))
            handle.write(f"{target}\t{path}\n")
            handle.flush()
            done += 1
    print(f"{GREEN}{done} file(s) renamed.{NC} Undo with:\n  python3 {Path(__file__)} --undo '{log}'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
