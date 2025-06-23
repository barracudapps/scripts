#!/bin/bash

################################################################################
# Script: 	accessOdooFilestore.sh
# Description: 	Locate and open the Odoo 'filestore' directory for a given DB name.
# Usage: 	sh ~/Documents/scripts/accessOdooFilestore.sh [db_name]
# Author: 	Pierre LAMOTTE
# Date: 	23 JUN 2025
################################################################################

# Get database name from argument
db_name="$1"

# Check for argument
if [ -z "$db_name" ]; then
    echo "❌ Error: No database name provided."
    echo "Usage: sh goToFilestore.sh [db_name]"
    exit 1
fi

# Initialize empty filestore base path
filestore_base=""

# Detect OS
os_name=$(uname)

# --- macOS-specific search ---
if [[ "$os_name" == "Darwin" ]]; then
    echo "🖥️ Detected macOS – scanning Application Support for Odoo..."
    
    mac_path="$HOME/Library/Application Support/Odoo"
    
    # Check if directory exists
    if [ -d "$mac_path" ]; then
        # Try to find 'filestore' inside
        filestore_base=$(find "$mac_path" -type d -name filestore -maxdepth 3 -print 2>/dev/null | head -n 1)
    fi
fi

# --- If not found, fallback to standard ~/.local/share path ---
if [ -z "$filestore_base" ]; then
    echo "🔍 Falling back to ~/.local/share/Odoo/filestore..."
    alt_path="$HOME/.local/share/Odoo/filestore"
    if [ -d "$alt_path" ]; then
        filestore_base="$alt_path"
    fi
fi

# --- If still not found, try scanning home ---
if [ -z "$filestore_base" ]; then
    echo "⏳ Scanning ~ for 'filestore' directory... (may be slow)"
    filestore_base=$(find "$HOME" -type d -name filestore -print 2>/dev/null | head -n 1)
fi

# --- Still not found ---
if [ -z "$filestore_base" ]; then
    echo "❌ Could not locate any 'filestore' directory."
    exit 2
fi

# Final DB filestore path
filestore_path="$filestore_base/$db_name"

# --- Check if DB filestore exists ---
if [ -d "$filestore_path" ]; then
    echo "✅ Filestore found for DB '$db_name':"
    echo "$filestore_path"
    echo ""

    echo "What would you like to do?"
    echo "  [1] Open in Terminal"
    echo "  [2] Open in Finder"
    echo "  [3] Quit"
    read -p "Enter your choice [1/2/3]: " user_choice

    case "$user_choice" in
        1)
            echo "Opening in Terminal..."
            open -a Terminal "$filestore_path"
            ;;
        2)
            echo "Opening in Finder..."
            open "$filestore_path"
            ;;
        *)
            echo "Exiting without opening."
            ;;
    esac
else
    echo "❌ Filestore not found for database: $db_name"
    echo "Searched path: $filestore_path"
    exit 3
fi
