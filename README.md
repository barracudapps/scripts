# Scripts

Ce dossier contient des scripts utiles pour diverses tâches (fichiers, médias, développement Odoo), écrits pour macOS (Apple Silicon) et testés avec le `/bin/bash` 3.2 et le `python3` 3.9 fournis par macOS.

## Auteurs

- [Pierre LAMOTTE](mailto:pl@barracudapps.com)

## Dépendances

```bash
brew install ghostscript ffmpeg imagemagick jpegoptim optipng pngquant webp xmlstarlet uv
brew install --cask libreoffice   # recursivePdf.sh
```

PostgreSQL (Postgres.app) est nécessaire pour les scripts Odoo qui interrogent une base.

## Liste des Scripts

### Fichiers et documents

#### 1. rmDSStore.sh

- **Description :** Supprime récursivement les fichiers `.DS_Store` (chemins avec espaces gérés). `--dry-run` liste sans supprimer.
- **Utilisation :** `bash ~/Documents/scripts/rmDSStore.sh [dossier] [--dry-run]` (dossier courant par défaut)
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 05 FEB 2024

#### 2. excelTempDir.sh

- **Description :** Ouvre le répertoire temporaire d'Excel dans le Finder.
- **Utilisation :** `bash ~/Documents/scripts/excelTempDir.sh`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 05 FEB 2024

#### 3. recursivePdf.sh

- **Description :** Convertit en PDF (LibreOffice) tous les fichiers `.doc`, `.docx`, `.odt` et `.rtf` d'un dossier et de ses sous-dossiers, puis propose de fusionner les PDF obtenus en un seul.
- **Utilisation :** `bash ~/Documents/scripts/recursivePdf.sh [dossier]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 29 MAY 2024

#### 4. reducePdfSize.sh

- **Description :** Réduit la taille d'un PDF, ou de tous les PDF du dossier courant, avec Ghostscript (5 niveaux de qualité). Les originaux sont déplacés dans `PDF_ORIGINALS_<date>/`, sauf si le fichier réduit n'est pas plus petit (il est alors supprimé et l'original conservé).
- **Utilisation :** `bash ~/Documents/scripts/reducePdfSize.sh [fichier.pdf]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 16 SEPT 2024

#### 5. pdf_ocr.sh

- **Description :** Rend des PDF scannés interrogeables et copiables (couche texte OCR invisible, OCRmyPDF + Tesseract). Les pages qui contiennent déjà du texte sont conservées, les pages sont redressées. Écrit `<nom>-ocr.pdf`, ou remplace les originaux avec `--replace` (sauvegardés dans `PDF_ORIGINALS_<date>/`). OCRmyPDF est lancé via `uvx` s'il n'est pas installé ; pour le français : `brew install tesseract-lang`.
- **Utilisation :** `bash ~/Documents/scripts/pdf_ocr.sh [fichier.pdf ...] [-l fra+eng] [--replace]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 NOV 2026

#### 6. updateEpubMetadata.sh

- **Description :** Met à jour le titre et les auteurs d'EPUB d'après leur nom de fichier `[Auteur(s)] Titre - Sous-titre.epub` (sous-titre facultatif). Écrit une copie `<nom>_updated.epub` à côté de l'original, conforme à la norme EPUB (`mimetype` en premier, non compressé).
- **Utilisation :** `bash ~/Documents/scripts/updateEpubMetadata.sh [fichier.epub ...]` (sans argument : un fichier ou tout le dossier courant)
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 OCT 2024

### Médias

#### 7. convertReduceImg.sh

- **Description :** Convertit (webp, png, jpg) et/ou optimise les images d'un dossier et de ses sous-dossiers. Les fichiers convertis sont écrits à côté de leur source ; l'optimisation sans conversion réécrit le fichier uniquement s'il devient plus petit. Cible de taille en KB ou en % de chaque fichier.
- **Utilisation :** `bash ~/Documents/scripts/convertReduceImg.sh [dossier]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 05 JUL 2024

