#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

################################################################################
# Script: 	accessOdooFilestore.sh
# Description: 	Locate and open the Odoo 'filestore' directory for a given DB name.
# Usage: 	sh ~/Documents/scripts/accessOdooFilestore.sh [db_name]
# Author: 	Pierre LAMOTTE
# Date: 	23 JUN 2025
################################################################################

db_name="$1"
default_user="$USER"
db_port="5432"
query="SELECT store_fname, name FROM ir_attachment WHERE mimetype = 'application/pdf' AND store_fname IS NOT NULL ORDER BY create_date DESC;"

if [ -z "${db_name:-}" ]; then
    echo "❌ Usage: $0 <db_name>"
    exit 1
fi

# Detect bash version
BASH_MAJOR_VERSION=$([ -n "${BASH_VERSINFO:-}" ] && echo "${BASH_VERSINFO[0]}" || echo "3")

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
read -rp "Enter your choice [1/2/3]: " user_choice

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
    *)
        echo "👋 Exiting."
        exit 0
        ;;
esac

echo ""
echo "📡 Querying database for PDF attachments..."
results=$($PSQL_BIN -U "$default_user" -d "$db_name" -Atc "$query" 2>/dev/null || true)

if [ -z "$results" ]; then
    echo "🔐 PostgreSQL connection failed with default user."
    read -rp "🔹 DB user: " db_user
    read -srp "🔹 DB password: " db_pass
    echo ""
    read -rp "🔹 DB port (default 5432): " custom_port
    db_port=${custom_port:-5432}
    export PGPASSWORD="$db_pass"
    results=$($PSQL_BIN -U "$db_user" -d "$db_name" -p "$db_port" -Atc "$query" 2>/dev/null || true)
fi

if [ -z "$results" ]; then
    echo "❌ Unable to retrieve PDF attachments from database."
    exit 3
fi

echo ""
echo "📂 PDF Attachments:"

names=()
paths=()

while IFS='|' read -r store_fname readable_name; do
    if [[ "$store_fname" == */* ]]; then
        full_path="$filestore_path/$store_fname"
    else
        prefix="${store_fname:0:2}"
        full_path="$filestore_path/$prefix/$store_fname"
    fi
    names+=("$readable_name")
    paths+=("$full_path")
done <<< "$results"

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
            tmp_pdf="/tmp/${names[$idx]// /_}.pdf"
            cp "$src" "$tmp_pdf"
            echo "🚀 Opening: $tmp_pdf"
            open "$tmp_pdf" 2>/dev/null || xdg-open "$tmp_pdf" || echo "⚠️ Open manually: $tmp_pdf"
            break
        fi
    done

elif [[ "$action" == "2" ]]; then
    echo ""
    read -rp "📂 Enter destination folder: " export_dir
    mkdir -p "$export_dir"
    PS3="📥 Choose a PDF to export: "
    select choice in "${names[@]}"; do
        if [[ -z "$choice" ]]; then
            echo "❌ Invalid selection."
        else
            idx=$((REPLY - 1))
            dest="$export_dir/${names[$idx]// /_}.pdf"
            cp "${paths[$idx]}" "$dest"
            echo "✅ Exported: $dest"
            break
        fi
    done

elif [[ "$action" == "3" ]]; then
    echo ""
    read -rp "📂 Enter destination folder for ALL PDFs: " export_all_dir
    mkdir -p "$export_all_dir"
    for i in "${!names[@]}"; do
        filename="${names[$i]// /_}.pdf"
        cp "${paths[$i]}" "$export_all_dir/$filename"
        echo "✅ Exported: $filename"
    done
    echo "📁 All PDFs exported to: $export_all_dir"

else
    echo "👋 Exiting."
fi
