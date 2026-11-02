#!/usr/bin/env python3
################################################################################
# Script:       odoo_project_sync.py
# Description:  Lit un fichier .odoo-project.json a la racine d'un projet
#               client Odoo, garantit que les worktrees Community/Enterprise
#               correspondant au commit demande existent (les cree sinon a
#               partir des repos centralises), puis met a jour les chemins
#               --addons-path dans .vscode/settings.json (et launch.json s'il
#               existe) sans toucher au reste de la configuration.
# Usage:        python3 odoo_project_sync.py [chemin_du_projet]
#               (par defaut: repertoire courant). Compatible Python 3.9+
#               (le python3 de macOS), bibliotheque standard uniquement.
# Auteur:       Pierre LAMOTTE
# Date:         28 SEPT 2026
################################################################################

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ODOO_ROOT = Path.home() / "Documents" / "Odoo"
REPOS = {
    "community": ODOO_ROOT / "_repos" / "odoo.git",
    "enterprise": ODOO_ROOT / "_repos" / "enterprise.git",
}
VERSIONS_DIR = ODOO_ROOT / "versions"
CONFIG_FILENAME = ".odoo-project.json"
SHORT_HASH_LEN = 8


def eprint(*args):
    print(*args, file=sys.stderr)


def find_config(start: Path) -> Path | None:
    """Cherche .odoo-project.json dans start puis ses parents (jusqu'a la racine)."""
    current = start.resolve()
    for candidate in [current, *current.parents]:
        config_path = candidate / CONFIG_FILENAME
        if config_path.is_file():
            return config_path
    return None


def run_git(repo: Path, *args, check=True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=check,
    )


def resolve_commit(repo: Path, commit_ref: str) -> str:
    """Resout commit_ref (hash complet/court, ou branche) en hash complet.
    Tente un fetch si la reference est introuvable localement."""
    result = run_git(repo, "rev-parse", "--verify", f"{commit_ref}^{{commit}}", check=False)
    if result.returncode == 0:
        return result.stdout.strip()

    eprint(f"  Commit {commit_ref} introuvable localement, fetch de {repo.name}...")
    # "origin" (github.com/odoo/*) est le remote public complet ; "dev" (odoo-dev,
    # acces SSH restreint) peut echouer selon la machine, on ne le bloque pas dessus.
    run_git(repo, "fetch", "origin", "--tags", check=False)

    result = run_git(repo, "rev-parse", "--verify", f"{commit_ref}^{{commit}}", check=False)
    if result.returncode != 0:
        raise SystemExit(f"Impossible de resoudre le commit '{commit_ref}' dans {repo}")
    return result.stdout.strip()


def verify_commit_on_branch(repo: Path, version: str, full_hash: str) -> None:
    """Verifie que full_hash appartient bien a la branche `version` (garde-fou
    contre un mauvais hash copie/colle dans .odoo-project.json)."""
    result = run_git(repo, "merge-base", "--is-ancestor", full_hash, f"origin/{version}", check=False)
    if result.returncode == 0:
        return
    result = run_git(repo, "merge-base", "--is-ancestor", full_hash, version, check=False)
    if result.returncode == 0:
        return
    eprint(
        f"  [ATTENTION] le commit {full_hash[:SHORT_HASH_LEN]} ne semble pas appartenir "
        f"a la branche {version} de {repo.name} (verifie .odoo-project.json)"
    )


def worktree_path(edition: str, version: str, full_hash: str) -> Path:
    short_hash = full_hash[:SHORT_HASH_LEN]
    return VERSIONS_DIR / edition / f"{version}@{short_hash}"


def existing_worktrees(repo: Path) -> dict[str, str]:
    """Retourne {chemin_absolu: hash_complet} pour tous les worktrees du repo."""
    result = run_git(repo, "worktree", "list", "--porcelain")
    trees: dict[str, str] = {}
    current_path = None
    for line in result.stdout.splitlines():
        if line.startswith("worktree "):
            current_path = line.removeprefix("worktree ")
        elif line.startswith("HEAD ") and current_path:
            trees[current_path] = line.removeprefix("HEAD ")
            current_path = None
    return trees


def ensure_worktree(edition: str, version: str, commit_ref: str) -> Path:
    repo = REPOS[edition]
    if not repo.is_dir():
        raise SystemExit(f"Repo centralise introuvable: {repo}")

    full_hash = resolve_commit(repo, commit_ref)
    verify_commit_on_branch(repo, version, full_hash)
    target = worktree_path(edition, version, full_hash)

    trees = existing_worktrees(repo)
    if str(target) in trees:
        print(f"  [ok] {edition} {version}@{full_hash[:SHORT_HASH_LEN]} deja pret ({target})")
        return target

    if target.exists():
        raise SystemExit(f"Le dossier {target} existe mais n'est pas un worktree connu de {repo}")

    print(f"  [creation] worktree {edition} {version}@{full_hash[:SHORT_HASH_LEN]} -> {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    run_git(
        repo,
        "worktree", "add", "--detach", str(target), full_hash,
    )
    return target


ADDONS_PATH_RE = re.compile(r'("--addons-path=)([^"]*)(")')
ODOO_BIN_PROGRAM_RE = re.compile(r'("program":\s*")([^"]*odoo-bin)(")')


