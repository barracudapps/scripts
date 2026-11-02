#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["polib"]
# ///

"""
Gestion sûre des traductions Odoo.
Synchronise les clés et les références de code tout en protégeant l'en-tête.

- Étape 1: Synchronise les clés et références via 'merge' mais en restaurant l'en-tête original.
- Étape 2: Remplit UNIQUEMENT les traductions vides depuis un module source
  (une langue régionale, ex. fr_BE, se rabat sur la langue de base, ex. fr).

Les modules sont cherchés dans le projet courant, puis dans les dossiers du
--addons-path de .vscode/settings.json (worktrees Odoo centralisés compris).
Un chemin vers le dossier du module est aussi accepté.

Usage (depuis la racine de votre projet Odoo) :
  ~/Documents/scripts/odoo_translate.py <module_cible> <module_source>
  (uv installe polib automatiquement ; sinon : python3 odoo_translate.py ...)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import polib
except ImportError:
    sys.exit("Le module 'polib' est requis : lancez le script directement (uv run --script) "
             "ou installez polib dans votre venv.")

# --- Configuration des couleurs ---
COLOR_GREEN = '\033[92m'
COLOR_YELLOW = '\033[93m'
COLOR_RED = '\033[91m'
COLOR_BOLD = '\033[1m'
COLOR_NC = '\033[0m'

def log_info(message):
    print(f"{COLOR_BOLD}{message}{COLOR_NC}")

def log_success(message):
    print(f"  -> {COLOR_GREEN}✓{COLOR_NC} {message}")

def log_warn(message):
    print(f"  -> {COLOR_YELLOW}!{COLOR_NC} {message}")

def is_module(path):
    return path.is_dir() and (path / '__manifest__.py').exists()


def addons_paths_from_vscode(root_dir):
    """Dossiers du --addons-path déclarés dans .vscode/settings.json ou launch.json."""
    paths = []
    for name in ('settings.json', 'launch.json'):
        config = root_dir / '.vscode' / name
        if not config.is_file():
            continue
        for match in re.findall(r'"--addons-path=([^"]*)"', config.read_text()):
            for segment in match.split(','):
                segment = segment.strip().replace('${workspaceFolder}', str(root_dir))
                path = Path(segment).expanduser()
                path = path if path.is_absolute() else root_dir / path
                if path.is_dir() and path not in paths:
                    paths.append(path)
    return paths


def find_module_path(root_dir, module_name):
    """Cherche un module : chemin direct, projet courant, puis --addons-path."""
    direct = Path(module_name).expanduser()
    if is_module(direct):
        return direct.resolve()
    candidates = [root_dir / 'addons' / module_name, root_dir / module_name]
    candidates += [subdir / module_name for subdir in sorted(root_dir.iterdir()) if subdir.is_dir()]
    candidates += [path / module_name for path in addons_paths_from_vscode(root_dir)]
    for path in candidates:
        if is_module(path):
            return path
    return None

def update_po_from_pot(target_module_path):
    """
    Étape 1 SÉCURISÉE: Synchronise le contenu mais préserve l'en-tête.
    """
    module_name = target_module_path.name
    i18n_path = target_module_path / 'i18n'
    pot_file_path = i18n_path / f'{module_name}.pot'

    if not pot_file_path.exists():
        print(f"{COLOR_RED}ERREUR: Fichier .pot introuvable : {pot_file_path}{COLOR_NC}", file=sys.stderr)
        return False

    log_info("\n--- Étape 1: Synchronisation avec préservation de l'en-tête ---")
    pot_file = polib.pofile(str(pot_file_path))
    po_files = list(i18n_path.glob('*.po'))

    if not po_files:
        log_warn("Aucun fichier .po trouvé à mettre à jour.")
        return True

    for po_file_path in po_files:
        po_file = polib.pofile(str(po_file_path))

        # CORRECTION: Utilisation de po_file.find('') pour obtenir l'en-tête
        # 1. Sauvegarder l'en-tête original (métadonnées et commentaires)
        original_metadata = po_file.metadata.copy()
        header_entry = po_file.find('')
        original_header_comment = header_entry.comment if header_entry else ""

        # 2. Lancer la synchronisation complète avec merge
        po_file.merge(pot_file)

        # 3. Restaurer l'en-tête original pour écraser les changements de merge
        po_file.metadata = original_metadata
        new_header_entry = po_file.find('')
        if new_header_entry:
            new_header_entry.comment = original_header_comment

        # 4. Trier et sauvegarder
        po_file.sort(key=lambda e: e.msgid.lower())
        po_file.save()
        log_success(f"'{po_file_path.name}' synchronisé et trié (en-tête préservé).")

    return True

def copy_translations(target_module_path, source_module_path):
    """Étape 2: Copie les traductions du source vers le cible (non-destructif)."""
    log_info(f"\n--- Étape 2: Remplissage des traductions vides depuis '{source_module_path.name}' ---")

    source_translations = {}
    source_i18n_path = source_module_path / 'i18n'
    if not source_i18n_path.is_dir():
        log_warn("Dossier 'i18n' introuvable pour le module source, étape ignorée.")
        return

    for source_po_path in source_i18n_path.glob('*.po'):
        lang = source_po_path.stem
        source_po = polib.pofile(str(source_po_path))
        source_translations[lang] = {
            entry.msgid: entry.msgstr for entry in source_po if entry.translated()
        }

    if not source_translations:
        log_warn("Aucune traduction valide trouvée dans le module source.")
        return

    target_i18n_path = target_module_path / 'i18n'
    for target_po_path in target_i18n_path.glob('*.po'):
        lang = target_po_path.stem
        # Langue régionale (ex. fr_BE) : Odoo n'y met que les différences, le reste
        # vient de la langue de base (fr). On cherche donc d'abord fr_BE, puis fr.
        base_lang = lang.split('_')[0]
        lookup = {**source_translations.get(base_lang, {}), **source_translations.get(lang, {})}
        if not lookup:
            continue

        target_po = polib.pofile(str(target_po_path))
        copied_count = 0

        for entry in target_po:
            if not entry.msgstr and entry.msgid in lookup:
                entry.msgstr = lookup[entry.msgid]
                copied_count += 1

        if copied_count > 0:
            target_po.save()
            log_success(f"{copied_count} traduction(s) copiée(s) dans '{target_po_path.name}'.")
        else:
            log_success(f"Aucune traduction à copier pour '{target_po_path.name}'.")

def main():
    parser = argparse.ArgumentParser(
        description="Outil sûr de gestion des traductions pour Odoo. À lancer depuis la racine du projet."
    )
    parser.add_argument("target_module", help="Le nom du module cible à mettre à jour.")
    parser.add_argument("source_module", help="Le nom du module source pour copier les traductions.")
    args = parser.parse_args()

    odoo_root = Path.cwd()
    log_info(f"Racine Odoo détectée : {odoo_root}")

    target_path = find_module_path(odoo_root, args.target_module)
    if not target_path:
        print(f"{COLOR_RED}ERREUR: Module cible '{args.target_module}' introuvable.{COLOR_NC}", file=sys.stderr)
        sys.exit(1)

    source_path = find_module_path(odoo_root, args.source_module)
    if not source_path:
        print(f"{COLOR_RED}ERREUR: Module source '{args.source_module}' introuvable.{COLOR_NC}", file=sys.stderr)
        sys.exit(1)

    log_info(f"Module Cible: {target_path}")
    log_info(f"Module Source: {source_path}")

    if not update_po_from_pot(target_path):
        sys.exit(1)
    copy_translations(target_path, source_path)

    log_info(f"\n{COLOR_GREEN}Opération terminée avec succès.{COLOR_NC}")

if __name__ == "__main__":
    main()
