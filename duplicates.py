#!/usr/bin/env python3
################################################################################
# Script:       duplicates.py
# Description:  Finds duplicate files (photos, PDF, downloads...) by content:
#               same size first, then a quick hash of the first 64 KB, then a
#               full hash, so different files are never mixed up.
#               For each group, the copy to keep is the best placed one (in a
#               protected folder, not in Downloads, shortest name without
#               " (1)" / " copy", oldest). The others can go to the Trash.
#               Read-only by default. With --clean, each group is confirmed:
#               everything, one by one, or nothing. Never moved: copies in
#               client folders and clouds (iCloud, Dropbox...), files evicted
#               to iCloud (not downloaded to read them), hard links. Git
#               repositories and build folders are skipped.
# Usage:        python3 ~/Documents/scripts/duplicates.py [FOLDER...] [--clean]
#                   [--min-size KB] [--top N]
#               FOLDER      default: Downloads, Desktop, Documents, Pictures
#                           (the Photos library itself is skipped)
#               --min-size  ignore files smaller than KB (default 100)
#               --top N     show the N groups wasting the most space (default 30,
#                           0 = all); the summary always covers every group
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from mac_common import (  # noqa: E402
    BOLD,
    DIM,
    GREEN,
    HOME,
    NC,
    choose_and_trash,
    human,
    is_dataless,
    is_inside,
    is_protected,
    short,
)

DEFAULT_ROOTS = [HOME / "Downloads", HOME / "Desktop", HOME / "Documents", HOME / "Pictures"]
SKIP_DIRS = {"Library", ".Trash", "node_modules", ".venv", "venv", "__pycache__", ".cache", "build", "dist",
             "Pods", ".dart_tool", "DerivedData", "SourcePackages", "target", ".gradle", "site-packages"}
SKIP_SUFFIXES = (".photoslibrary", ".app", ".musiclibrary", ".tvlibrary", ".imovielibrary",
                 ".fcpbundle", ".xcarchive", ".bundle", ".framework", ".lrdata")
COPY_NAME = re.compile(r"( \(\d+\)| \d+| copy( \d+)?| copie( \d+)?|-\d+|_\d+)$", re.IGNORECASE)
CHUNK = 1024 * 1024


def walk(roots: list[Path], min_size: int):
    """(path, size, inode) of the regular files worth comparing."""
    seen_inodes = set()
    for root in roots:
        for dirpath, dirs, files in os.walk(root, onerror=lambda e: None):
            if ".git" in dirs or ".git" in files:   # code repository: git manages its files
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs
                       if d not in SKIP_DIRS and not d.startswith(".") and not d.endswith(SKIP_SUFFIXES)]
            for name in files:
                if name.startswith("."):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    stat = os.lstat(path)
                except OSError:
                    continue
                if not os.path.isfile(path) or os.path.islink(path) or stat.st_size < min_size:
                    continue
                if is_dataless(path):
                    continue
                key = (stat.st_dev, stat.st_ino)
                if key in seen_inodes:      # hard link or folder given twice: same file
                    continue
                seen_inodes.add(key)
                yield Path(path), stat.st_size


def digest(path: Path, limit: int | None = None) -> str | None:
    hasher = hashlib.blake2b(digest_size=20)
    try:
        with path.open("rb") as handle:
            if limit:
                hasher.update(handle.read(limit))
            else:
                for block in iter(lambda: handle.read(CHUNK), b""):
                    hasher.update(block)
    except OSError:
        return None
    return hasher.hexdigest()


