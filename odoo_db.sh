#!/bin/bash

################################################################################
# Script:       odoo_db.sh
# Description:  Manages local Odoo databases together with their filestore.
#               Backups use Odoo's own format (zip with dump.sql, filestore/
#               and manifest.json), compatible with the database manager and
#               Odoo.sh. Restored databases are neutralized by default
#               (crons, outgoing mail servers, payment providers... disabled).
# Usage:        bash odoo_db.sh list
#               bash odoo_db.sh dump <db> [output.zip]
#               bash odoo_db.sh restore <backup.zip|.dump|.sql> <db> [--no-neutralize] [--project DIR]
#               bash odoo_db.sh clone <source_db> <new_db>
#               bash odoo_db.sh neutralize <db> [--project DIR]
#               bash odoo_db.sh drop <db>
# Notes:        The project (python, odoo-bin, addons-path) needed by
#               "neutralize" is found from the VS Code configuration using the
#               database, the current directory, or --project.
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"
[[ -x "$PG_BIN/psql" ]] && export PATH="$PG_BIN:$PATH"

if [[ "$OSTYPE" == "darwin"* ]]; then
    FILESTORE_BASE="$HOME/Library/Application Support/Odoo/filestore"
else
    FILESTORE_BASE="$HOME/.local/share/Odoo/filestore"
fi

TMP_DIR=""
trap '[[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"' EXIT

