#!/usr/bin/env python3
################################################################################
# Script:       odoo_doctor.py
# Description:  Health check of the local Odoo environment and of every Odoo
#               project (or of the projects given as arguments): shared
#               worktrees, VS Code launch configuration, virtualenv (arm64,
#               psycopg2/lxml/... importable), addons path, database, and
#               global tools (PostgreSQL, Mailpit, wkhtmltopdf, uv).
#               Read-only: it never modifies anything.
# Usage:        python3 ~/Documents/scripts/odoo_doctor.py [project_dir ...] [--quiet]
#               --quiet only shows warnings and errors.
#               Exit code 1 when at least one error is found.
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import odoo_projects as op  # noqa: E402

GREEN, YELLOW, RED, BOLD, NC = "\033[92m", "\033[93m", "\033[91m", "\033[1m", "\033[0m"
POSTGRES_APP_BIN = Path("/Applications/Postgres.app/Contents/Versions/latest/bin")
VENV_IMPORT_CHECK = (
    "import json, platform, sys\n"
    "result = {'arch': platform.machine(), 'version': sys.version.split()[0], 'missing': []}\n"
    "for mod in ('psycopg2', 'lxml.etree', 'PIL.Image', 'babel', 'werkzeug', 'reportlab', 'cryptography'):\n"
    "    try:\n"
    "        __import__(mod)\n"
    "    except Exception as exc:\n"
    "        result['missing'].append(f'{mod} ({type(exc).__name__})')\n"
    "print(json.dumps(result))\n"
)


class Report:
    def __init__(self, quiet: bool):
        self.quiet = quiet
        self.errors = 0
        self.warnings = 0

    def ok(self, msg: str) -> None:
        if not self.quiet:
            print(f"  {GREEN}✓{NC} {msg}")

    def warn(self, msg: str) -> None:
        self.warnings += 1
        print(f"  {YELLOW}!{NC} {msg}")

    def error(self, msg: str) -> None:
        self.errors += 1
        print(f"  {RED}✗{NC} {msg}")


def run(cmd: list[str], timeout: int = 20) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


def psql_bin() -> str:
    candidate = POSTGRES_APP_BIN / "psql"
    return str(candidate) if candidate.exists() else (shutil.which("psql") or "psql")


def existing_databases() -> set[str] | None:
    result = run([psql_bin(), "-d", "postgres", "-Atc", "SELECT datname FROM pg_database"])
    return set(result.stdout.split()) if result.returncode == 0 else None


def check_global(report: Report) -> set[str] | None:
    print(f"{BOLD}Environnement{NC}")
    dbs = existing_databases()
    if dbs is None:
        report.error("PostgreSQL injoignable (Postgres.app est-il démarré ?)")
    else:
        version = run([psql_bin(), "-d", "postgres", "-Atc", "SHOW server_version"]).stdout.strip()
        report.ok(f"PostgreSQL {version} ({len(dbs)} bases)")

    for tool, hint in (("uv", "brew install uv"), ("git", "brew install git")):
        if shutil.which(tool):
            report.ok(f"{tool} : {shutil.which(tool)}")
        else:
            report.error(f"{tool} introuvable ({hint})")

    wk = shutil.which("wkhtmltopdf")
    if not wk:
        report.error("wkhtmltopdf introuvable : impression PDF impossible")
    else:
        version = run([wk, "--version"]).stdout.strip()
        if "patched qt" in version:
            report.ok(f"{version} ({wk})")
        else:
            report.warn(f"wkhtmltopdf sans Qt patché ({version}) : en-têtes/pieds de page PDF incorrects")

    if not shutil.which("mailpit"):
        report.warn("mailpit introuvable : les mails partiront vers smtp localhost:1025 sans capteur")
    elif run(["pgrep", "-x", "mailpit"]).returncode == 0:
        report.ok("Mailpit lancé (http://127.0.0.1:8025/)")
    else:
        report.warn("Mailpit installé mais pas lancé (lancer `mailpit`)")

    for edition, repo in op.REPOS.items():
        if repo.is_dir():
            report.ok(f"Dépôt central {edition} : {repo}")
        else:
            report.error(f"Dépôt central {edition} absent : {repo}")
    return dbs