def patch_addons_path(text: str, community_path: Path, enterprise_path: Path | None) -> tuple[str, int]:
    """Remplace, dans chaque occurrence de --addons-path=..., les segments qui
    pointent vers un ancien worktree community/enterprise par les nouveaux
    chemins absolus, en preservant tous les autres segments (addons custom du
    client) tels quels."""

    count = 0

    def replace(match: re.Match) -> str:
        nonlocal count
        prefix, paths_str, suffix = match.groups()
        segments = paths_str.split(",")
        new_segments = []
        for seg in segments:
            seg_stripped = seg.strip()
            lower = seg_stripped.lower()
            enterprise_prefix = f"{VERSIONS_DIR}/enterprise/"
            if seg_stripped.startswith(enterprise_prefix):
                # deja resolu vers un worktree enterprise centralise : corrige un
                # eventuel /addons final erronement ajoute par un run precedent
                new_segments.append(seg_stripped.removesuffix("/addons"))
            elif seg_stripped.startswith(str(VERSIONS_DIR)):
                # deja resolu vers un worktree community centralise
                new_segments.append(seg_stripped)
            elif enterprise_path and (
                "odoo-enterprise" in lower or lower.endswith("enterprise") or "/enterprise" in lower
            ):
                # le repo enterprise n'a pas de sous-dossier addons/ : les modules
                # sont directement a la racine du worktree
                new_segments.append(str(enterprise_path))
            elif lower.endswith("odoo/odoo/addons"):
                # ex: "odoo/odoo/addons" -> coeur Odoo (paquet python "odoo")
                new_segments.append(f"{community_path}/odoo/addons")
            elif lower.endswith("odoo/addons") or seg_stripped == "addons":
                # ex: "odoo/addons" ou "addons" -> addons officiels du worktree
                new_segments.append(f"{community_path}/addons")
            else:
                new_segments.append(seg_stripped)
        count += 1
        return f"{prefix}{','.join(new_segments)}{suffix}"

    new_text = ADDONS_PATH_RE.sub(replace, text)
    return new_text, count


def patch_odoo_bin_program(text: str, community_path: Path) -> tuple[str, int]:
    """Remplace "program": ".../odoo-bin" par le chemin absolu du worktree
    community, pour que le debugger VS Code retrouve l'executable une fois
    l'ancien dossier local (souvent nomme odoo/) supprime."""
    count = 0

    def replace(match: re.Match) -> str:
        nonlocal count
        prefix, _old_path, suffix = match.groups()
        count += 1
        return f"{prefix}{community_path}/odoo-bin{suffix}"

    new_text = ODOO_BIN_PROGRAM_RE.sub(replace, text)
    return new_text, count


DEBUGPY_LAUNCH_RE = re.compile(r'("type":\s*"debugpy",\s*\n(\s*)"request":\s*"launch",\n)')


def ensure_venv_interpreter(text: str) -> tuple[str, int]:
    """Force VS Code a utiliser .venv/bin/python3 pour chaque config debugpy,
    plutot que de compter sur une selection manuelle d'interpreteur (invisible
    dans les fichiers, perdue sur une nouvelle machine ou apres un reset de
    VS Code). N'ajoute rien si "python" est deja present quelque part dans le
    fichier (evite les doublons sur un re-run)."""
    if '"python":' in text:
        return text, 0

    count = 0

    def replace(match: re.Match) -> str:
        nonlocal count
        header, indent = match.groups()
        count += 1
        return f'{header}{indent}"python": "${{workspaceFolder}}/.venv/bin/python3",\n'

    new_text = DEBUGPY_LAUNCH_RE.sub(replace, text)
    return new_text, count


def patch_vscode_configs(project_dir: Path, community_path: Path, enterprise_path: Path | None) -> None:
    vscode_dir = project_dir / ".vscode"
    if not vscode_dir.is_dir():
        print("  Pas de dossier .vscode, rien a patcher.")
        return

    for filename in ("settings.json", "launch.json"):
        file_path = vscode_dir / filename
        if not file_path.is_file():
            continue
        original = file_path.read_text()
        patched, addons_count = patch_addons_path(original, community_path, enterprise_path)
        patched, program_count = patch_odoo_bin_program(patched, community_path)
        patched, interpreter_count = ensure_venv_interpreter(patched)

        if addons_count == 0 and program_count == 0 and interpreter_count == 0:
            print(f"  [info] aucun --addons-path ni odoo-bin trouve dans {filename}")
            continue
        if patched != original:
            file_path.write_text(patched)
            print(
                f"  [patch] {filename}: {addons_count} addons-path, "
                f"{program_count} programme(s) odoo-bin, "
                f"{interpreter_count} interpreteur(s) .venv mis a jour"
            )
        else:
            print(f"  [ok] {filename}: deja a jour")


def load_config(config_path: Path) -> dict:
    try:
        return json.loads(config_path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{config_path} n'est pas un JSON valide: {exc}") from None


def main() -> None:
    start = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    config_path = find_config(start)
    if config_path is None:
        eprint(f"Pas de {CONFIG_FILENAME} trouve dans {start} ni ses parents, rien a faire.")
        sys.exit(0)

    project_dir = config_path.parent
    print(f"Projet: {project_dir}")
    config = load_config(config_path)

    paths: dict[str, Path] = {}
    for edition in ("community", "enterprise"):
        entry = config.get(edition)
        if not entry:
            continue
        version = entry["version"]
        commit_ref = entry.get("commit", version)
        paths[edition] = ensure_worktree(edition, version, commit_ref)

    if "community" not in paths:
        eprint("Configuration incomplete: il faut au moins 'community' dans .odoo-project.json")
        sys.exit(1)
    if "enterprise" not in paths:
        print("  [info] pas d'entree 'enterprise' : projet Community seul")

    patch_vscode_configs(project_dir, paths["community"], paths.get("enterprise"))
    print("Termine.")


if __name__ == "__main__":
    main()