fatal() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "==> $*"; }
usage() { sed -n '/^# Usage:/,/^# Notes:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

for tool in psql pg_dump createdb dropdb rsync zip unzip python3; do
    command -v "$tool" >/dev/null || fatal "'$tool' is required"
done

db_exists() { [[ "$(psql -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$1'")" == "1" ]]; }
check_name() { [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] || fatal "Invalid database name: '$1'"; }
human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i] }'; }
dir_size() { [[ -d "$1" ]] && du -sk "$1" | awk '{ print $1 * 1024 }' || echo 0; }
projects_using() { python3 "$SCRIPTS_DIR/lib/odoo_projects.py" dbs | awk -F'\t' -v db="$1" '$1 == db { print $2 }'; }

# Project used to run odoo-bin for a database: --project, a project whose
# configuration uses the database, or the current directory
find_project() {
    local db="$1" wanted="$2" candidate
    if [[ -n "$wanted" ]]; then echo "$wanted"; return; fi
    candidate=$(projects_using "$db" | head -n 1)
    if [[ -n "$candidate" ]]; then echo "$candidate"; return; fi
    if python3 "$SCRIPTS_DIR/lib/odoo_projects.py" config "$PWD" >/dev/null 2>&1; then echo "$PWD"; fi
}

cmd_list() {
    local refs
    refs=$(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" dbs)
    printf '%-32s %10s %10s  %-8s %s\n' "DATABASE" "DB SIZE" "FILESTORE" "ODOO" "PROJECT(S)"
    psql -d postgres -AtF $'\t' -c "SELECT datname, pg_database_size(datname) FROM pg_database
        WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname" |
    while IFS=$'\t' read -r db size; do
        local version projects
        version=$(psql -d "$db" -Atc "SELECT latest_version FROM ir_module_module WHERE name = 'base'" 2>/dev/null | cut -d. -f1,2 || true)
        projects=$(awk -F'\t' -v db="$db" '$1 == db { sub(".*/Clients/", "", $2); sub(ENVIRON["HOME"], "~", $2); print $2 }' <<<"$refs" | paste -sd, -)
        printf '%-32s %10s %10s  %-8s %s\n' "$db" "$(human "$size")" "$(human "$(dir_size "$FILESTORE_BASE/$db")")" \
            "${version:--}" "${projects:-(no project)}"
    done
}

cmd_dump() {
    local db="$1" output="${2:-}"
    check_name "$db"
    db_exists "$db" || fatal "Database '$db' does not exist"
    output="${output:-$PWD/${db}_$(date +%Y%m%d_%H%M%S).zip}"
    [[ "$output" == *.zip ]] || output+=".zip"
    [[ -e "$output" ]] && fatal "$output already exists"

    TMP_DIR=$(mktemp -d)
    local tmp="$TMP_DIR"
    info "Dumping database '$db'..."
    pg_dump --no-owner --format=plain --file="$tmp/dump.sql" "$db"
    if [[ -d "$FILESTORE_BASE/$db" ]]; then
        info "Copying filestore ($(human "$(dir_size "$FILESTORE_BASE/$db")"))..."
        mkdir -p "$tmp/filestore"
        rsync -a "$FILESTORE_BASE/$db/" "$tmp/filestore/"
    fi
    psql -d "$db" -Atc "SELECT json_build_object(
            'odoo_dump', '1', 'db_name', current_database(),
            'version', (SELECT latest_version FROM ir_module_module WHERE name = 'base'),
            'pg_version', current_setting('server_version'),
            'modules', (SELECT json_object_agg(name, latest_version) FROM ir_module_module WHERE state = 'installed'))" \
        > "$tmp/manifest.json" 2>/dev/null || echo '{"odoo_dump": "1"}' > "$tmp/manifest.json"
    info "Compressing..."
    (cd "$tmp" && zip -q -r "$output" .)
    info "Backup written: $output ($(human "$(stat -f%z "$output")"))"
}

cmd_restore() {
    local file="$1" db="$2" neutralize=true project=""
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-neutralize) neutralize=false; shift ;;
            --project) project="${2/#\~/$HOME}"; shift 2 ;;
            *) fatal "Unknown option: $1" ;;
        esac
    done
    check_name "$db"
    [[ -f "$file" ]] || fatal "Backup not found: $file"
    db_exists "$db" && fatal "Database '$db' already exists (drop it first: odoo_db.sh drop $db)"
    [[ -e "$FILESTORE_BASE/$db" ]] && fatal "A filestore already exists for '$db': $FILESTORE_BASE/$db"

    TMP_DIR=$(mktemp -d)
    local tmp="$TMP_DIR"
    createdb "$db"
    case "$file" in
        *.zip)
            info "Extracting $file..."
            unzip -q "$file" -d "$tmp"
            [[ -f "$tmp/dump.sql" ]] || fatal "No dump.sql in the archive (not an Odoo backup?)"
            info "Restoring SQL dump..."
            psql -q -d "$db" -v ON_ERROR_STOP=0 -f "$tmp/dump.sql" >/dev/null 2>"$tmp/psql.log" || true
            if [[ -d "$tmp/filestore" ]]; then
                mkdir -p "$FILESTORE_BASE"
                mv "$tmp/filestore" "$FILESTORE_BASE/$db"
                info "Filestore restored ($(human "$(dir_size "$FILESTORE_BASE/$db")"))"
            fi
            ;;
        *.dump|*.backup)
            info "Restoring custom-format dump..."
            pg_restore --no-owner -d "$db" "$file" 2>"$tmp/psql.log" || true
            ;;
        *.sql)
            info "Restoring SQL dump..."
            psql -q -d "$db" -v ON_ERROR_STOP=0 -f "$file" >/dev/null 2>"$tmp/psql.log" || true
            ;;
        *) dropdb "$db"; fatal "Unsupported backup format: $file (expected .zip, .dump or .sql)" ;;
    esac

    local errors
    errors=$(grep -c 'ERROR' "$tmp/psql.log" || true)
    if ! psql -d "$db" -Atc "SELECT 1 FROM ir_module_module LIMIT 1" >/dev/null 2>&1; then
        fatal "The restored database does not look like an Odoo database ($errors SQL error(s))"
    fi
    (( errors > 0 )) && echo "[WARN] $errors SQL error(s) during the restore (often harmless: roles, extensions)" >&2
    info "Database '$db' restored"

    if $neutralize; then
        cmd_neutralize "$db" ${project:+--project "$project"}
    else
        echo "[WARN] Database NOT neutralized: crons and outgoing mail servers are active." >&2
    fi
}

