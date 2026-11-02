#!/bin/bash

################################################################################
# Script:       mac_health.sh
# Description:  One-page health check of the Mac, with a score:
#                 battery     cycles, maximum capacity, condition
#                 backup      Time Machine configured and recent (< 7 days)
#                 storage     free space on the data volume, disk SMART status
#                 security    FileVault, firewall, SIP, Gatekeeper, automatic
#                             security updates
#                 updates     pending macOS updates (network, ~20 s)
#                 system      uptime (restart advised after 2 weeks), memory
#                             pressure
#               Read-only, no administrator needed. Exit code 1 when
#               something needs attention.
# Usage:        bash mac_health.sh [--quick] [--quiet]
#               --quick  skip the macOS update check
#               --quiet  only print the items needing attention (used by
#                        maintenance.sh)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -uo pipefail

quick=false
quiet=false
for arg in "$@"; do
    case "$arg" in
        --quick) quick=true ;;
        --quiet) quiet=true ;;
        -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [[ -t 1 ]]; then BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'; else BOLD=""; DIM=""; NC=""; fi
checks=0
passed=0
problems=()
section() { $quiet || printf '\n%s%s%s\n' "$BOLD" "$1" "$NC"; }
good() { checks=$((checks + 1)); passed=$((passed + 1)); $quiet || printf '  ✅ %s\n' "$1"; }
warn() { checks=$((checks + 1)); problems+=("$1"); printf '  ⚠️  %s\n' "$1${2:+ ${DIM}→ $2${NC}}"; }
bad() { checks=$((checks + 1)); problems+=("$1"); printf '  ❌ %s\n' "$1${2:+ ${DIM}→ $2${NC}}"; }
info() { $quiet || printf '  ·  %s\n' "$1"; }

$quiet || printf '%sMac health check%s  %s%s, macOS %s%s\n' "$BOLD" "$NC" "$DIM" \
    "$(sysctl -n hw.model)" "$(sw_vers -productVersion)" "$NC"

# ---------------------------------------------------------------- battery
battery=$(ioreg -rn AppleSmartBattery 2>/dev/null)
if [[ -n "$battery" ]]; then
    section "🔋 Battery"
    cycles=$(sed -n 's/.*"CycleCount" = \([0-9]*\).*/\1/p' <<<"$battery" | head -n 1)
    design=$(sed -n 's/.*"DesignCapacity"=\([0-9]*\).*/\1/p' <<<"$battery" | head -n 1)
    raw_max=$(sed -n 's/.*"AppleRawMaxCapacity"=\([0-9]*\).*/\1/p' <<<"$battery" | head -n 1)
    condition=$(system_profiler SPPowerDataType 2>/dev/null | sed -n 's/.*Condition: //p' | head -n 1)
    health=$(system_profiler SPPowerDataType 2>/dev/null | sed -n 's/.*Maximum Capacity: \([0-9]*\).*/\1/p' | head -n 1)
    if [[ -z "$health" && -n "$design" && -n "$raw_max" && "$design" -gt 0 ]]; then
        health=$((raw_max * 100 / design))
    fi
    if [[ -n "$health" ]]; then
        if (( health >= 80 )); then
            good "Maximum capacity ${health}% (${cycles:-?} cycles)"
        else
            warn "Maximum capacity ${health}% (${cycles:-?} cycles)" "below 80%: autonomy reduced, a replacement can be worth it"
        fi
    fi
    if [[ -n "$condition" && "$condition" != "Normal" ]]; then
        bad "Battery condition: $condition" "have the battery checked"
    elif [[ -n "$condition" ]]; then
        good "Battery condition normal"
    fi
fi

# ---------------------------------------------------------------- backup
section "💾 Backup"
destinations=$(tmutil destinationinfo 2>&1)
if [[ "$destinations" == *"No destinations"* ]]; then
    bad "No Time Machine backup configured" "plug an external disk and enable it in System Settings > General > Time Machine"