def worktree_for(edition: str, version: str, commit: str) -> tuple[Path | None, str]:
    repo = op.REPOS[edition]
    result = run(["git", "-C", str(repo), "rev-parse", "--verify", f"{commit}^{{commit}}"])
    if result.returncode != 0:
        return None, f"commit {commit} inconnu du dépôt {repo.name} (lancer odoo_project_sync.py)"
    full = result.stdout.strip()
    return op.VERSIONS_DIR / edition / f"{version}@{full[:8]}", full


def check_odoo_project_json(project: Path, report: Report) -> None:
    path = project / ".odoo-project.json"
    if not path.is_file():
        return
    try:
        data = json.loads(path.read_text())
    except ValueError as exc:
        report.error(f".odoo-project.json invalide : {exc}")
        return
    for edition in ("community", "enterprise"):
        entry = data.get(edition)
        if not entry:
            continue
        version, commit = entry.get("version", "?"), entry.get("commit", entry.get("version", "?"))
        if "REMPLACER" in str(commit):
            report.error(f"{edition} : commit non renseigné dans .odoo-project.json")
            continue
        worktree, info = worktree_for(edition, version, commit)
        if worktree is None:
            report.error(f"{edition} : {info}")
        elif worktree.is_dir():
            report.ok(f"{edition} {version}@{info[:8]} présent")
        else:
            report.error(f"{edition} {version}@{info[:8]} absent : lancer odoo_project_sync.py")


def check_venv(python: str, report: Report) -> None:
    if not python:
        report.warn('pas de "python" dans la configuration : VS Code peut prendre le mauvais interpréteur')
        return
    py = Path(python)
    if not py.exists():
        report.error(f"interpréteur introuvable : {python} (venv à créer : uv venv --managed-python .venv)")
        return
    result = run([str(py), "-c", VENV_IMPORT_CHECK], timeout=60)
    if result.returncode != 0:
        report.error(f"la venv ne démarre pas : {(result.stderr.strip().splitlines() or ['?'])[-1]}")
        return
    info = json.loads(result.stdout)
    label = f"venv Python {info['version']} {info['arch']}"
    if info["arch"] != "arm64":
        report.warn(f"{label} : pas en arm64 (Rosetta), à recréer avec uv")
    if info["missing"]:
        report.error(f"{label} : imports en échec : {', '.join(info['missing'])}")
    elif info["arch"] == "arm64":
        report.ok(f"{label}, dépendances critiques importables")


def check_config(project: Path, config: dict, dbs: set[str] | None, report: Report) -> None:
    program = Path(config["program"])
    if program.is_file():
        report.ok(f"odoo-bin : {program}")
    else:
        report.error(f"odoo-bin introuvable : {program}")

    check_venv(config["python"], report)

    for path in op.addons_paths(config["args"], project):
        if not path.is_dir():
            level = report.warn if path.parent == project else report.error
            level(f"--addons-path : dossier absent {path}")

    if not any(a.startswith("--http-interface=::") for a in config["args"]):
        report.warn("--http-interface=:: absent : l'impression PDF peut tourner indéfiniment (wkhtmltopdf/IPv6)")

    db = config["database"]
    if not db:
        report.warn("aucune base (-d) dans la configuration")
    elif "REMPLACER" in db:
        report.error("nom de base non renseigné (REMPLACER_PAR_LE_NOM_DB)")
    elif dbs is not None:
        if db in dbs:
            report.ok(f"base « {db} » présente")
        else:
            report.warn(f"base « {db} » absente de PostgreSQL (Docker, ou à créer/restaurer)")


def check_project(project: Path, dbs: set[str] | None, report: Report) -> None:
    print(f"\n{BOLD}{project}{NC}")
    check_odoo_project_json(project, report)
    config = op.config_summary(project)
    if config is None:
        report.warn("aucune configuration de lancement Odoo dans .vscode/")
        return
    report.ok(f"configuration « {config['name']} » ({Path(config['file']).name})")
    check_config(project, config, dbs, report)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if any(a in ("-h", "--help") for a in sys.argv[1:]):
        print("Usage: odoo_doctor.py [project_dir ...] [--quiet]")
        return 0
    report = Report(quiet="--quiet" in sys.argv)
    dbs = check_global(report)
    projects = [Path(a).expanduser().resolve() for a in args] or op.find_projects()
    for project in projects:
        check_project(project, dbs, report)
    color = RED if report.errors else (YELLOW if report.warnings else GREEN)
    print(f"\n{color}{BOLD}{len(projects)} projet(s) : {report.errors} erreur(s), "
          f"{report.warnings} avertissement(s){NC}")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