def find_groups(roots: list[Path], min_size: int) -> list[tuple[int, list[Path]]]:
    by_size: dict[int, list[Path]] = defaultdict(list)
    for path, size in walk(roots, min_size):
        by_size[size].append(path)
    candidates = {size: paths for size, paths in by_size.items() if len(paths) > 1}
    print(f"{DIM}{sum(len(p) for p in candidates.values())} file(s) share a size with another one, "
          f"comparing their content...{NC}", file=sys.stderr)

    groups = []
    for size, paths in candidates.items():
        by_head: dict[str, list[Path]] = defaultdict(list)
        for path in paths:
            head = digest(path, 64 * 1024)
            if head:
                by_head[head].append(path)
        for same_head in by_head.values():
            if len(same_head) < 2:
                continue
            if size <= 64 * 1024:       # the head was the whole file
                groups.append((size, same_head))
                continue
            by_full: dict[str, list[Path]] = defaultdict(list)
            for path in same_head:
                full = digest(path)
                if full:
                    by_full[full].append(path)
            groups += [(size, same) for same in by_full.values() if len(same) > 1]
    return groups


def keeper_score(path: Path) -> tuple:
    """Lower is better: the copy most likely to be the one the user filed."""
    in_temporary = is_inside(path, HOME / "Downloads")
    looks_like_copy = bool(COPY_NAME.search(path.stem))
    try:
        mtime = path.stat().st_mtime
    except OSError:
        mtime = 0
    return (not is_protected(path), in_temporary, looks_like_copy, len(path.parts), len(path.name), mtime)


def main() -> int:
    parser = argparse.ArgumentParser(description="Find duplicate files by content.")
    parser.add_argument("folders", nargs="*", type=Path)
    parser.add_argument("--clean", action="store_true", help="move the extra copies to the Trash")
    parser.add_argument("--min-size", type=int, default=100, help="minimum size in KB (default 100)")
    parser.add_argument("--top", type=int, default=30, help="groups shown (0 = all)")
    args = parser.parse_args()

    roots = [p.expanduser().resolve() for p in args.folders] or [p for p in DEFAULT_ROOTS if p.is_dir()]
    for root in roots:
        if not root.is_dir():
            sys.exit(f"Not a folder: {root}")
    # A folder inside another one would be walked twice
    roots = [r for r in roots if not any(r != o and is_inside(r, o) for o in roots)]

    groups = find_groups(roots, args.min_size * 1024)
    groups.sort(key=lambda g: -g[0] * (len(g[1]) - 1))
    if not groups:
        print(f"{GREEN}No duplicates found in {', '.join(short(r) for r in roots)}.{NC}")
        return 0

    wasted = moved = 0
    folder_pairs: dict[tuple[Path, Path], int] = defaultdict(int)
    for size, paths in groups:
        paths.sort(key=keeper_score)
        keep, extras = paths[0], paths[1:]
        wasted += size * len(extras)
        for path in extras:
            folder_pairs[(keep.parent, path.parent)] += size
    shown = groups[:args.top] if args.top else groups
    for size, paths in shown:
        keep, extras = paths[0], paths[1:]
        removable = [p for p in extras if not is_protected(p)]
        print(f"\n{BOLD}{human(size)} x {len(paths)}{NC}  {DIM}{keep.name}{NC}")
        print(f"  {GREEN}keep{NC}    {short(keep)}")
        for path in extras:
            label = "copy   " if path in removable else f"{DIM}copy (protected folder, left alone){NC}"
            print(f"  {label} {short(path)}")
        if args.clean and removable:
            moved += choose_and_trash([(p, size) for p in removable], indent="  ")

    if len(shown) < len(groups):
        print(f"\n{DIM}... {len(groups) - len(shown)} smaller group(s) not shown (--top 0 to see them all){NC}")
    print(f"\n{BOLD}Folders sharing the most duplicates{NC} {DIM}(a whole copied folder?){NC}")
    for (kept, copied), size in sorted(folder_pairs.items(), key=lambda kv: -kv[1])[:5]:
        print(f"  {human(size):>9}  {short(copied)}\n             {DIM}copy of{NC} {short(kept)}")
    print(f"\n{BOLD}{len(groups)} group(s) of duplicates, {human(wasted)} taken by the extra copies.{NC}")
    if args.clean:
        print(f"Moved to the Trash: {human(moved)} - empty the Trash to free the space.")
    else:
        print(f"{DIM}Run with --clean to choose which copies go to the Trash.{NC}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
