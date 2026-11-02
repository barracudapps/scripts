#!/usr/bin/env python3
################################################################################
# Script:       lib/mac_common.py
# Description:  Shared helpers for the everyday Mac scripts (forgotten_files,
#               duplicates, app_uninstall, startup_items...): sizes, protected
#               folders, NFC path comparison, safe move to the Trash, questions
#               asked on the terminal even when stdin is redirected.
#               Python 3.9+, stdlib only. Not meant to be run directly.
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

HOME = Path.home()
TRASH = HOME / ".Trash"
COLOR = sys.stdout.isatty()
BOLD, DIM, RED, GREEN, YELLOW, NC = (
    ("\033[1m", "\033[2m", "\033[91m", "\033[92m", "\033[93m", "\033[0m") if COLOR else ("",) * 6
)

# Never cleaned automatically: client work and synchronised clouds
PROTECTED = [
    HOME / "Desktop" / "Indépendant BApps" / "Clients",
    HOME / "Library" / "Mobile Documents",      # iCloud Drive
    HOME / "Library" / "CloudStorage",          # Dropbox, Google Drive, OneDrive...
    HOME / "Dropbox",
    HOME / "Google Drive",
]

# st_flags bit of a file evicted to iCloud (reading it would download it)
SF_DATALESS = 0x40000000


def human(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return ""


def nfc(path: Path | str) -> str:
    # macOS returns decomposed accents (NFD) from the file system: compare in NFC
    return unicodedata.normalize("NFC", str(path))


def is_inside(path: Path | str, root: Path | str) -> bool:
    text, root_text = nfc(path), nfc(root).rstrip(os.sep)
    return text == root_text or text.startswith(root_text + os.sep)


def is_protected(path: Path | str) -> bool:
    return any(is_inside(path, root) for root in PROTECTED)


def is_dataless(path: Path | str) -> bool:
    try:
        return bool(os.lstat(path).st_flags & SF_DATALESS)
    except (OSError, AttributeError):
        return False


def size_of(path: Path) -> int:
    try:
        if path.is_symlink():
            return 0
        if path.is_file():
            return path.stat().st_size
        total = 0
        for dirpath, _dirs, files in os.walk(path, onerror=lambda e: None):
            for name in files:
                try:
                    total += os.lstat(os.path.join(dirpath, name)).st_size
                except OSError:
                    pass
        return total
    except OSError:
        return 0


def spotlight_date(path: Path | str, attribute: str = "kMDItemLastUsedDate") -> datetime | None:
    """Date attribute from Spotlight (UTC), None when unknown."""
    try:
        out = subprocess.run(["mdls", "-raw", "-name", attribute, str(path)],
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    if not out or out == "(null)":
        return None
    try:
        return datetime.strptime(out[:25], "%Y-%m-%d %H:%M:%S %z")
    except ValueError:
        return None


def short(path: Path | str) -> str:
    text = str(path)
    return "~" + text[len(str(HOME)):] if text.startswith(str(HOME)) else text


def move_to_trash(path: Path) -> bool:
    """Move to the user Trash with a unique name (recoverable from the Finder)."""
    target = TRASH / path.name
    counter = 2
    while target.exists() or target.is_symlink():
        stem, suffix = (path.stem, path.suffix) if path.is_file() else (path.name, "")
        target = TRASH / f"{stem} {counter}{suffix}"
        counter += 1
    try:
        shutil.move(str(path), str(target))
        return True
    except OSError as exc:
        reason = "permission denied" if isinstance(exc, PermissionError) else type(exc).__name__
        print(f"    {RED}could not move{NC} {short(path)}: {reason}")
        return False


def ask(prompt: str) -> str:
    """Question read from the terminal itself (works when stdin is a pipe)."""
    try:
        with open("/dev/tty") as tty:
            sys.stdout.write(prompt)
            sys.stdout.flush()
            return tty.readline().strip().lower()
    except OSError:
        return ""


def confirm(prompt: str) -> bool:
    return ask(f"{prompt} (y/N) ") in ("y", "yes", "o", "oui")


def choose_and_trash(paths: list[tuple[Path, int]], indent: str = "    ") -> int:
    """Ask all / each / none, move the chosen items to the Trash, return the bytes moved."""
    if not paths:
        return 0
    choice = ask(f"{indent}-> Move to the Trash: [a]ll {len(paths)} item(s), [e]ach one, [N]one? ")
    moved = 0
    for path, size in paths:
        if choice == "e":
            if not confirm(f"{indent}{short(path)} ({human(size)})?"):
                continue
        elif choice != "a":
            return moved
        if move_to_trash(path):
            moved += size
    return moved
