#!/bin/bash

################################################################################
# Script:       disk_report.sh
# Description:  Shows what takes disk space and can probably be reclaimed:
#               Odoo databases used by no project, orphan filestores, shared
#               Odoo worktrees used by no project, developer caches (uv,
#               Homebrew, npm, pip, Xcode), leftover .venv backups, Docker.
#               Read-only by default. With --clean, each item is shown in
#               detail and deleted only after an explicit confirmation.
# Usage:        bash ~/Documents/scripts/disk_report.sh [--clean] [--deep]
#               --deep also lists the biggest folders of the home directory
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ODOO_ROOT="$HOME/Documents/Odoo"
PG_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"
[[ -x "$PG_BIN/psql" ]] && export PATH="$PG_BIN:$PATH"
FILESTORE_BASE="$HOME/Library/Application Support/Odoo/filestore"

clean=false
deep=false
for arg in "$@"; do
    case "$arg" in
        --clean) clean=true ;;
        --deep) deep=true ;;
        -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
total_kb=0

kb_of() { [[ -e "$1" ]] && du -sk "$1" 2>/dev/null | awk '{ print $1 }' || echo 0; }
human_kb() { awk -v k="$1" 'BEGIN { split("KB MB GB TB", u); i = 1; while (k >= 1024 && i < 4) { k /= 1024; i++ } printf "%.1f %s", k, u[i] }'; }
section() { echo ""; echo "${BOLD}$*${NC}"; }
line() { printf '  %10s  %s\n' "$(human_kb "$1")" "$2"; total_kb=$((total_kb + $1)); }
confirm() { local a; read -rp "    -> $1 (y/N) " a </dev/tty; [[ "$a" =~ ^[yY] ]]; }

