#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

################################################################################
# Script: 	accessOdooFilestore.sh
# Description: 	Locate and open the Odoo 'filestore' directory for a given DB name.
# Usage: 	bash ~/Documents/scripts/accessOdooFilestore.sh <db_name>
# Author: 	Pierre LAMOTTE
# Date: 	23 JUN 2025
################################################################################

db_name="${1:-}"
default_user="$USER"
db_port="5432"
list_limit=50

if [ -z "${db_name:-}" ]; then
    echo "❌ Usage: $0 <db_name>"
    exit 1
fi

# Select psql
if [ -x "/Applications/Postgres.app/Contents/Versions/latest/bin/psql" ]; then
    echo "📦 Using Postgres.app's psql binary"
    PSQL_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin/psql"
else
    PSQL_BIN="psql"
fi

# Locate filestore
echo "🧭 Locating filestore for '$db_name'..."
filestore_base=""
if [[ "$(uname)" == "Darwin" ]]; then
    filestore_base=$(find "$HOME/Library/Application Support/Odoo" -type d -name filestore -maxdepth 3 2>/dev/null | head -n 1)
fi
[ -z "$filestore_base" ] && [ -d "$HOME/.local/share/Odoo/filestore" ] && filestore_base="$HOME/.local/share/Odoo/filestore"
[ -z "$filestore_base" ] && filestore_base=$(find "$HOME" -type d -name filestore 2>/dev/null | head -n 1)

filestore_path="$filestore_base/$db_name"
if [ -z "$filestore_base" ] || [ ! -d "$filestore_path" ]; then
    echo "❌ Filestore not found for DB '$db_name'"
    exit 2
fi

echo "✅ Filestore found: $filestore_path"
echo ""

# User choice
echo "What would you like to do?"
echo "  [1] Open in Terminal"
echo "  [2] Open in Finder (macOS) / Files (Linux)"
echo "  [3] Quit"
echo "  [4] Don't open it, go to the PDF attachments"
read -rp "Enter your choice [1/2/3/4]: " user_choice

case "$user_choice" in
    1)
        if [[ "$(uname)" == "Darwin" ]]; then
            open -a Terminal "$filestore_path"
        else
            gnome-terminal --working-directory="$filestore_path" &>/dev/null || x-terminal-emulator &
        fi
        ;;
    2)
        if [[ "$(uname)" == "Darwin" ]]; then
            open "$filestore_path"
        else
            xdg-open "$filestore_path" &>/dev/null
        fi
        ;;
    4) ;;
    *)
        echo "👋 Exiting."
        exit 0
        ;;
esac

echo ""
read -rp "🔎 Filter PDF attachments by name (empty = the $list_limit most recent): " name_filter

# The filter is passed as a psql variable (:'pattern'), never pasted into the SQL
query="SELECT store_fname, name FROM ir_attachment
WHERE mimetype = 'application/pdf' AND store_fname IS NOT NULL
  AND name ILIKE :'pattern'
ORDER BY create_date DESC LIMIT $list_limit;"

run_query() {
    printf '%s\n' "$query" | "$PSQL_BIN" "$@" -d "$db_name" -At -v pattern="%${name_filter}%" 2>/dev/null || true
}

echo "📡 Querying database for PDF attachments..."
conn_args=(-U "$default_user")
if ! "$PSQL_BIN" "${conn_args[@]}" -d "$db_name" -Atc "SELECT 1" >/dev/null 2>&1; then
    echo "🔐 PostgreSQL connection failed with default user."
    read -rp "🔹 DB user: " db_user
    read -srp "🔹 DB password: " db_pass
    echo ""
    read -rp "🔹 DB port (default 5432): " custom_port
    db_port=${custom_port:-5432}
    export PGPASSWORD="$db_pass"
    conn_args=(-U "$db_user" -p "$db_port")
    if ! "$PSQL_BIN" "${conn_args[@]}" -d "$db_name" -Atc "SELECT 1" >/dev/null 2>&1; then
        echo "❌ Unable to connect to database '$db_name'."
        exit 3
    fi
fi

results=$(run_query "${conn_args[@]}")
if [ -z "$results" ]; then
    echo "❌ No PDF attachment found${name_filter:+ matching '$name_filter'}."
    exit 3
fi

echo ""
echo "📂 PDF Attachments:"

names=()
paths=()

# File name usable on disk: no "/" or ":", single ".pdf" extension
safe_pdf_name() {
    local n="${1//\//_}"
    n="${n//:/_}"
    n="${n%.[pP][dD][fF]}"
    printf '%s.pdf' "${n:-attachment}"
}

while IFS='|' read -r store_fname readable_name; do
    if [[ "$store_fname" == */* ]]; then
        full_path="$filestore_path/$store_fname"
    else
        prefix="${store_fname:0:2}"
        full_path="$filestore_path/$prefix/$store_fname"
    fi
    [[ -f "$full_path" ]] || continue   # attachment present in DB but not on disk
    names+=("$readable_name")
    paths+=("$full_path")
done <<< "$results"

if [ ${#names[@]} -eq 0 ]; then
    echo "❌ The matching attachments are missing from the filestore."
    exit 3
fi
echo "${#names[@]} PDF(s) found."

echo ""
echo "📁 Actions:"
echo "  [1] Open one PDF"
echo "  [2] Export one PDF"
echo "  [3] Export ALL PDFs"
echo "  [4] Quit"
read -rp "Choose an action [1/2/3/4]: " action

if [[ "$action" == "1" ]]; then
    PS3="📥 Choose a PDF to open: "
    select choice in "${names[@]}"; do
        if [[ -z "$choice" ]]; then
            echo "❌ Invalid selection."
        else
            idx=$((REPLY - 1))
            src="${paths[$idx]}"
            tmp_pdf="${TMPDIR:-/tmp}/$(safe_pdf_name "${names[$idx]}")"
            cp "$src" "$tmp_pdf"
            echo "🚀 Opening: $tmp_pdf"
            open "$tmp_pdf" 2>/dev/null || xdg-open "$tmp_pdf" || echo "⚠️ Open manually: $tmp_pdf"
            break
        fi
    done

elif [[ "$action" == "2" ]]; then
    echo ""
    read -rp "📂 Enter destination folder: " export_dir
    export_dir="${export_dir/#\~/$HOME}"
    mkdir -p "$export_dir"
    PS3="📥 Choose a PDF to export: "
    select choice in "${names[@]}"; do
        if [[ -z "$choice" ]]; then
            echo "❌ Invalid selection."
        else
            idx=$((REPLY - 1))
            dest="$export_dir/$(safe_pdf_name "${names[$idx]}")"
            cp "${paths[$idx]}" "$dest"
            echo "✅ Exported: $dest"
            break
        fi
    done

elif [[ "$action" == "3" ]]; then
    echo ""
    read -rp "📂 Enter destination folder for ALL PDFs: " export_all_dir
    export_all_dir="${export_all_dir/#\~/$HOME}"
    mkdir -p "$export_all_dir"
    for i in "${!names[@]}"; do
        filename=$(safe_pdf_name "${names[$i]}")
        # Same name twice: add a counter instead of overwriting
        n=2
        while [[ -e "$export_all_dir/$filename" ]]; do
            filename="$(safe_pdf_name "${names[$i]}")"
            filename="${filename%.pdf}-$n.pdf"
            n=$((n + 1))
        done
        cp "${paths[$i]}" "$export_all_dir/$filename"
        echo "✅ Exported: $filename"
    done
    echo "📁 All PDFs exported to: $export_all_dir"

else
    echo "👋 Exiting."
fi
