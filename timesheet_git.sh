#!/bin/bash

################################################################################
# Script:       timesheet_git.sh
# Description:  Estimates the time spent per day and per client from your own
#               commits in all the git repositories (client folders and
#               ~/Documents), to help filling timesheets and invoices.
#               Commits less than 2 hours apart form a work session; each
#               session counts from its first to its last commit, plus 30 min
#               for the work done before the first commit.
# Usage:        bash timesheet_git.sh [--since DATE] [--until DATE] [--client TXT]
#                                     [--details] [--csv] [--author REGEX]
#               --since/--until  any git date ("2026-11-01", "last monday"...);
#                                default: since the 1st of the current month
#               --client TXT     only the clients/projects containing TXT
#               --details        list the commit messages of each day
#               --csv            CSV output (date;client;sessions;commits;hours)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

CLIENTS_DIR="$HOME/Desktop/Indépendant BApps/Clients"
ROOTS=("$CLIENTS_DIR" "$HOME/Documents")

since="$(date +%Y-%m-01)"
until="now"
client_filter=""
details=false
csv=false
author=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) since="$2"; shift 2 ;;
        --until) until="$2"; shift 2 ;;
        --client) client_filter="$2"; shift 2 ;;
        --details) details=true; shift ;;
        --csv) csv=true; shift ;;
        --author) author="$2"; shift 2 ;;
        -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$author" ]]; then
    name=$(git config --global user.name || true)
    email=$(git config --global user.email || true)
    author="${name}${email:+|$email}"
fi
[[ -n "$author" ]] || { echo "No git identity: use --author" >&2; exit 1; }

# git filters on the commit date; the report uses the author date (rebased
# commits keep it), so both bounds are applied again on the author date
since_epoch=$(git rev-parse --since="$since" | sed 's/^--max-age=//')
until_epoch=$(git rev-parse --until="$until" | sed 's/^--min-age=//')

# One line per commit: epoch, label (client/project), repo, subject
collect() {
    find "${ROOTS[@]}" -maxdepth 6 -name .git \( -type d -o -type f \) \
        -not -path '*/Odoo/versions/*' -not -path '*/_repos/*' -not -path '*/flutter/bin/*' \
        -not -path '*/node_modules/*' -prune 2>/dev/null |
    while IFS= read -r gitdir; do
        repo=$(dirname "$gitdir")
        case "$repo" in
            "$CLIENTS_DIR"/*) rel="${repo#"$CLIENTS_DIR"/}"; label=$(cut -d/ -f1-2 <<<"$rel") ;;
            *) label="Documents/$(basename "$repo")" ;;
        esac
        git -C "$repo" log --all --no-merges -E -i --author="$author" \
            --since="$since" --format="%at%x09$label%x09$repo%x09%s" 2>/dev/null || true
    done
}

collect | python3 -c '
import sys
from collections import defaultdict
from datetime import datetime

GAP, LEAD = 2 * 3600, 30 * 60
client_filter, details, csv = sys.argv[1].lower(), sys.argv[2] == "true", sys.argv[3] == "true"
since_epoch, until_epoch = int(sys.argv[4]), int(sys.argv[5])
commits = set()
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t", 3)
    if len(parts) == 4 and client_filter in parts[1].lower() and since_epoch <= int(parts[0]) <= until_epoch:
        commits.add((int(parts[0]), parts[1], parts[3]))   # set: same commit seen in several branches

days = defaultdict(list)
for ts, label, subject in sorted(commits):
    days[(datetime.fromtimestamp(ts).strftime("%Y-%m-%d"), label)].append((ts, subject))

rows, totals = [], defaultdict(float)
for (day, label), items in sorted(days.items()):
    sessions, start, last = [], items[0][0], items[0][0]
    for ts, _ in items[1:]:
        if ts - last > GAP:
            sessions.append((start, last)); start = ts
        last = ts
    sessions.append((start, last))
    hours = sum(end - begin + LEAD for begin, end in sessions) / 3600
    rows.append((day, label, len(sessions), len(items), hours, [s for _, s in items]))
    totals[label] += hours

if csv:
    print("date;client;sessions;commits;hours")
    for day, label, n_sessions, n_commits, hours, _ in rows:
        print(f"{day};{label};{n_sessions};{n_commits};{hours:.2f}".replace(".", ","))
    sys.exit()

if not rows:
    print("No commit found for this period.")
    sys.exit()
current_day = None
for day, label, n_sessions, n_commits, hours, subjects in rows:
    if day != current_day:
        weekday = datetime.strptime(day, "%Y-%m-%d").strftime("%a")
        print(f"\n{weekday} {day}")
        current_day = day
    print(f"  {hours:5.1f} h  {label:<34} {n_commits:3d} commit(s), {n_sessions} session(s)")
    if details:
        for subject in subjects:
            print(f"           - {subject[:90]}")
print("\nTotal per client (estimate):")
for label, hours in sorted(totals.items(), key=lambda x: -x[1]):
    print(f"  {hours:6.1f} h  {label}")
print(f"  {sum(totals.values()):6.1f} h  TOTAL")
' "$client_filter" "$details" "$csv" "$since_epoch" "$until_epoch"