projects_dbs=$(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" dbs 2>/dev/null)
projects=$(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" projects 2>/dev/null)

# --------------------------------------------------------------------------- #
section "Bases Odoo utilisées par aucun projet (taille base + filestore)"
db_list=""
if psql -d postgres -Atc "SELECT 1" >/dev/null 2>&1; then
    db_list=$(psql -d postgres -AtF $'\t' -c "SELECT datname, pg_database_size(datname) / 1024 FROM pg_database
        WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY 2 DESC")
    found=false
    while IFS=$'\t' read -r db size_kb; do
        [[ -z "$db" ]] && continue
        cut -f1 <<<"$projects_dbs" | grep -qxF "$db" && continue
        fs_kb=$(kb_of "$FILESTORE_BASE/$db")
        line $((size_kb + fs_kb)) "$db ${DIM}(base $(human_kb "$size_kb"), filestore $(human_kb "$fs_kb"))${NC}"
        found=true
        if $clean && confirm "Supprimer la base '$db' et son filestore ?"; then
            bash "$SCRIPTS_DIR/odoo_db.sh" drop "$db" </dev/tty
        fi
    done <<<"$db_list"
    $found || echo "  (aucune)"
else
    echo "  PostgreSQL injoignable, section ignorée"
fi

# --------------------------------------------------------------------------- #
section "Filestores sans base de données (ni projet qui les référence)"
orphans=()
orphans_kb=0
if [[ -d "$FILESTORE_BASE" && -n "$db_list" ]]; then   # unknown DB list: never call a filestore orphan
    for fs in "$FILESTORE_BASE"/*/; do
        [[ -d "$fs" ]] || continue
        name=$(basename "$fs")
        cut -f1 <<<"$db_list" | grep -qxF "$name" && continue
        cut -f1 <<<"$projects_dbs" | grep -qxF "$name" && continue   # e.g. DB running in Docker
        kb=$(kb_of "$fs")
        line "$kb" "$name"
        orphans+=("$name")
        orphans_kb=$((orphans_kb + kb))
    done
fi
if [[ ${#orphans[@]} -eq 0 ]]; then
    echo "  (aucun)"
else
    echo "  ${DIM}${#orphans[@]} filestore(s), $(human_kb "$orphans_kb"), dans $FILESTORE_BASE${NC}"
    if $clean; then
        read -rp "    -> Supprimer [a]ll les ${#orphans[@]} filestores listés, [e]ach un par un, [N]one ? " choice </dev/tty
        for name in "${orphans[@]}"; do
            case "$choice" in
                a|A) ;;
                e|E) confirm "Supprimer $name ($(human_kb "$(kb_of "$FILESTORE_BASE/$name")")) ?" || continue ;;
                *) break ;;
            esac
            rm -rf "${FILESTORE_BASE:?}/${name:?}" && echo "    supprimé : $name"
        done
    fi
fi

# --------------------------------------------------------------------------- #
section "Worktrees Odoo partagés utilisés par aucun projet"
# A worktree is used when a project's .odoo-project.json, odoo-bin, addons path
# or symlink points into it. Branch worktrees without @hash (e.g. 19.0) are the
# shared defaults: listed only for information, never proposed for deletion.
used=$(
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        if [[ -f "$p/.odoo-project.json" ]]; then
            python3 - "$p/.odoo-project.json" "$ODOO_ROOT" <<'PYEOF'
import json, subprocess, sys
data = json.load(open(sys.argv[1])); root = sys.argv[2]
for edition, repo in (("community", "odoo.git"), ("enterprise", "enterprise.git")):
    entry = data.get(edition)
    if not entry:
        continue
    r = subprocess.run(["git", "-C", f"{root}/_repos/{repo}", "rev-parse", "--short=8",
                        f"{entry.get('commit', entry['version'])}^{{commit}}"], capture_output=True, text=True)
    if r.returncode == 0:
        print(f"{root}/versions/{edition}/{entry['version']}@{r.stdout.strip()}")
PYEOF
        fi
        grep -ho "$ODOO_ROOT/versions/[a-z]*/[0-9.]*@*[0-9a-f]*" "$p/.vscode/"*.json 2>/dev/null
        find "$p" -maxdepth 2 -type l -exec readlink {} \; 2>/dev/null | grep -o "$ODOO_ROOT/versions/[a-z]*/[^/]*"
        [[ "$p" == "$ODOO_ROOT/versions/"* ]] && echo "$p"
    done <<<"$projects" | sort -u
)
found=false
for edition in community enterprise; do
    repo="$ODOO_ROOT/_repos/$([[ $edition == community ]] && echo odoo || echo enterprise).git"
    for wt in "$ODOO_ROOT/versions/$edition"/*/; do
        [[ -d "$wt" ]] || continue
        wt="${wt%/}"
        grep -qxF "$wt" <<<"$used" && continue
        kb=$(kb_of "$wt")
        if [[ "$(basename "$wt")" != *@* ]]; then
            printf '  %10s  %s %s\n' "$(human_kb "$kb")" "$wt" "${DIM}(worktree de branche par défaut, conservé)${NC}"
            continue
        fi
        line "$kb" "$wt"
        found=true
        if $clean && confirm "Retirer ce worktree (git worktree remove) ?"; then
            git -C "$repo" worktree remove "$wt" && echo "    retiré" || echo "    refusé par git (modifications locales ?)"
        fi
    done
    git -C "$repo" worktree prune 2>/dev/null
done
$found || echo "  (aucun worktree @commit inutilisé)"

# --------------------------------------------------------------------------- #
section "Caches de développement (se reconstruisent automatiquement)"
cache_line() {   # kb, label, clean command (empty = report only)
    local kb="$1" label="$2" cmd="$3"
    (( kb > 0 )) || return 0
    line "$kb" "$label"
    if $clean && [[ -n "$cmd" ]] && confirm "Nettoyer : $cmd ?"; then
        eval "$cmd"
    fi
}
command -v uv >/dev/null && cache_line "$(kb_of "$(uv cache dir 2>/dev/null)")" "uv ($(uv cache dir 2>/dev/null))" "uv cache prune"
command -v brew >/dev/null && cache_line "$(kb_of "$(brew --cache)")" "Homebrew ($(brew --cache))" "brew cleanup --prune=all"
cache_line "$(kb_of "$HOME/.npm/_cacache")" "npm ($HOME/.npm/_cacache)" "npm cache clean --force"
cache_line "$(kb_of "$HOME/Library/Caches/pip")" "pip ($HOME/Library/Caches/pip)" "rm -rf \"\$HOME/Library/Caches/pip\""
cache_line "$(kb_of "$HOME/Library/Developer/Xcode/DerivedData")" "Xcode DerivedData" "rm -rf \"\$HOME/Library/Developer/Xcode/DerivedData\"/*"
cache_line "$(kb_of "$HOME/Library/Developer/CoreSimulator/Caches")" "Simulateurs iOS (caches)" "xcrun simctl delete unavailable"

# --------------------------------------------------------------------------- #
section "Sauvegardes de venv et restes de migration"
found=false
while IFS= read -r -d '' d; do
    line "$(kb_of "$d")" "$d"
    found=true
    if $clean && confirm "Supprimer cette ancienne venv ?"; then
        rm -rf "$d" && echo "    supprimé"
    fi
done < <(find "$HOME/Desktop" "$HOME/Documents" -maxdepth 6 -type d -name '.venv.*' -prune -print0 2>/dev/null)
$found || echo "  (aucune)"

# --------------------------------------------------------------------------- #
section "Docker (rapport seulement : nettoyer avec 'docker system prune')"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    docker system df 2>/dev/null | sed 's/^/  /'
else
    echo "  Docker non lancé"
fi

if $deep; then
    section "Plus gros dossiers du dossier personnel (peut prendre du temps)"
    du -xk -d 2 "$HOME" 2>/dev/null | sort -rn | sed -n '2,21p' | while read -r kb path; do
        printf '  %10s  %s\n' "$(human_kb "$kb")" "${path/#$HOME/~}"
    done
fi

echo ""
echo "${BOLD}Total récupérable estimé (hors Docker) : $(human_kb "$total_kb")${NC}"
$clean || echo "${DIM}Relancer avec --clean pour supprimer élément par élément, après confirmation.${NC}"
