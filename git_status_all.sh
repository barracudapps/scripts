#!/bin/bash

################################################################################
# Script:       git_status_all.sh
# Description:  End-of-day check of all the git repositories (client folders
#               and ~/Documents): uncommitted changes, untracked files, commits
#               not pushed or not pulled, stashes, branches without upstream.
#               Only the repositories needing attention are shown.
# Usage:        bash git_status_all.sh [--fetch] [--all]
#               --fetch  update the remote branches first (network)
#               --all    also show the clean repositories
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -uo pipefail

ROOTS=("$HOME/Desktop/Indépendant BApps/Clients" "$HOME/Documents")
fetch=false
show_all=false
for arg in "$@"; do
    case "$arg" in
        --fetch) fetch=true ;;
        --all) show_all=true ;;
        -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

RED=$'\033[91m'; YELLOW=$'\033[93m'; GREEN=$'\033[92m'; DIM=$'\033[2m'; NC=$'\033[0m'
attention=0
total=0

while IFS= read -r gitdir; do
    repo=$(dirname "$gitdir")
    total=$((total + 1))
    $fetch && git -C "$repo" fetch --quiet --all --prune 2>/dev/null

    branch=$(git -C "$repo" symbolic-ref --short -q HEAD || echo "(detached)")
    porcelain=$(git -C "$repo" status --porcelain 2>/dev/null)
    changed=$(grep -cv '^??' <<<"$porcelain" || true)
    untracked=$(grep -c '^??' <<<"$porcelain" || true)
    [[ -z "$porcelain" ]] && changed=0 && untracked=0
    stashes=$(git -C "$repo" stash list 2>/dev/null | wc -l | tr -d ' ')

    issues=()
    (( changed > 0 )) && issues+=("${RED}$changed modified${NC}")
    (( untracked > 0 )) && issues+=("${YELLOW}$untracked untracked${NC}")
    if git -C "$repo" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
        read -r behind ahead < <(git -C "$repo" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
        (( ahead > 0 )) && issues+=("${RED}$ahead to push${NC}")
        (( behind > 0 )) && issues+=("${YELLOW}$behind to pull${NC}")
    elif [[ "$branch" != "(detached)" ]] && git -C "$repo" remote | grep -q .; then
        issues+=("${YELLOW}no upstream${NC}")
    fi
    (( stashes > 0 )) && issues+=("${DIM}$stashes stash(es)${NC}")

    if [[ ${#issues[@]} -gt 0 ]]; then
        attention=$((attention + 1))
        printf '%s  %s\n' "${repo/#$HOME/\~}" "${DIM}[$branch]${NC}"
        printf '    %s\n' "$(IFS=,; echo "${issues[*]}" | sed 's/,/, /g')"
    elif $show_all; then
        printf '%s  %s  %s\n' "${repo/#$HOME/\~}" "${DIM}[$branch]${NC}" "${GREEN}clean${NC}"
    fi
done < <(find "${ROOTS[@]}" -maxdepth 6 -name .git \( -type d -o -type f \) \
    -not -path '*/Odoo/versions/*' -not -path '*/_repos/*' -not -path '*/flutter/bin/*' \
    -not -path '*/node_modules/*' -prune 2>/dev/null | sort)

echo ""
if (( attention == 0 )); then
    echo "${GREEN}All $total repositories are clean and in sync.${NC}"
else
    echo "$attention/$total repositories need attention.$($fetch || echo " (run with --fetch to compare with the remotes)")"
fi
