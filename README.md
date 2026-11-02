<div align="center">

# 🧰 Scripts

**Petits outils du quotidien pour garder un Mac en forme, protéger ses documents et développer sur Odoo.**

*Une commande, un problème réglé. Rien n'est supprimé sans ton accord.*

![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-000000?logo=apple&logoColor=white)
![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/python-3.9%2B-3776AB?logo=python&logoColor=white)
![uv](https://img.shields.io/badge/uv-managed-DE5FE9?logo=astral&logoColor=white)
![Odoo](https://img.shields.io/badge/Odoo-16%20→%2020-714B67?logo=odoo&logoColor=white)
![Scripts](https://img.shields.io/badge/scripts-36-orange)
![Corbeille](https://img.shields.io/badge/suppression-via%20la%20Corbeille-brightgreen)

[🩺 Quel est ton souci ?](#-quel-est-ton-souci-) · [🔎 Je veux…](#-je-veux) · [🚀 Démarrage](#-démarrage-rapide) · [🏠 Mac au quotidien](#-mac-au-quotidien) · [🛡️ Vie privée](#%EF%B8%8F-vie-privée-et-documents-sensibles) · [📄 Documents](#-documents-et-médias) · [🟣 Odoo](#-odoo) · [⚙️ Système](#%EF%B8%8F-système-et-productivité)

</div>

---

## 🩺 Quel est ton souci ?

Suis la flèche qui te ressemble :

```mermaid
flowchart LR
    Q{{😩 Mon Mac…}}
    Q -->|est plein| P1[forgotten_files.py<br/>duplicates.py<br/>app_uninstall.py]
    Q -->|rame au démarrage| P2[startup_items.py]
    Q -->|va-t-il bien ?| P3[mac_health.sh]
    Q -->|Internet rame| P4[net_check.sh]
    D{{📤 Je dois envoyer…}}
    D -->|ma carte d'identité| D1[id_watermark.py]
    D -->|des photos, un PDF, un .docx| D2[strip_metadata.py]
    F{{🖼️ Mes photos…}}
    F -->|sont en vrac| F1[photo_rename.py]
    F -->|sont en double| P1
```

> [!TIP]
> **Le rituel du dimanche (5 minutes)** — chaque case est une commande :
> - [ ] `mac_health.sh` : le bulletin de santé, avec une note sur 100
> - [ ] `forgotten_files.py --clean` : les vieux fichiers oubliés partent à la Corbeille
> - [ ] `duplicates.py --clean` : les doublons aussi
> - [ ] `startup_items.py` : rien de louche ne se lance au démarrage ?
> - [ ] vider la Corbeille 🗑️ … et profiter de la place retrouvée

## 🔎 Je veux…

<details open>
<summary><b>🏠 Au quotidien, pour tout le monde</b></summary>

| Je veux… | Script | Exemple |
|---|---|---|
| savoir si mon Mac va bien (batterie, sauvegarde, sécurité…) | [`mac_health.sh`](#mac_healthsh) | `mac_health.sh` |
| comprendre pourquoi Internet rame | [`net_check.sh`](#net_checksh) | `net_check.sh` |
| retrouver les vieux fichiers oubliés | [`forgotten_files.py`](#forgotten_filespy) | `forgotten_files.py --clean` |
| supprimer les fichiers en double | [`duplicates.py`](#duplicatespy) | `duplicates.py ~/Pictures --clean` |
| désinstaller une app **et ses restes** | [`app_uninstall.py`](#app_uninstallpy) | `app_uninstall.py Zoom` |
| voir ce qui se lance au démarrage | [`startup_items.py`](#startup_itemspy) | `startup_items.py --orphans` |
| ranger mes photos par date | [`photo_rename.py`](#photo_renamepy) | `photo_rename.py ~/Pictures/Vacances --by-month` |
| envoyer une pièce d'identité sans risque | [`id_watermark.py`](#id_watermarkpy) | `id_watermark.py cni.heic --to "Agence Dupont"` |
| retirer la position GPS d'une photo avant de la partager | [`strip_metadata.py`](#strip_metadatapy) | `strip_metadata.py photo.heic` |
| fusionner, découper, faire pivoter des PDF | [`pdf_tools.py`](#pdf_toolspy) | `pdf_tools.py extract contrat.pdf 1-3,7` |
| rendre un scan interrogeable | [`pdf_ocr.sh`](#pdf_ocrsh) / [`pdf_tools.py scan`](#pdf_toolspy) | `pdf_tools.py scan facture.pdf` |
| alléger des PDF, des images, des vidéos | [`reducePdfSize.sh`](#reducepdfsizesh) · [`convertReduceImg.sh`](#convertreduceimgsh) · [`compressVideo.sh`](#compressvideosh) | `reducePdfSize.sh devis.pdf` |

</details>

<details>
<summary><b>🟣 Pour développer sur Odoo</b></summary>

| Je veux… | Script | Exemple |
|---|---|---|
| démarrer un nouveau projet client Odoo | [`odoo_new_project.sh`](#odoo_new_projectsh) | `odoo_new_project.sh ~/…/Acme/ERP/Odoo 19.0 --init-db --lang fr_FR` |
| lancer Odoo, mettre à jour un module, tester | [`odoo_run.sh`](#odoo_runsh) | `odoo_run.sh --test my_module` |
| créer un module propre | [`odoo_module_new.sh`](#odoo_module_newsh) | `odoo_module_new.sh acme_fleet --model acme.vehicle --views` |
| mettre à jour les traductions d'un module | [`odoo_i18n.sh`](#odoo_i18nsh) | `odoo_i18n.sh acme_fleet -l fr,nl --source fleet` |
| vérifier que tout l'environnement Odoo va bien | [`odoo_doctor.py`](#odoo_doctorpy) | `odoo_doctor.py --quiet` |
| sauvegarder / restaurer / cloner une base | [`odoo_db.sh`](#odoo_dbsh) | `odoo_db.sh restore prod.zip acme-copy` |
| partager une base sans données personnelles | [`odoo_anonymize.sh`](#odoo_anonymizesh) | `odoo_anonymize.sh acme-prod` |
| montrer Odoo à un prospect | [`odoo_demo_share.sh`](#odoo_demo_sharesh) | `odoo_demo_share.sh` |
| lancer les tests sur plusieurs bases en parallèle | [`odooTests.sh`](#odootestssh) | `odooTests.sh --threads 4` |

</details>

<details>
<summary><b>⚙️ Pour le développeur organisé</b></summary>

| Je veux… | Script | Exemple |
|---|---|---|
| savoir combien de temps j'ai passé par client | [`timesheet_git.sh`](#timesheet_gitsh) | `timesheet_git.sh --since 2026-10-01` |
| ne rien oublier de commiter ce soir | [`git_status_all.sh`](#git_status_allsh) | `git_status_all.sh --fetch` |
| libérer de la place (caches de dev, bases Odoo) | [`disk_report.sh`](#disk_reportsh) | `disk_report.sh --clean` |
| un contrôle automatique chaque lundi | [`maintenance.sh`](#maintenancesh) | `maintenance.sh --install 09:00` |
| demander à toutes mes sessions Claude de sauver leur contexte | [`claude_sessions.sh`](#claude_sessionssh) | `claude_sessions.sh save --compact --wait` |

</details>

## 🚀 Démarrage rapide

```bash
# Outils utilisés par les scripts
brew install uv exiftool ghostscript ffmpeg imagemagick jpegoptim optipng pngquant webp xmlstarlet tesseract tesseract-lang ngrok
brew install --cask libreoffice postgres-app

# Facultatif : appeler les scripts sans chemin (ajouter à ~/.bash_profile)
export PATH="$HOME/Documents/scripts:$PATH"
```

Tous les scripts affichent leur aide avec `-h` (ou `--help`). Ceux qui posent des questions acceptent aussi le fichier ou le dossier en argument.

---

> [!IMPORTANT]
> **La promesse** : les scripts « grand public » ne font **rien** sans `--clean` / `--apply` ou sans ta confirmation. Ce qui part va **dans la Corbeille** (récupérable), les originaux de documents ne sont jamais modifiés, et les dossiers clients, iCloud, Dropbox et Google Drive sont protégés.

---

## 🏠 Mac au quotidien

<details id="mac_healthsh">
<summary><b><code>mac_health.sh</code></b> — 🩺 le bulletin de santé du Mac, noté sur 100</summary>

Batterie (cycles, capacité restante), sauvegarde Time Machine (moins de 7 jours ?), espace disque et état SMART, FileVault, pare-feu, SIP, Gatekeeper, mises à jour de sécurité automatiques, mises à jour macOS en attente, dernier redémarrage, pression mémoire. Lecture seule, sans mot de passe administrateur ; chaque point à corriger vient avec **la marche à suivre**.

```text
🔋 Battery
  ✅ Maximum capacity 89% (303 cycles)
💾 Backup
  ❌ No Time Machine backup configured → plug an external disk and enable it in System Settings > …
🔒 Security
  ✅ FileVault on (disk encrypted)

Score: 76/100  🟡 Good, a few things to do  (10/13 checks passed)
```

```bash
mac_health.sh            # bilan complet (~20 s avec les mises à jour)
mac_health.sh --quick    # sans la vérification des mises à jour
```

Intégré à [`maintenance.sh`](#maintenancesh) : les problèmes remontent dans la notification du lundi.
</details>

<details id="net_checksh">
<summary><b><code>net_check.sh</code></b> — 📶 « Internet rame : c'est le Wi-Fi, la box ou le Mac ? »</summary>

Teste chaque maillon dans l'ordre (signal Wi-Fi et bande 2,4/5 GHz → box → Internet par IP → DNS → accès web et portail captif d'hôtel ou de gare → débit et réactivité avec `networkQuality`, intégré à macOS), puis rend **un verdict en une phrase** : redémarrer la box, se rapprocher, changer de DNS, appeler le fournisseur… Ne modifie rien.

```text
4. Name resolution (DNS)
  ❌ The DNS server 192.168.1.1 does not answer, a public one does
Verdict
  ➜ Internet works but names (websites) are not resolved: restart the box, or set the DNS to 1.1.1.1 …
```

```bash
net_check.sh             # ~35 s avec le test de débit
net_check.sh --quick     # sans le test de débit
```
</details>

<details id="forgotten_filespy">
<summary><b><code>forgotten_files.py</code></b> — 🕸️ vieux fichiers oubliés et non essentiels</summary>

Téléchargements anciens, installeurs (`.dmg`, `.pkg`, `.iso`…), gros fichiers jamais rouverts, dossiers régénérables de projets inactifs (`node_modules`, `.venv`, `build`…), vieilles captures d'écran, symboles de débogage iOS et sauvegardes d'iPhone, vieux journaux, Corbeille, applications non ouvertes depuis un an. L'âge correspond à la **dernière ouverture** connue de Spotlight.

Lecture seule par défaut ; `--clean` affiche la liste détaillée de chaque catégorie puis propose tout / un par un / rien, et **déplace dans la Corbeille**. Jamais touchés : dossiers clients (hors dossiers régénérables), iCloud, Dropbox, Google Drive, applications (signalées seulement).

```bash
forgotten_files.py                       # rapport
forgotten_files.py --only big --days 365 --min-size 500
forgotten_files.py --clean
```

Pour inclure la Corbeille et les sauvegardes d'iPhone : donner l'« Accès complet au disque » au terminal (Réglages > Confidentialité).
</details>

<details id="duplicatespy">
<summary><b><code>duplicates.py</code></b> — 👯 les fichiers en double, comparés par leur contenu</summary>

Même taille, puis même début, puis même contenu complet : deux fichiers différents ne sont **jamais** confondus, quel que soit leur nom. Pour chaque groupe, la copie gardée est la mieux rangée (dossier protégé, hors Téléchargements, nom sans « (1) » ni « copie », la plus ancienne). Résumé des **dossiers copiés en entier**. Ignorés : bibliothèque Photos, dépôts git, dossiers de build, fichiers restés dans iCloud (pas téléchargés pour rien), liens physiques.

```bash
duplicates.py                            # Téléchargements, Bureau, Documents, Images
duplicates.py ~/Pictures --min-size 500  # seulement les fichiers de plus de 500 Ko
duplicates.py --clean                    # tout / un par un / rien, groupe par groupe
```
</details>

<details id="app_uninstallpy">
<summary><b><code>app_uninstall.py</code></b> — 🧹 désinstaller une app <i>et tout ce qu'elle a laissé</i></summary>

Glisser une app dans la Corbeille laisse derrière elle préférences, caches, `Application Support`, conteneurs, cookies, agents de démarrage… parfois des centaines de Mo. Le script les retrouve **par l'identifiant exact de l'app** (jamais par un mot approchant), affiche tout avec la taille, puis envoie à la Corbeille après confirmation. Refuse les apps d'Apple et les apps ouvertes ; renvoie vers `brew uninstall --cask --zap` pour celles installées avec Homebrew ; donne les commandes `sudo` pour les restes système sans les lancer.

```bash
app_uninstall.py --list                  # les apps les moins utilisées d'abord
app_uninstall.py "Microsoft Teams" --dry-run
app_uninstall.py Zoom
app_uninstall.py --leftovers             # restes d'apps déjà supprimées
```
</details>

<details id="startup_itemspy">
<summary><b><code>startup_items.py</code></b> — 🚦 tout ce qui démarre avec le Mac</summary>

Éléments d'ouverture, apps en arrière-plan, agents et démons, avec l'éditeur (signature) et l'état actif/inactif. Repère les **orphelins** (le programme n'existe plus : app désinstallée) et les programmes non signés.

```bash
startup_items.py                         # liste (sans les éléments d'Apple)
startup_items.py --all
startup_items.py --disable com.example.updater   # un de tes agents, réactivable avec --enable
startup_items.py --orphans               # tes orphelins à la Corbeille, commandes sudo pour les autres
```
</details>

<details id="photo_renamepy">
<summary><b><code>photo_rename.py</code></b> — 📸 des photos rangées par date de prise de vue</summary>

`IMG_4521.HEIC` → `2026-11-02_14-35-12.heic` : les photos se trient dans l'ordre chronologique partout, quel que soit l'appareil. Les Live Photos et fichiers associés (`.MOV`, `.AAE`, `.XMP`) suivent leur photo ; deux photos à la même seconde reçoivent `_2`. Date lue par exiftool (sinon Spotlight) ; les fichiers sans date de prise de vue sont marqués `~`.

**Simulation par défaut**, et chaque `--apply` écrit un fichier pour **tout annuler**.

```bash
photo_rename.py ~/Pictures/Vacances                       # aperçu
photo_rename.py ~/Pictures/Vacances --by-month --apply    # -> 2026/2026-07/…
photo_rename.py --undo ~/Pictures/Vacances/.photo_rename_20261102-213609.tsv
```
</details>

---

## 🛡️ Vie privée et documents sensibles

<details id="id_watermarkpy">
<summary><b><code>id_watermark.py</code></b> — 🪪 filigraner une pièce d'identité avant de l'envoyer</summary>

Agence immobilière, banque, employeur… Une copie de carte d'identité volée sert à usurper une identité. Le script écrit **en diagonale sur toute la page** à qui la copie est destinée, pour quoi et quand :

> *Copie destinée à Agence Dupont - usage : dossier location - 02/11/2026*

Le résultat est **aplati** (chaque page devient une image : le filigrane ne s'enlève pas en éditant le PDF) et ne garde pas les métadonnées. PDF ou photos (HEIC, JPG, PNG…), recto et verso réunis dans un seul PDF avec `-o`.

```bash
id_watermark.py cni-recto.heic cni-verso.heic --to "Agence Dupont" --for "dossier location" -o cni-dupont.pdf
id_watermark.py fiche-paie.pdf --to "Banque X" --opacity 0.4
id_watermark.py passeport.jpg --text "Copie pour l'hôtel Bellevue - séjour du 3 au 5 mai"
```
</details>

<details id="strip_metadatapy">
<summary><b><code>strip_metadata.py</code></b> — 🕵️ retirer les informations cachées avant de partager</summary>

Une photo de téléphone contient la **position GPS** exacte (souvent celle du domicile), le modèle de l'appareil, la date ; un PDF ou un `.docx` contient l'auteur, la société, le logiciel. Le script écrit une copie `NOM-clean.EXT` sans tout cela, puis **relit la copie pour vérifier** qu'il ne reste rien.

| Type | Comment | Ce qui est gardé |
|---|---|---|
| Photos (JPG, HEIC, PNG, TIFF, WEBP, DNG) | exiftool, sans perte | orientation, profil couleur |
| Vidéos (MOV, MP4, M4V) | ffmpeg, sans réencodage | image et son |
| PDF | pypdf | pages, signets |
| Word, Excel, PowerPoint | propriétés du document vidées | contenu |

```bash
strip_metadata.py --show IMG_1234.HEIC   # juste voir ce qu'elle révèle
strip_metadata.py photo.heic devis.pdf rapport.docx
strip_metadata.py ~/Desktop/À\ partager --out ~/Desktop/Propre
```
</details>

---

## 🟣 Odoo

Le cycle de vie d'un projet client, de la création à la démo :

```mermaid
flowchart LR
    A[odoo_new_project.sh] --> B[odoo_module_new.sh]
    B --> C[odoo_run.sh -i / -u]
    C --> D[odoo_i18n.sh]
    C --> E[odoo_run.sh --test<br/>odooTests.sh]
    C --> F[odoo_demo_share.sh]
    G[(copie de prod)] --> H[odoo_db.sh restore] --> I[odoo_anonymize.sh] --> C
    J[odoo_doctor.py] -.vérifie.-> C
```

Les sources Odoo sont partagées entre tous les projets : un worktree git par couple version + commit dans `~/Documents/Odoo/versions/`, synchronisé par [`odoo_project_sync.py`](#odoo_project_syncpy). Chaque projet décrit sa version dans `.odoo-project.json` et son lancement dans `.vscode/settings.json`, que tous les scripts relisent.

<details id="odoo_new_projectsh">
<summary><b><code>odoo_new_project.sh</code></b> — créer un projet client complet en une commande</summary>

Copie le template `~/Documents/Odoo/_templates/client-project`, écrit `.odoo-project.json` (réutilise par défaut le worktree `<version>@<hash>` déjà présent, sans nouveau checkout), le nom de base, `.ruff.toml`, `user/`, `.gitignore`, crée la venv uv (psycopg2 compilé contre Postgres.app) et, en option, une base initialisée sans données de démo.

```bash
odoo_new_project.sh "~/Desktop/Indépendant BApps/Clients/Acme/ERP/Odoo" 19.0 --db acme-dev --init-db --lang fr_FR
odoo_new_project.sh ./Odoo 20.0 --no-enterprise --latest
```

Options : `--db`, `--no-enterprise`, `--latest`, `--python X.Y`, `--init-db`, `--lang`.
</details>

<details id="odoo_runsh">
<summary><b><code>odoo_run.sh</code></b> — lancer Odoo depuis le terminal avec la configuration du projet</summary>

Reprend l'interpréteur, `odoo-bin` et les arguments de la configuration VS Code, et remplace les lignes `-i`/`-u`/`--test-tags` selon le mode choisi : plus besoin de modifier `settings.json`.

```bash
odoo_run.sh                          # comme le débogueur
odoo_run.sh -u my_module -p 8070     # mise à jour, à côté du débogueur
odoo_run.sh --test my_module         # installe/met à jour + tests, puis s'arrête
odoo_run.sh --test-tags /my_module:TestSale.test_discount
odoo_run.sh shell -d acme-dev        # shell Odoo
odoo_run.sh --dry-run --test my_module   # afficher la commande
```
</details>

<details id="odoo_module_newsh">
<summary><b><code>odoo_module_new.sh</code></b> — créer un module selon les conventions du projet</summary>

Manifest dans l'ordre habituel, auteur / licence / catégorie repris des modules existants, idiomes de la version : vues `<list>` (18+) ou `<tree>`, droits `security/ir.access.csv` en Odoo 20, `ir.model.access.csv` avant (jamais tous les droits à `base.group_user`). Rien d'autre que ce qui est demandé.

```bash
odoo_module_new.sh acme_sale_discount --depends sale
odoo_module_new.sh acme_fleet --model acme.vehicle --views --summary "Company vehicles"
```
</details>

<details id="odoo_i18nsh">
<summary><b><code>odoo_i18n.sh</code></b> — toute la chaîne de traduction d'un module</summary>

Exporte le `.pot` depuis la base (`odoo-bin i18n export` en 19+), crée les `.po` manquants, synchronise et reprend les traductions existantes d'un module source via `odoo_translate.py`, puis compte ce qu'il reste à traduire.

```bash
odoo_i18n.sh acme_fleet -l fr,nl --source fleet
#     fr   7 translated messages, 4 untranslated messages.
```
</details>

<details id="odoo_translatepy">
<summary><b><code>odoo_translate.py</code></b> — synchroniser les .po et copier des traductions</summary>

Synchronise les `.po` d'un module avec son `.pot` (en-tête préservé), puis remplit uniquement les traductions vides depuis un module source, cherché dans le projet puis dans le `--addons-path` (worktrees centralisés compris). Une langue régionale (`fr_BE`) se complète avec la langue de base (`fr`). Lancé par `uv`, qui installe `polib`.

```bash
odoo_translate.py my_module account
```
</details>

<details id="odoo_doctorpy">
<summary><b><code>odoo_doctor.py</code></b> — diagnostic de l'environnement et de tous les projets</summary>

Lecture seule. PostgreSQL, Mailpit, wkhtmltopdf, uv, dépôts centraux ; puis pour chaque projet : worktrees, `odoo-bin`, venv (arm64, psycopg2/lxml/Pillow… importables), `--addons-path`, `--http-interface=::`, base présente. Code de sortie 1 en cas d'erreur.

```bash
odoo_doctor.py                   # tous les projets trouvés
odoo_doctor.py . --quiet         # le projet courant, avertissements et erreurs seulement
```
</details>

<details id="odoo_dbsh">
<summary><b><code>odoo_db.sh</code></b> — sauvegarder, restaurer, cloner, neutraliser, supprimer</summary>

Base et filestore ensemble, au format de sauvegarde d'Odoo et d'Odoo.sh (`dump.sql`, `filestore/`, `manifest.json`). Une restauration est **neutralisée par défaut** (crons, serveurs de mails…). `drop` montre ce qui sera supprimé et demande de retaper le nom.

```bash
odoo_db.sh list
odoo_db.sh dump acme-dev
odoo_db.sh restore ~/Downloads/acme_prod.zip acme-prod-copy
odoo_db.sh clone acme-dev acme-dev-test
odoo_db.sh drop acme-dev-test
```
</details>

<details id="odoo_anonymizesh">
<summary><b><code>odoo_anonymize.sh</code></b> — copie anonymisée d'une base, à partager sans risque</summary>

Clone la base (la source n'est jamais modifiée), lance l'obfuscation native `odoo-bin obfuscate` (Odoo 17+) avec un mot de passe aléatoire jamais conservé, ajoute comptes bancaires, données privées des employés et champs `x_*` des contacts, remplace les identifiants de connexion, supprime les pièces jointes métier (et leurs fichiers), remet le mot de passe admin à `admin` et neutralise. N'affiche que des compteurs.

```bash
odoo_anonymize.sh acme-prod                 # -> acme-prod-anon
odoo_anonymize.sh acme-prod acme-share --keep-attachments
```
</details>

<details id="odoo_demo_sharesh">
<summary><b><code>odoo_demo_share.sh</code></b> — partager une démo par un lien public</summary>

Ouvre un tunnel ngrok vers l'Odoo local, fige `web.base.url` sur l'URL publique (liens des mails, portail, site), copie le lien, et remet tout en place au Ctrl-C, sans redémarrer Odoo.

```bash
odoo_demo_share.sh                    # depuis le dossier du projet, Odoo lancé
odoo_demo_share.sh --restore -d acme  # après un plantage
```
</details>

<details id="odootestssh">
<summary><b><code>odooTests.sh</code></b> — tests sur plusieurs instances en parallèle</summary>

Bases et filestores clonés, supprimés à la fin ou au Ctrl-C ; commande lue dans « Odoo All Tests » (sinon « Odoo D-Bug »).

```bash
odooTests.sh --threads 4
odooTests.sh --loop-until-fail 10    # traquer un test instable
```
</details>

<details id="accessodoofilestoresh">
<summary><b><code>accessOdooFilestore.sh</code></b> — retrouver et ouvrir les PDF générés par Odoo</summary>

```bash
accessOdooFilestore.sh acme-dev      # filtre par nom, ouvrir ou exporter
```
</details>

<details id="odoofiltersh">
<summary><b><code>odooFilter.sh</code></b> — domaine « OU » sur une liste de termes</summary>

```bash
odooFilter.sh -f partner_id.name dupont durand martin
odooFilter.sh -p < codes.txt         # codes du type « Nom (ABCD) »
# ["|", "|", ("partner_id.name", "ilike", "dupont"), …]   (copié dans le presse-papiers)
```
</details>

<details id="odoo_project_syncpy">
<summary><b><code>odoo_project_sync.py</code></b> — worktrees centralisés et chemins VS Code</summary>

Lit `.odoo-project.json`, crée les worktrees manquants sur le commit exact, puis corrige uniquement `--addons-path`, `program` et l'interpréteur `.venv` dans `.vscode/` (le reste n'est jamais touché). Lancé automatiquement à l'ouverture du projet dans VS Code (tâche `runOn: folderOpen` du template). Python 3.9+, bibliothèque standard.

```json
{
  "community": { "version": "19.0", "commit": "5b8e4559" },
  "enterprise": { "version": "19.0", "commit": "e2ec1078" }
}
```
</details>

---

## 📄 Documents et médias

<details id="pdf_toolspy">
<summary><b><code>pdf_tools.py</code></b> — infos, fusion, découpe, extraction, rotation, scan</summary>

L'original n'est jamais modifié. Pages au format `1-3,5,8-`.

```bash
pdf_tools.py info contrat.pdf
pdf_tools.py merge dossier.pdf devis.pdf contrat.pdf annexes.pdf   # un signet par fichier
pdf_tools.py extract contrat.pdf 1-3,7 -o signature.pdf
pdf_tools.py remove scan.pdf 2
pdf_tools.py rotate scan.pdf 90 --pages 2-3
pdf_tools.py split annexes.pdf --every 2
pdf_tools.py scan facture.pdf          # OCR + compression -> facture-scan.pdf
```
</details>

<details id="pdf_ocrsh">
<summary><b><code>pdf_ocr.sh</code></b> — rendre des PDF scannés interrogeables</summary>

OCRmyPDF (via `uvx` s'il n'est pas installé) + Tesseract ; pages déjà textuelles conservées, pages redressées.

```bash
pdf_ocr.sh scan.pdf                 # -> scan-ocr.pdf
pdf_ocr.sh -l fra+nld --replace     # tout le dossier, originaux sauvegardés
```
</details>

<details id="reducepdfsizesh">
<summary><b><code>reducePdfSize.sh</code></b> — alléger des PDF</summary>

Ghostscript, 5 niveaux de qualité ; l'original n'est remplacé que si le résultat est plus petit.

```bash
reducePdfSize.sh devis.pdf
reducePdfSize.sh                    # tout le dossier courant
```
</details>

<details id="recursivepdfsh">
<summary><b><code>recursivePdf.sh</code></b> — convertir des documents Word en PDF (et les fusionner)</summary>

```bash
recursivePdf.sh ~/Documents/Dossier   # .doc, .docx, .odt, .rtf, sous-dossiers compris
```
</details>

<details id="updateepubmetadatash">
<summary><b><code>updateEpubMetadata.sh</code></b> — titre et auteurs d'EPUB depuis le nom de fichier</summary>

Format `[Auteur(s)] Titre - Sous-titre.epub` ; écrit `<nom>_updated.epub`, conforme à la norme EPUB.

```bash
updateEpubMetadata.sh "[Jane Doe] Big Book - Part 1.epub"
```
</details>

<details id="convertreduceimgsh">
<summary><b><code>convertReduceImg.sh</code></b> — convertir et optimiser des images</summary>

webp / png / jpg, récursif, cible en KB ou en % de chaque fichier ; l'optimisation sans conversion ne remplace un fichier que s'il devient plus petit.

```bash
convertReduceImg.sh ~/Pictures/Site
```
</details>

<details id="compressvideosh">
<summary><b><code>compressVideo.sh</code></b> — compresser des vidéos</summary>

H.264 ou H.265 matériel (Apple Silicon), redimensionnement sans agrandissement, son facultatif ; l'original va dans `originals/` seulement si la vidéo compressée est plus petite.

```bash
compressVideo.sh ~/Movies/Démo
```
</details>

---

## ⚙️ Système et productivité

<details id="claude_sessionssh">
<summary><b><code>claude_sessions.sh</code></b> — parler à toutes les sessions Claude Code ouvertes</summary>

Liste les sessions (`claude agents --json`) et tape une demande dans chaque session **inactive** de Terminal.app ou iTerm2 : sauvegarder son contexte et sa mémoire pour une reprise ultérieure (puis `/compact`), les relire, ou tout autre message. Jamais pendant qu'une session travaille ou affiche une question ; la session qui lance le script est ignorée.

```bash
claude_sessions.sh list
claude_sessions.sh save --compact --wait     # avant de tout fermer le soir
claude_sessions.sh reload                    # le lendemain matin
claude_sessions.sh send "Lance les tests et résume les échecs" --only acme
claude_sessions.sh save --dry-run            # voir à qui ce serait envoyé
```

La première fois, macOS demande d'autoriser le terminal à contrôler Terminal / iTerm (Réglages > Confidentialité > Automatisation).
</details>

<details id="maintenancesh">
<summary><b><code>maintenance.sh</code></b> — contrôle hebdomadaire du Mac, avec notification</summary>

Homebrew (paquets à jour, `brew doctor`), santé du Mac ([`mac_health.sh`](#mac_healthsh) : batterie, sauvegarde, sécurité, mises à jour macOS), environnement Odoo (`odoo_doctor.py`), disque (`disk_report.sh`, alerte au-delà de 85 %), dépôts git (`git_status_all.sh`). Rapport dans `~/Library/Logs/maintenance/`, notification macOS seulement s'il y a quelque chose à faire.

```bash
maintenance.sh                    # maintenant
maintenance.sh --upgrade          # avec brew upgrade
maintenance.sh --install 09:00 1  # chaque lundi à 9 h (launchd) ; --uninstall pour arrêter
```
</details>

<details id="disk_reportsh">
<summary><b><code>disk_report.sh</code></b> — retrouver de la place</summary>

Bases Odoo sans projet, filestores orphelins, worktrees inutilisés, caches (uv, Homebrew, npm, pip, Xcode), anciennes venvs, Docker. Lecture seule par défaut ; `--clean` supprime élément par élément après confirmation.

```bash
disk_report.sh
disk_report.sh --clean
disk_report.sh --deep            # + les plus gros dossiers du dossier personnel
```
</details>

<details id="git_status_allsh">
<summary><b><code>git_status_all.sh</code></b> — tous les dépôts qui demandent de l'attention</summary>

Modifications non commitées, fichiers non suivis, commits à pousser ou à récupérer, stashs, branches sans upstream.

```bash
git_status_all.sh --fetch
```
</details>

<details id="timesheet_gitsh">
<summary><b><code>timesheet_git.sh</code></b> — temps estimé par jour et par client</summary>

À partir de tes commits dans tous les dépôts : sessions de travail (commits à moins de 2 h d'intervalle) + 30 min avant le premier commit.

```bash
timesheet_git.sh                              # mois en cours
timesheet_git.sh --since 2026-10-01 --until 2026-10-31 --client acme --details
timesheet_git.sh --since "last monday" --csv > semaine.csv
```
</details>

<details>
<summary><b><code>rmDSStore.sh</code></b> · <b><code>excelTempDir.sh</code></b> — petits utilitaires</summary>

```bash
rmDSStore.sh ~/Projets --dry-run     # .DS_Store récursifs
excelTempDir.sh                      # dossier temporaire d'Excel
```
</details>

---

## 📝 Notes

- Écrits pour le `/bin/bash` 3.2 et le `python3` 3.9 fournis par macOS : lancez-les avec `bash script.sh` (ou `./script.sh`), pas avec `sh`. Les scripts Python qui ont des dépendances (`odoo_translate.py`, `pdf_tools.py`, `id_watermark.py`, `strip_metadata.py`) sont exécutés par `uv`, qui les installe tout seul.
- Rien n'est supprimé sans confirmation explicite ; les originaux de fichiers sont conservés ou sauvegardés.
- Les outils « Mac au quotidien » partagent [`lib/mac_common.py`](lib/mac_common.py) : dossiers protégés, comparaison des chemins accentués, envoi à la Corbeille, questions posées au terminal.
- Les scripts Odoo partagent [`lib/odoo_projects.py`](lib/odoo_projects.py) : recherche des projets dans `~/Desktop/Indépendant BApps/Clients` et `~/Documents` (modifiable avec `ODOO_PROJECT_ROOTS="dossier1:dossier2"`), lecture des configurations VS Code, bases utilisées.

<div align="center">

**Auteur :** [Pierre LAMOTTE](mailto:pl@barracudapps.com) — une idée de script ? Ouvre une issue, elle a peut-être déjà sa place dans la boîte à outils 🧰

</div>
