#!/bin/bash

################################################################################
# Script: rmDSStore.sh
# Description: Removes .DS_Store files recursively in a directory
#              (current directory by default). Safe with spaces in paths.
# Usage: bash ~/Documents/scripts/rmDSStore.sh [directory] [--dry-run]
# Author: Pierre LAMOTTE
# Date: 05 FEB 2024
################################################################################

target_dir="."
dry_run=false

for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) dry_run=true ;;
        -h|--help)
            echo "Usage: $0 [directory] [--dry-run]"
            exit 0 ;;
        *) target_dir="$arg" ;;
    esac
done

if [[ ! -d "$target_dir" ]]; then
    echo "The directory does not exist: $target_dir" >&2
    exit 1
fi

count=0
while IFS= read -r -d '' file; do
    if $dry_run; then
        echo "Would delete: $file"
    else
        rm -f "$file" && echo "Deleted: $file"
    fi
    count=$((count + 1))
done < <(find "$target_dir" -type f -name .DS_Store -print0 2>/dev/null)

if $dry_run; then
    echo "Dry run finished. Number of .DS_Store files found: $count"
else
    echo ".DS_Store removal finished. Number of deleted files: $count"
fi