cmd_neutralize() {
    local db="$1" project="" config python program
    shift
    [[ "${1:-}" == "--project" ]] && project="${2/#\~/$HOME}"
    check_name "$db"
    db_exists "$db" || fatal "Database '$db' does not exist"

    project=$(find_project "$db" "$project")
    if [[ -z "$project" ]]; then
        echo "[WARN] No Odoo project found to neutralize '$db'." >&2
        echo "       Rerun: odoo_db.sh neutralize $db --project <project_dir>" >&2
        return 1
    fi
    config=$(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" config "$project") || fatal "No launch configuration in $project"
    python=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["python"])' <<<"$config")
    program=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["program"])' <<<"$config")
    local addons
    addons=$(python3 -c 'import json,sys; print(next((a for a in json.load(sys.stdin)["args"] if a.startswith("--addons-path=")), ""))' <<<"$config")
    [[ -x "$python" ]] || python="$project/.venv/bin/python3"
    [[ -x "$python" && -f "$program" ]] || fatal "Python or odoo-bin not found for project $project"

    info "Neutralizing '$db' with $project..."
    (cd "$project" && "$python" "$program" neutralize -d "$db" ${addons:+"$addons"} --log-level=warn)
    info "Database '$db' neutralized"
}

cmd_clone() {
    local source="$1" target="$2"
    check_name "$source"; check_name "$target"
    db_exists "$source" || fatal "Database '$source' does not exist"
    db_exists "$target" && fatal "Database '$target' already exists"
    info "Cloning '$source' into '$target'..."
    if ! createdb -T "$source" "$target" 2>/dev/null; then
        fatal "Clone failed: '$source' is probably in use (stop Odoo / close psql sessions on it)"
    fi
    if [[ -d "$FILESTORE_BASE/$source" ]]; then
        rsync -a "$FILESTORE_BASE/$source/" "$FILESTORE_BASE/$target/"
    fi
    info "Done: '$target' ($(human "$(psql -d postgres -Atc "SELECT pg_database_size('$target')")"), filestore $(human "$(dir_size "$FILESTORE_BASE/$target")"))"
}

cmd_drop() {
    local db="$1" projects answer
    check_name "$db"
    db_exists "$db" || [[ -d "$FILESTORE_BASE/$db" ]] || fatal "Neither database nor filestore found for '$db'"
    projects=$(projects_using "$db")

    echo "The following will be deleted:"
    if db_exists "$db"; then
        echo "  - database '$db' ($(human "$(psql -d postgres -Atc "SELECT pg_database_size('$db')")"))"
    fi
    [[ -d "$FILESTORE_BASE/$db" ]] && echo "  - filestore $FILESTORE_BASE/$db ($(human "$(dir_size "$FILESTORE_BASE/$db")"))"
    if [[ -n "$projects" ]]; then
        echo "  WARNING: used by these project(s):"
        while IFS= read -r p; do echo "    $p"; done <<<"$projects"
    fi
    read -rp "Type the database name to confirm: " answer
    [[ "$answer" == "$db" ]] || { echo "Aborted."; exit 1; }

    if db_exists "$db"; then
        dropdb "$db" || fatal "dropdb failed ('$db' is probably in use: stop Odoo first)"
    fi
    [[ -d "$FILESTORE_BASE/$db" ]] && rm -rf "${FILESTORE_BASE:?}/$db"
    info "'$db' deleted"
}

command="${1:-}"
[[ -n "$command" ]] && shift
case "$command" in
    list) cmd_list ;;
    dump) [[ $# -ge 1 ]] || { usage >&2; exit 1; }; cmd_dump "$@" ;;
    restore) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; cmd_restore "$@" ;;
    clone) [[ $# -eq 2 ]] || { usage >&2; exit 1; }; cmd_clone "$@" ;;
    neutralize) [[ $# -ge 1 ]] || { usage >&2; exit 1; }; cmd_neutralize "$@" ;;
    drop) [[ $# -eq 1 ]] || { usage >&2; exit 1; }; cmd_drop "$@" ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 1 ;;
esac