#### 8. compressVideo.sh

- **Description :** Compresse les vidéos d'un dossier en MP4 : H.264 (compatibilité maximale) ou H.265 matériel (Apple Silicon, plus léger). Redimensionnement (sans agrandissement) et suppression du son en option. Les originaux vont dans `originals/`, sauf si la vidéo compressée n'est pas plus petite.
- **Utilisation :** `bash ~/Documents/scripts/compressVideo.sh [dossier]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 18 SEPT 2024

### Odoo

#### 9. accessOdooFilestore.sh

- **Description :** Localise le filestore d'une base Odoo locale, l'ouvre (Terminal ou Finder) et permet d'ouvrir ou d'exporter les PDF générés (filtre par nom, 50 plus récents par défaut).
- **Utilisation :** `bash ~/Documents/scripts/accessOdooFilestore.sh <db_name>`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 23 JUIN 2025

#### 10. odooTests.sh

- **Description :** Lance les tests Odoo sur plusieurs instances en parallèle (bases et filestores clonés, supprimés à la fin ou sur Ctrl-C). La commande (programme, interpréteur `python` de la venv, arguments, base `-d`) est lue dans la configuration de lancement de `.vscode/settings.json` : « Odoo All Tests » par défaut, sinon « Odoo D-Bug ».
- **Utilisation :** `bash ~/Documents/scripts/odooTests.sh [--threads N] [--loop-until-fail N] [--config NOM] [--verbose]` depuis la racine du projet
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 17 JUIL 2025

#### 11. odooFilter.sh

- **Description :** Génère un domaine Odoo « OU » sur une liste de termes, prêt à coller dans un filtre personnalisé (copié dans le presse-papiers). `-p` entoure chaque terme de parenthèses (codes du type « Nom (ABCD) »).
- **Utilisation :** `bash ~/Documents/scripts/odooFilter.sh [-f champ] [-o opérateur] [-p] terme1 terme2 ...` ou `... < termes.txt` (un terme par ligne). Par défaut : `partner_ids.name` et `ilike`.
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 JAN 2025

#### 12. odoo_translate.py

- **Description :** Synchronise les `.po` d'un module avec son `.pot` (en-tête préservé), puis remplit uniquement les traductions vides depuis un module source. Les modules sont cherchés dans le projet puis dans le `--addons-path` de `.vscode/settings.json` (worktrees centralisés compris) ; une langue régionale (ex. `fr_BE`) complète avec la langue de base (`fr`).
- **Utilisation :** `~/Documents/scripts/odoo_translate.py <module_cible> <module_source>` depuis la racine du projet (exécuté par `uv`, qui installe `polib` automatiquement)
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 04 AOÛT 2025

#### 13. odoo_project_sync.py

- **Description :** Centralise les sources Odoo Community/Enterprise dans `~/Documents/Odoo/versions/` (repos bare dans `_repos/`, un worktree git par couple version+commit, partagé entre tous les projets clients). Lit `.odoo-project.json` à la racine d'un projet client, crée les worktrees manquants sur le commit exact demandé, puis patche uniquement `--addons-path`, `program` et l'interpréteur `.venv` dans `.vscode/settings.json`/`launch.json` (le reste du fichier n'est jamais touché). Enterprise est facultatif. Un template de projet client prêt à copier se trouve dans `~/Documents/Odoo/_templates/client-project/` (avec une tâche VS Code qui lance ce script automatiquement à l'ouverture du dossier via `runOn: folderOpen`).
- **Utilisation :** `python3 ~/Documents/scripts/odoo_project_sync.py [chemin_du_projet]` (par défaut le répertoire courant). Format de `.odoo-project.json` :
  ```json
  {
    "community": { "version": "17.0", "commit": "65ac59feda8e" },
    "enterprise": { "version": "17.0", "commit": "db0415afefdf" }
  }
  ```
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 28 SEPT 2026

#### 14. odoo_new_project.sh

- **Description :** Crée un projet client Odoo à partir du template : `.odoo-project.json` (réutilise par défaut le worktree `<version>@<hash>` le plus récent, sans nouveau checkout ; `--latest` pour le dernier commit), nom de base dans la configuration VS Code, `.ruff.toml`, `user/`, `.gitignore`, worktrees et addons-path (`odoo_project_sync.py`), venv uv avec les dépendances du worktree (psycopg2 compilé contre Postgres.app) et, en option, base initialisée sans données de démo.
- **Utilisation :** `bash ~/Documents/scripts/odoo_new_project.sh <dossier_projet> <version> [--db NOM] [--no-enterprise] [--latest] [--python X.Y] [--init-db] [--lang fr_FR]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 NOV 2026