else
    latest=$(tmutil latestbackup 2>/dev/null | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{6\}' | tail -n 1)
    if [[ -z "$latest" ]]; then
        # The disk may be unplugged: the last date is still known from the preferences
        latest=$(defaults read /Library/Preferences/com.apple.TimeMachine 2>/dev/null |
            grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9:]\{8\}' | sort | tail -n 1 | tr ' :' '--' | tr -d ':')
    fi
    if [[ -z "$latest" ]]; then
        warn "Time Machine configured, last backup date unknown" "plug the backup disk, or give Full Disk Access to the terminal"
    else
        latest_day=${latest:0:10}
        age=$(( ( $(date +%s) - $(date -j -f %Y-%m-%d "$latest_day" +%s) ) / 86400 ))
        if (( age <= 7 )); then
            good "Last Time Machine backup: $latest_day ($age day(s) ago)"
        else
            warn "Last Time Machine backup: $latest_day ($age days ago)" "plug the backup disk"
        fi
    fi
fi

# ---------------------------------------------------------------- storage
section "🗄  Storage"
volume="/System/Volumes/Data"
[[ -d "$volume" ]] || volume="/"
read -r size used avail pct <<<"$(df -H "$volume" | awk 'NR == 2 { print $2, $3, $4, $5 }')"
pct=${pct%\%}
if (( pct >= 90 )); then
    bad "Disk ${pct}% full (${avail} free of ${size})" "free space: forgotten_files.py, duplicates.py"
elif (( pct >= 80 )); then
    warn "Disk ${pct}% full (${avail} free of ${size})" "macOS slows down when the disk is nearly full"
else
    good "Disk ${pct}% full (${avail} free of ${size})"
fi
smart=$(diskutil info disk0 2>/dev/null | sed -n 's/.*SMART Status: *//p')
if [[ "$smart" == "Verified" ]]; then
    good "Internal disk SMART status verified"
elif [[ -n "$smart" && "$smart" != "Not Supported" ]]; then
    bad "Internal disk SMART status: $smart" "back up now and have the disk checked"
fi

# ---------------------------------------------------------------- security
section "🔒 Security"
if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
    good "FileVault on (disk encrypted)"
else
    warn "FileVault off" "a stolen Mac gives access to all files: System Settings > Privacy & Security > FileVault"
fi
if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
    good "Firewall on"
else
    warn "Firewall off" "System Settings > Network > Firewall"
fi
if csrutil status 2>/dev/null | grep -q "enabled"; then
    good "System Integrity Protection on"
else
    bad "System Integrity Protection off" "only for specific development needs: re-enable it from recovery mode"
fi
if spctl --status 2>/dev/null | grep -q "enabled"; then
    good "Gatekeeper on (only checked apps open)"
else
    bad "Gatekeeper off" "sudo spctl --global-enable"
fi
critical=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null)
if [[ "$critical" == "0" ]]; then
    warn "Automatic security responses off" "System Settings > General > Software Update > Automatic updates"
else
    good "Security responses installed automatically"
fi

# ---------------------------------------------------------------- updates
if ! $quick; then
    section "⬆️  Updates"
    updates=$(softwareupdate -l 2>&1)
    pending=$(grep -c '^\* Label:' <<<"$updates" || true)
    if (( pending > 0 )); then
        warn "$pending macOS update(s) pending" "System Settings > General > Software Update"
        $quiet || grep '^\* Label:' <<<"$updates" | sed 's/^\* Label: /       /'
    elif grep -q "No new software available" <<<"$updates"; then
        good "macOS is up to date"
    else
        info "Update check failed (offline?)"
    fi
fi

# ---------------------------------------------------------------- system
section "⚙️  System"
boot=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
days=$(( ( $(date +%s) - boot ) / 86400 ))
if (( days >= 14 )); then
    warn "Running for $days days without restart" "a restart installs pending fixes and frees memory"
else
    good "Restarted $days day(s) ago"
fi
free_mem=$(memory_pressure 2>/dev/null | sed -n 's/.*free percentage: \([0-9]*\)%.*/\1/p')
if [[ -n "$free_mem" ]]; then
    if (( free_mem < 15 )); then
        warn "Memory under pressure (${free_mem}% free)" "close unused apps and browser tabs"
    else
        good "Memory OK (${free_mem}% free)"
    fi
fi

# ---------------------------------------------------------------- score
score=$(( checks > 0 ? passed * 100 / checks : 100 ))
if (( score >= 90 )); then mood="🟢 Great shape"; elif (( score >= 70 )); then mood="🟡 Good, a few things to do"; else mood="🔴 Needs care"; fi
if ! $quiet || [[ ${#problems[@]} -gt 0 ]]; then
    printf '\n%sScore: %d/100%s  %s  (%d/%d checks passed)\n' "$BOLD" "$score" "$NC" "$mood" "$passed" "$checks"
fi
[[ ${#problems[@]} -eq 0 ]]
