#!/usr/bin/env python3
################################################################################
# Script:       startup_items.py
# Description:  Lists everything that starts with the Mac or runs in the
#               background: login items, background apps, launch agents and
#               daemons, with their developer and whether they are enabled.
#               Flags the orphans (left behind by an uninstalled app: their
#               program no longer exists) and the unsigned ones.
#               Sources: macOS background task list (sfltool dumpbtm) and the
#               LaunchAgents / LaunchDaemons folders.
#               Read-only by default. Only the current user's launch agents
#               can be changed (no administrator needed); for the others the
#               commands or the System Settings page are given.
# Usage:        python3 ~/Documents/scripts/startup_items.py [--all]
#               python3 ~/Documents/scripts/startup_items.py --disable LABEL
#               python3 ~/Documents/scripts/startup_items.py --enable LABEL
#               python3 ~/Documents/scripts/startup_items.py --orphans
#               --all       also show Apple items and disabled items
#               --disable   stop a user launch agent and keep it off at login
#               --enable    turn it back on
#               --orphans   move the orphan user launch agents to the Trash
#                           (after confirmation) and print the commands for
#                           the system-wide ones
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

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
    move_to_trash,
    short,
)

UID = os.getuid()
USER_AGENTS = HOME / "Library" / "LaunchAgents"
PLIST_DIRS = [
    (USER_AGENTS, "agent (you)"),
    (Path("/Library/LaunchAgents"), "agent (all users)"),
    (Path("/Library/LaunchDaemons"), "daemon (system)"),
]
SHOWN_TYPES = {"login item": "login item", "app": "background app", "agent": "agent",
               "legacy agent": "agent", "daemon": "daemon", "legacy daemon": "daemon"}
HEADINGS = {"login item": "Login items", "background app": "Background apps", "agent": "Agents (apps)",
            "agent (you)": "Launch agents - yours", "agent (all users)": "Launch agents - all users",
            "daemon": "Daemons (apps)", "daemon (system)": "Daemons - system-wide (admin)"}
SHELLS = ("/bin/", "/usr/bin/", "/usr/sbin/", "/sbin/")
LOGIN_ITEMS_SETTINGS = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"


class Item:
    def __init__(self, name: str, kind: str, developer: str, enabled: bool, program: str,
                 plist: Path | None = None, label: str = ""):
        self.name, self.kind, self.developer, self.enabled = name, kind, developer, enabled
        self.program, self.plist, self.label = program, plist, label

    @property
    def orphan(self) -> bool:
        return bool(self.program) and self.program.startswith("/") and not Path(self.program).exists()

    @property
    def apple(self) -> bool:
        return self.label.startswith("com.apple.") or self.program.startswith(("/System/", "/usr/libexec/"))


