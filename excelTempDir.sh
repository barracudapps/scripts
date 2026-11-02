#!/bin/bash

################################################################################
# Script: excelTempDir.sh
# Description: Opens Excel's temporary directory in Finder
# Usage: bash ~/Documents/scripts/excelTempDir.sh
# Author: Pierre LAMOTTE
# Date: 05 FEB 2024
################################################################################

excel_tmp="${TMPDIR:?TMPDIR is not set}/spool/visu"

if [[ ! -d "$excel_tmp" ]]; then
    echo "Excel's temporary directory does not exist (yet): $excel_tmp" >&2
    echo "Opening the parent temporary directory instead." >&2
    excel_tmp="$TMPDIR"
fi

open "$excel_tmp"
