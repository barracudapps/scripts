#!/bin/bash

################################################################################
# Script:       maintenance.sh
# Description:  Weekly check of the development Mac, in one report:
#               Homebrew (outdated packages, brew doctor), Mac health
#               (mac_health.sh: battery, backup, security, macOS updates),
#               Odoo environment (odoo_doctor.py), reclaimable disk space (disk_report.sh),
#               git repositories needing attention (git_status_all.sh).
#               Read-only unless --upgrade. A macOS notification is shown
#               only when something needs attention. The report is kept in
#               ~/Library/Logs/maintenance/.
# Usage:        bash maintenance.sh [--upgrade] [--quiet]
#               bash maintenance.sh --install [HH:MM] [DAY]  schedule it (launchd,
#                                                            default: Monday 09:00)
#               bash maintenance.sh --uninstall
#               --upgrade  also run brew upgrade (and brew cleanup)
#               --quiet    no terminal output, report file + notification only
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/Library/Logs/maintenance"
LABEL="com.barracudapps.maintenance"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# launchd starts with a minimal PATH
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/Applications/Postgres.app/Contents/Versions/latest/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

upgrade=false
quiet=false
case "${1:-}" in
    --install)
        time="${2:-09:00}"; day="${3:-1}"
        [[ "$time" =~ ^([0-9]{1,2}):([0-9]{2})$ ]] || { echo "Time must look like 09:00" >&2; exit 1; }
        hour=$((10#${BASH_REMATCH[1]})); minute=$((10#${BASH_REMATCH[2]}))
        mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"
        cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$SCRIPTS_DIR/maintenance.sh</string><string>--quiet</string></array>
    <key>StartCalendarInterval</key>
    <dict><key>Weekday</key><integer>$day</integer><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>
    <key>StandardErrorPath</key><string>$LOG_DIR/launchd.err</string>
</dict>
</plist>
EOF
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
        launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "Scheduled: day $day (1 = Monday) at $time. Remove with: $0 --uninstall"
        exit $? ;;
    --uninstall)
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
        rm -f "$PLIST" && echo "Unscheduled."
        exit 0 ;;
    -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
esac
for arg in "$@"; do
    case "$arg" in
        --upgrade) upgrade=true ;;
        --quiet) quiet=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

mkdir -p "$LOG_DIR"
report="$LOG_DIR/$(date +%Y-%m-%d_%H%M).log"
problems=()
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
out() { if $quiet; then cat >> "$report"; else tee -a "$report"; fi; }
section() { printf '\n== %s ==\n' "$1" | out; }

echo "Maintenance report $(date '+%Y-%m-%d %H:%M')" | out

section "Homebrew"
if command -v brew >/dev/null; then
    brew update --quiet >/dev/null 2>&1
    outdated=$(brew outdated --verbose 2>/dev/null)
    if [[ -n "$outdated" ]]; then
        count=$(wc -l <<<"$outdated" | tr -d ' ')
        echo "$count outdated package(s):" | out
        sed 's/^/  /' <<<"$outdated" | out
        if $upgrade; then
            brew upgrade 2>&1 | tail -n 5 | out
            brew cleanup --prune=30 >/dev/null 2>&1
        else
            problems+=("$count Homebrew update(s)")
        fi
    else
        echo "Everything is up to date." | out
    fi
    doctor=$(brew doctor 2>&1)
    if [[ "$doctor" != *"ready to brew"* ]]; then
        grep '^Warning' <<<"$doctor" | sed 's/^/  /' | out
        problems+=("brew doctor warnings")
    fi
else
    echo "Homebrew not found" | out
    problems+=("Homebrew missing")
fi

section "Odoo environment (odoo_doctor.py --quiet)"
doctor_out=$(python3 "$SCRIPTS_DIR/odoo_doctor.py" --quiet 2>&1 | strip)
doctor_rc=$?
grep -E '^  [!✗]|^/|^~|projet' <<<"$doctor_out" | out
(( doctor_rc != 0 )) && problems+=("Odoo: $(tail -n 1 <<<"$doctor_out")")

section "Mac health (mac_health.sh --quiet)"
health_out=$(bash "$SCRIPTS_DIR/mac_health.sh" --quiet 2>&1 | strip)
if [[ -n "$health_out" ]]; then
    echo "$health_out" | out
    while IFS= read -r line; do
        problems+=("${line#*  }")
    done < <(grep -E '^  (❌|⚠️)' <<<"$health_out" | sed 's/ → .*//; s/^  [^ ]* *//' | grep -v '^Disk ')
else
    echo "Everything is fine." | out
fi

section "Disk"
# "/" is the sealed system volume on macOS: user data lives on the Data volume
data_volume="/System/Volumes/Data"
[[ -d "$data_volume" ]] || data_volume="/"
free=$(df -H "$data_volume" | awk 'NR == 2 { print $4 " free (" $5 " used)" }')
echo "System disk: $free" | out
disk_total=$(bash "$SCRIPTS_DIR/disk_report.sh" 2>/dev/null | strip | grep 'Total récupérable' | sed 's/.*: //')
echo "Reclaimable (disk_report.sh): ${disk_total:-?}" | out
used_pct=$(df "$data_volume" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')
(( used_pct >= 85 )) && problems+=("disk ${used_pct}% used")

section "Git repositories (git_status_all.sh)"
git_out=$(bash "$SCRIPTS_DIR/git_status_all.sh" 2>&1 | strip)
echo "$git_out" | out
git_summary=$(tail -n 1 <<<"$git_out")
[[ "$git_summary" == *"need attention"* ]] && problems+=("git: ${git_summary%% (*}")

section "Summary"
if [[ ${#problems[@]} -eq 0 ]]; then
    echo "Nothing to report." | out
else
    printf '  - %s\n' "${problems[@]}" | out
    message=$(printf '%s; ' "${problems[@]}")
    osascript -e "display notification \"${message%; }\" with title \"Maintenance\" subtitle \"Report: $(basename "$report")\"" 2>/dev/null
fi
$quiet || echo "Report saved: $report"

# Keep the last 12 reports
ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +13 | while IFS= read -r old; do rm -f "$old"; done
