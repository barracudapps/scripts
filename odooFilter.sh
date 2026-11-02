#!/bin/bash

################################################################################
# Script:       odooFilter.sh
# Description:  Generates an Odoo domain with multiple OR conditions for
#               filtering records based on a list of terms. The domain is
#               formatted to be directly usable in Odoo's interface (custom
#               filter / domain editor). Copied to the clipboard on macOS.
# Usage:        bash odooFilter.sh [-f field] [-o operator] [-p] term1 term2 ...
#               bash odooFilter.sh [-f field] [-p] < terms.txt  (one term per line)
#               Defaults: field=partner_ids.name, operator=ilike
#               -p wraps each term in parentheses, e.g. codes like "Name (ABCD)"
# Author:       Pierre LAMOTTE
# Date:         02 JAN 2025
################################################################################

field="partner_ids.name"
operator="ilike"
wrap=false

usage() {
    echo "Usage: $0 [-f field] [-o operator] [-p] term1 term2 ..."
    echo "       $0 [-f field] [-o operator] [-p] < terms.txt"
    echo "  -p  wrap each term in parentheses (match codes like \"Name (ABCD)\")"
}

while getopts ":f:o:ph" opt; do
    case "$opt" in
        f) field="$OPTARG" ;;
        o) operator="$OPTARG" ;;
        p) wrap=true ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

terms=("$@")
# No term given as argument: read them from stdin (one per line)
if [[ ${#terms[@]} -eq 0 && ! -t 0 ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "${line// /}" ]] && terms+=("$line")
    done
fi

if [[ ${#terms[@]} -eq 0 ]]; then
    usage >&2
    exit 1
fi

# Escape backslashes and double quotes so the domain stays valid
escape() {
    local value="${1//\\/\\\\}"
    printf '%s' "${value//\"/\\\"}"
}

domain=""
# Odoo uses prefix notation: n terms need n-1 "|" operators
for ((i = 1; i < ${#terms[@]}; i++)); do
    domain+="\"|\", "
done
for term in "${terms[@]}"; do
    $wrap && term="($term)"
    domain+="(\"$(escape "$field")\", \"$(escape "$operator")\", \"$(escape "$term")\"), "
done
domain="[${domain%, }]"

echo "$domain"
if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$domain" | pbcopy
    echo "(copied to clipboard)" >&2
fi
