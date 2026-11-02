#!/usr/bin/env python3
################################################################################
# Script:       lib/odoo_projects.py
# Description:  Shared helpers for the Odoo scripts: find local Odoo projects,
#               read their VS Code launch configurations (JSON with comments)
#               and list the databases they use. Python 3.9+, stdlib only.
# Usage:        python3 lib/odoo_projects.py projects    -> one project per line
#               python3 lib/odoo_projects.py dbs         -> "db<TAB>project" lines
#               python3 lib/odoo_projects.py config DIR [NAME]
#                   -> JSON {name, program, python, args, database} of a launch
#                      configuration ("Odoo D-Bug" by default)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ODOO_ROOT = Path.home() / "Documents" / "Odoo"
VERSIONS_DIR = ODOO_ROOT / "versions"
REPOS = {
    "community": ODOO_ROOT / "_repos" / "odoo.git",
    "enterprise": ODOO_ROOT / "_repos" / "enterprise.git",
}
# Folders scanned for projects (override with ODOO_PROJECT_ROOTS="dir1:dir2")
DEFAULT_ROOTS = [
    Path.home() / "Desktop" / "Indépendant BApps" / "Clients",
    Path.home() / "Documents",
]
SKIP_DIRS = {".git", ".venv", "node_modules", "__pycache__", "versions", "_repos", "_templates", "filestore", "Library"}
MAX_DEPTH = 6


def project_roots() -> list[Path]:
    env = os.environ.get("ODOO_PROJECT_ROOTS")
    roots = [Path(p).expanduser() for p in env.split(":")] if env else DEFAULT_ROOTS
    return [r for r in roots if r.is_dir()]


def load_jsonc(path: Path):
    """Parse a VS Code JSON file: // and /* */ comments, trailing commas."""
    text = path.read_text()
    out, i, in_str = [], 0, False
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end == -1 else end + 2
            continue
        else:
            out.append(c)
        i += 1
    return json.loads(re.sub(r",(\s*[\]}])", r"\1", "".join(out)))


def launch_configurations(project: Path) -> list[dict]:
    """Odoo launch configurations (those running an odoo-bin) of a project."""
    configs = []
    for name in ("settings.json", "launch.json"):
        path = project / ".vscode" / name
        if not path.is_file():
            continue
        try:
            data = load_jsonc(path)
        except (ValueError, OSError):
            continue
        launch = data.get("launch", {}) if name == "settings.json" else data
        for config in launch.get("configurations", []) if isinstance(launch, dict) else []:
            if "odoo-bin" in str(config.get("program", "")):
                config = dict(config, _file=str(path))
                configs.append(config)
    return configs


def expand(value: str, project: Path) -> str:
    return value.replace("${workspaceFolder}", str(project))


def database_of(args: list[str]) -> str | None:
    for i, arg in enumerate(args):
        if arg in ("-d", "--database") and i + 1 < len(args):
            return args[i + 1]
        if arg.startswith("--database="):
            return arg.split("=", 1)[1]
        if arg.startswith("-d") and len(arg) > 2 and not arg.startswith("--"):
            return arg[2:]
    return None


def addons_paths(args: list[str], project: Path) -> list[Path]:
    paths = []
    for arg in args:
        if arg.startswith("--addons-path="):
            for seg in arg.split("=", 1)[1].split(","):
                seg = expand(seg.strip(), project)
                if seg:
                    p = Path(seg).expanduser()
                    paths.append(p if p.is_absolute() else project / p)
    return paths


def find_projects() -> list[Path]:
    """Projects = folders with a .odoo-project.json, or with a .vscode config
    running odoo-bin (e.g. Docker-based projects, tutorials)."""
    found: set[Path] = set()
    for root in project_roots():
        base_depth = len(root.parts)
        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            depth = len(current.parts) - base_depth
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and (not d.startswith(".") or d == ".vscode")]
            if depth >= MAX_DEPTH:
                dirnames[:] = []
            if ".odoo-project.json" in filenames:
                found.add(current)
            elif current.name == ".vscode" and launch_configurations(current.parent):
                found.add(current.parent)
    # Shared Odoo worktrees used directly as a project (e.g. community/19.0)
    for worktree in sorted(VERSIONS_DIR.glob("*/*")):
        if launch_configurations(worktree):
            found.add(worktree)
    return sorted(found)


def config_summary(project: Path, name: str | None = None) -> dict | None:
    configs = launch_configurations(project)
    if not configs:
        return None
    by_name = {c.get("name"): c for c in configs}
    config = by_name.get(name) if name else by_name.get("Odoo D-Bug", configs[0])
    if config is None:
        return None
    args = [expand(str(a), project) for a in config.get("args", [])]
    return {
        "name": config.get("name"),
        "file": config["_file"],
        "program": expand(str(config.get("program", "")), project),
        "python": expand(str(config.get("python", "")), project),
        "args": args,
        "database": database_of(args),
    }


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ("projects", "dbs", "config"):
        print(__doc__ or "usage: odoo_projects.py projects|dbs|config DIR [NAME]", file=sys.stderr)
        return 2
    if argv[0] == "projects":
        for project in find_projects():
            print(project)
    elif argv[0] == "dbs":
        seen = set()
        for project in find_projects():
            for config in launch_configurations(project):
                db = database_of([str(a) for a in config.get("args", [])])
                if db and (db, project) not in seen:
                    seen.add((db, project))
                    print(f"{db}\t{project}")
    else:
        if len(argv) < 2:
            return 2
        summary = config_summary(Path(argv[1]).resolve(), argv[2] if len(argv) > 2 else None)
        if summary is None:
            print("No Odoo launch configuration found", file=sys.stderr)
            return 1
        print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