def read_btm() -> list[dict[str, str]]:
    """Records of the current user and of the system from 'sfltool dumpbtm'."""
    try:
        out = subprocess.run(["sfltool", "dumpbtm"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    records, current, keep = [], None, False
    for line in out.splitlines():
        header = re.match(r"\s*Records for UID (-?\d+)", line)
        if header:
            keep = int(header.group(1)) in (UID, 0)
            continue
        if re.match(r"\s*#\d+:$", line):
            current = {}
            if keep:
                records.append(current)
            continue
        field = re.match(r"\s*([A-Za-z ]+): (.*)$", line)
        if field and current is not None and keep:
            current.setdefault(field.group(1).strip(), field.group(2).strip())
    return records


def plist_program(data: dict) -> str:
    """The real program: for "/bin/sh script" style entries, the script itself."""
    arguments = [str(a) for a in data.get("ProgramArguments") or []]
    program = str(data.get("Program") or (arguments[0] if arguments else ""))
    if program.startswith(SHELLS):
        paths = [unquote(a[7:]) if a.startswith("file://") else a for a in arguments[1:]]
        program = next((a.rstrip("/") for a in paths if a.startswith("/")), program)
    return program


def signer(program: str) -> str:
    if not program or not Path(program).exists():
        return ""
    out = subprocess.run(["codesign", "-dvv", program], capture_output=True, text=True).stderr
    match = re.search(r"Authority=(?:Developer ID Application: |Apple Development: )?(.+)", out)
    if "Signature=adhoc" in out or "not signed" in out:
        return "unsigned"
    return match.group(1).strip() if match else ""


def collect() -> list[Item]:
    items: dict[str, Item] = {}
    disabled_out = subprocess.run(["launchctl", "print-disabled", f"gui/{UID}"],
                                  capture_output=True, text=True).stdout
    disabled = set(re.findall(r'"([^"]+)" => (?:disabled|true)', disabled_out))
    for folder, kind in PLIST_DIRS:
        for plist in sorted(folder.glob("*.plist")) if folder.is_dir() else []:
            try:
                with plist.open("rb") as handle:
                    data = plistlib.load(handle)
            except (OSError, plistlib.InvalidFileException, ValueError):
                continue
            label = str(data.get("Label", plist.stem))
            enabled = not data.get("Disabled", False) and label not in disabled
            items[str(plist)] = Item(label, kind, "", enabled, plist_program(data), plist, label)

    for record in read_btm():
        kind = SHOWN_TYPES.get(re.sub(r"\s*\(0x[0-9a-f]+\)", "", record.get("Type", "")))
        if not kind:
            continue
        url = record.get("URL", "")
        developer = record.get("Developer Name", "")
        developer = "" if developer == "(null)" else developer
        enabled = "enabled" in record.get("Disposition", "") and "disabled" not in record.get("Disposition", "")
        if url in items:                      # same launchd plist: complete it
            items[url].developer = items[url].developer or developer
            items[url].enabled = items[url].enabled and enabled
            continue
        if kind in ("agent", "daemon") and url.startswith("/"):
            continue                          # plist already listed or gone with its folder
        program = record.get("Executable Path", "") or (url if url.startswith("/") else "")
        program = re.sub(rf"^/Users/{UID}/", f"{HOME}/", program)    # the list uses the uid as home
        name = record.get("Name", "") if record.get("Name") != "(null)" else record.get("Identifier", "")
        items[record.get("UUID", name)] = Item(name, kind, developer, enabled, program,
                                               label=record.get("Bundle Identifier", ""))
    return sorted(items.values(), key=lambda i: (not i.orphan, i.kind, i.name.lower()))


def set_agent(label: str, enable: bool) -> int:
    plist = next((p for p in USER_AGENTS.glob("*.plist") if label in (p.stem, read_label(p))), None)
    if not plist:
        print(f"'{label}' is not one of your launch agents ({short(USER_AGENTS)}).")
        print("Login items and background apps: System Settings > General > Login Items & Extensions")
        print(f"System-wide agents and daemons need an administrator:\n"
              f"  sudo launchctl {'enable' if enable else 'disable'} system/{label}")
        print(f"  open '{LOGIN_ITEMS_SETTINGS}'")
        return 1
    real = read_label(plist) or label
    if enable:
        subprocess.run(["launchctl", "enable", f"gui/{UID}/{real}"])
        subprocess.run(["launchctl", "bootstrap", f"gui/{UID}", str(plist)], capture_output=True)
        print(f"{GREEN}Enabled{NC} {real}")
    else:
        subprocess.run(["launchctl", "bootout", f"gui/{UID}/{real}"], capture_output=True)
        subprocess.run(["launchctl", "disable", f"gui/{UID}/{real}"])
        print(f"{GREEN}Disabled{NC} {real} (stopped now, and will not start at login). "
              f"Undo with --enable {real}")
    return 0


def read_label(plist: Path) -> str:
    try:
        with plist.open("rb") as handle:
            return str(plistlib.load(handle).get("Label", ""))
    except (OSError, plistlib.InvalidFileException, ValueError):
        return ""


def clean_orphans(items: list[Item]) -> int:
    orphans = [i for i in items if i.orphan]
    if not orphans:
        print(f"{GREEN}No orphan found.{NC}")
        return 0
    for item in orphans:
        where = short(item.plist) if item.plist else item.kind
        print(f"  {RED}orphan{NC} {item.name}  {DIM}{where} -> missing {item.program}{NC}")
    mine = [i for i in orphans if i.plist and i.plist.parent == USER_AGENTS]
    others = [i for i in orphans if i not in mine]
    if mine and confirm(f"\nMove your {len(mine)} orphan launch agent(s) to the Trash?"):
        for item in mine:
            subprocess.run(["launchctl", "bootout", f"gui/{UID}", str(item.plist)], capture_output=True)
            if move_to_trash(item.plist):
                print(f"  moved {short(item.plist)}")
    system = [i for i in others if i.plist]
    if system:
        print(f"\n{YELLOW}System-wide orphans{NC} (administrator needed, review then run yourself):")
        for item in system:
            domain = "system" if item.plist.parent.name == "LaunchDaemons" else f"gui/{UID}"
            print(f"  sudo launchctl bootout {domain} '{item.plist}'; sudo mv '{item.plist}' ~/.Trash/")
    if any(not i.plist for i in others):
        print("\nOther orphans are login items: remove them in System Settings > General > Login Items.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="What starts with the Mac or runs in the background.")
    parser.add_argument("--all", action="store_true", help="also Apple and disabled items")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--disable", metavar="LABEL")
    group.add_argument("--enable", metavar="LABEL")
    group.add_argument("--orphans", action="store_true")
    args = parser.parse_args()
    if args.disable or args.enable:
        return set_agent(args.disable or args.enable, enable=bool(args.enable))

    items = collect()
    if args.orphans:
        return clean_orphans(items)
    shown = [i for i in items if args.all or (i.enabled and not i.apple) or i.orphan]
    current_kind = None
    for item in sorted(shown, key=lambda i: (i.kind, not i.orphan, i.name.lower())):
        if item.kind != current_kind:
            current_kind = item.kind
            print(f"\n{BOLD}{HEADINGS.get(item.kind, item.kind)}{NC}")
        developer = item.developer or signer(item.program)
        state = f"{RED}orphan: program missing{NC}" if item.orphan else (
            f"{YELLOW}unsigned{NC}" if developer == "unsigned" else "")
        on = f"{GREEN}on {NC}" if item.enabled else f"{DIM}off{NC}"
        details = f"{DIM}{developer if developer not in ('', 'unsigned') else 'unknown developer'}{NC}"
        label = f" {DIM}[{item.label}]{NC}" if item.label and item.label != item.name else ""
        print(f"  {on} {item.name}{label}  {details} {state}")
    orphans = sum(1 for i in items if i.orphan)
    hidden = len(items) - len(shown)
    print(f"\n{len(shown)} item(s) shown" + (f", {hidden} hidden (Apple or off: --all)" if hidden else "")
          + (f", {RED}{orphans} orphan(s){NC}: clean with --orphans" if orphans else "") + ".")
    print(f"{DIM}Stop one of yours: --disable LABEL. Login items: System Settings > General > "
          f"Login Items & Extensions.{NC}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