#### 15. odoo_doctor.py

- **Description :** Diagnostic en lecture seule de l'environnement Odoo (PostgreSQL, Mailpit, wkhtmltopdf, uv, dépôts centraux) et de chaque projet : worktrees du commit demandé, `odoo-bin`, venv (arm64, psycopg2/lxml/Pillow… importables), `--addons-path`, `--http-interface=::`, base présente. Code de sortie 1 en cas d'erreur.
- **Utilisation :** `python3 ~/Documents/scripts/odoo_doctor.py [dossier_projet ...] [--quiet]` (sans argument : tous les projets trouvés)
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 NOV 2026

#### 16. odoo_db.sh

- **Description :** Gère une base Odoo locale avec son filestore : `list` (taille, filestore, version, projet qui l'utilise), `dump` (zip au format Odoo/Odoo.sh : `dump.sql`, `filestore/`, `manifest.json`), `restore` (zip, `.dump` ou `.sql`, **neutralisée par défaut** via `odoo-bin neutralize`), `clone`, `neutralize` et `drop` (détail affiché et nom de la base à retaper pour confirmer).
- **Utilisation :** `bash ~/Documents/scripts/odoo_db.sh list | dump <db> [fichier.zip] | restore <sauvegarde> <db> [--no-neutralize] [--project DIR] | clone <source> <cible> | neutralize <db> [--project DIR] | drop <db>`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 NOV 2026

### Système

#### 17. disk_report.sh

- **Description :** Montre l'espace récupérable : bases Odoo utilisées par aucun projet, filestores orphelins, worktrees `@commit` inutilisés, caches (uv, Homebrew, npm, pip, Xcode), anciennes venvs, Docker. Lecture seule par défaut ; `--clean` supprime élément par élément après confirmation (choix global pour les filestores orphelins, liste affichée avant). `--deep` liste aussi les plus gros dossiers du dossier personnel.
- **Utilisation :** `bash ~/Documents/scripts/disk_report.sh [--clean] [--deep]`
- **Auteur :** Pierre LAMOTTE
- **Date de création :** 02 NOV 2026

### Bibliothèque

- **`lib/odoo_projects.py`** : fonctions partagées par les scripts Odoo (recherche des projets dans `~/Desktop/Indépendant BApps/Clients` et `~/Documents`, lecture des configurations VS Code avec commentaires, bases utilisées). Dossiers scannés modifiables avec `ODOO_PROJECT_ROOTS="dossier1:dossier2"`.

## Notes d'utilisation

- Les scripts utilisent des fonctionnalités de bash : lancez-les avec `bash script.sh` (ou `./script.sh`), pas avec `sh`.
- Assurez-vous d'avoir les droits d'exécution pour les scripts. Sinon, vous pouvez les ajouter avec la commande `chmod +x nom_du_script.sh`.
- Les scripts interactifs acceptent aussi le dossier ou le fichier à traiter en argument, et un `~` saisi au clavier est bien interprété.

N'hésitez pas à contribuer en proposant des améliorations ou en ajoutant de nouveaux scripts !
