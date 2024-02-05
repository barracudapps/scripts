#!/bin/bash

################################################################################
# Script: rmDSStore.sh
# Description: Removes .DS_STORE files recursively in the current directory.
# Usage: sh ~/Documents/scripts/rmDSStore.sh
# Author: Pierre LAMOTTE
# Date: 05 FEB 2024
################################################################################

# Current directory path
current_dir=$(pwd)

# Counter for deleted .DS_Store files
count_deleted=0

# .DS_Store files removal
for file in $(find "$current_dir" -type f -name .DS_Store); do
    echo "Deleted: $file"
    rm "$file"
    ((count_deleted++))
done

# Display the number of .DS_Store files deletes
echo ".DS_Store removal finished. Number of deleted files : $count_deleted"
