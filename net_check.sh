#!/bin/bash

################################################################################
# Script:       net_check.sh
# Description:  "Internet is slow: is it the Wi-Fi, the box or the Mac?"
#               Tests each link of the chain and gives a verdict in plain words:
#                 1. network connection and Wi-Fi signal quality
#                 2. the box / router (local gateway)
#                 3. Internet by IP address (no DNS)
#                 4. name resolution (DNS), compared with a public resolver
#                 5. web access and hotel/station login pages (captive portal)
#                 6. speed and responsiveness (networkQuality, built into macOS)
#               Read-only: changes nothing on the Mac.
# Usage:        bash net_check.sh [--quick]
#               --quick  skip the speed test (about 20 seconds)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -uo pipefail

quick=false
for arg in "$@"; do
    case "$arg" in
        --quick) quick=true ;;
        -h|--help) sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
    BOLD=""; DIM=""; NC=""
fi
OK="✅"; WARN="⚠️ "; KO="❌"
verdicts=()
step() { printf '\n%s%s%s\n' "$BOLD" "$1" "$NC"; }
say() { printf '  %s %s\n' "$1" "$2"; }

# ping_stats HOST -> "loss avg_ms" (loss in %, avg empty when nothing came back)
ping_stats() {
    local out loss avg
    out=$(ping -c 10 -i 0.2 -t 5 -q "$1" 2>/dev/null)
    loss=$(sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' <<<"$out")
    avg=$(sed -n 's|.*= [0-9.]*/\([0-9.]*\)/.*|\1|p' <<<"$out")
    avg=${avg%.*}
    echo "${loss:-100} ${avg:-}"
}

# ---------------------------------------------------------------- 1. connection
step "1. Connection"
route=$(route -n get default 2>/dev/null)
gateway=$(awk '/gateway:/ { print $2 }' <<<"$route")
interface=$(awk '/interface:/ { print $2 }' <<<"$route")
if [[ -z "$interface" ]]; then
    say "$KO" "No network connection (Wi-Fi off, cable unplugged or no network joined)."
    printf '\n%sVerdict:%s connect the Mac to a network first (Wi-Fi menu in the menu bar).\n' "$BOLD" "$NC"
    exit 1
fi
port=$(networksetup -listallhardwareports 2>/dev/null |
    awk -v dev="$interface" '/^Hardware Port:/ { sub(/^Hardware Port: /, ""); name = $0 } $2 == dev { print name; exit }')
port=${port:-$interface}
say "$OK" "Connected through $port ($interface)$( [[ -n "$gateway" ]] && echo ", box/router $gateway")"

wifi=false
if [[ "$port" == "Wi-Fi" || "$port" == "AirPort" ]]; then
    wifi=true
    info=$(system_profiler SPAirPortDataType 2>/dev/null | sed -n '/Current Network Information:/,/Other Local Wi-Fi Networks:/p')
    signal=$(sed -n 's/.*Signal \/ Noise: \(-[0-9]*\) dBm.*/\1/p' <<<"$info" | head -n 1)
    noise=$(sed -n 's/.*Signal \/ Noise: -[0-9]* dBm \/ \(-[0-9]*\) dBm.*/\1/p' <<<"$info" | head -n 1)
    channel=$(sed -n 's/.*Channel: \(.*\)/\1/p' <<<"$info" | head -n 1)
    rate=$(sed -n 's/.*Transmit Rate: \([0-9]*\).*/\1/p' <<<"$info" | head -n 1)
    phy=$(sed -n 's/.*PHY Mode: \(.*\)/\1/p' <<<"$info" | head -n 1)
    if [[ -n "$signal" ]]; then
        detail="signal $signal dBm, noise ${noise:-?} dBm, channel ${channel:-?}, ${phy:-?}, link ${rate:-?} Mbit/s"
        if (( signal >= -60 )); then
            say "$OK" "Wi-Fi signal good ($detail)"
        elif (( signal >= -70 )); then
            say "$WARN" "Wi-Fi signal average ($detail)"
            verdicts+=("The Wi-Fi signal is average: move closer to the box or remove obstacles (walls, microwave).")
        else
            say "$KO" "Wi-Fi signal weak ($detail)"
            verdicts+=("The Wi-Fi signal is weak: move closer to the box, or use a cable or a Wi-Fi repeater.")
        fi
        if [[ "$channel" == *2GHz* ]]; then
            say "$WARN" "Connected on 2.4 GHz: slower and more crowded than 5 GHz"
            verdicts+=("The Mac uses the 2.4 GHz band: if the box offers a 5 GHz network, join it when close to the box.")
        fi
    fi
fi

# ---------------------------------------------------------------- 2. box
step "2. Box / router"
gateway_ok=unknown
if [[ -n "$gateway" ]]; then
    read -r loss avg <<<"$(ping_stats "$gateway")"
    if [[ -z "$avg" ]]; then
        gateway_ok=no
        say "$DIM-$NC" "The box does not answer ping ${DIM}(many boxes ignore it: checked again below)${NC}"
    elif [[ "${loss%.*}" -gt 0 ]]; then
        gateway_ok=lossy
        say "$WARN" "The box answers, but ${loss}% of the packets are lost (average ${avg} ms)"
    elif $wifi && [[ "${avg%.*}" -ge 20 ]]; then
        gateway_ok=slow
        say "$WARN" "The box answers slowly over Wi-Fi: ${avg} ms (expected < 10 ms)"
    else
        gateway_ok=yes
        say "$OK" "The box answers in ${avg} ms"
    fi
else
    say "$DIM-$NC" "No local gateway (VPN or tethering?)"
fi

# ---------------------------------------------------------------- 3. internet by IP
step "3. Internet (by IP address)"
read -r loss1 avg1 <<<"$(ping_stats 1.1.1.1)"
read -r loss2 avg2 <<<"$(ping_stats 8.8.8.8)"
internet_ok=yes
if [[ -z "$avg1" && -z "$avg2" ]]; then
    internet_ok=no
    say "$KO" "Internet does not answer (Cloudflare 1.1.1.1 and Google 8.8.8.8 unreachable)"
else
    best_loss=$loss1; best_avg=$avg1
    [[ -z "$avg1" || ( -n "$avg2" && "${loss2%.*}" -lt "${loss1%.*}" ) ]] && best_loss=$loss2 && best_avg=$avg2
    if [[ "${best_loss%.*}" -gt 0 ]]; then
        internet_ok=lossy
        say "$WARN" "Internet answers, but ${best_loss}% of the packets are lost (average ${best_avg} ms)"
    elif [[ "${best_avg%.*}" -ge 80 ]]; then
        internet_ok=slow
        say "$WARN" "Internet answers slowly: ${best_avg} ms (expected < 40 ms)"
    else
        say "$OK" "Internet answers in ${best_avg} ms"
    fi
fi
[[ "$gateway_ok" == "no" && "$internet_ok" != "no" ]] && say "$DIM-$NC" "${DIM}(so the box works, it just ignores ping)${NC}"

# ---------------------------------------------------------------- 4. DNS
step "4. Name resolution (DNS)"
dns_time() {   # dns_time [@server] -> query time in ms, empty on failure
    dig +tries=1 +time=3 "$@" apple.com 2>/dev/null |
        awk '/status:/ { ok = ($0 ~ /NOERROR/) } /Query time:/ { if (ok) print $4 }'
}
dns_server=$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/ { print $3; exit }')
system_dns=$(dns_time)
public_dns=$(dns_time @1.1.1.1)
dns_ok=yes
if [[ -z "$system_dns" ]]; then
    dns_ok=no
    if [[ -n "$public_dns" ]]; then
        say "$KO" "The DNS server ${dns_server:-of the network} does not answer, a public one does"
    else
        say "$KO" "No DNS server answers"
    fi
elif [[ "$system_dns" -ge 150 ]]; then
    dns_ok=slow
    say "$WARN" "DNS answers slowly: ${system_dns} ms via ${dns_server:-?} (public resolver: ${public_dns:-?} ms)"
else
    say "$OK" "DNS answers in ${system_dns} ms via ${dns_server:-?}"
fi

# ---------------------------------------------------------------- 5. web
step "5. Web access"
web_ok=yes
page=$(curl -s -m 8 http://captive.apple.com/hotspot-detect.html 2>/dev/null)
if [[ "$page" == *Success* ]]; then
    https_time=$(curl -s -o /dev/null -m 10 -w '%{time_total}' https://www.apple.com/ 2>/dev/null)
    if [[ -n "$https_time" && "$https_time" != "0.000000" ]]; then
        say "$OK" "Websites open (apple.com in ${https_time%???}s)"
    else
        web_ok=https
        say "$WARN" "Plain web works but secure sites (https) fail"
    fi
elif [[ -n "$page" ]]; then
    web_ok=captive
    say "$KO" "A login page intercepts the traffic (hotel, train station, public Wi-Fi)"
else
    web_ok=no
    say "$KO" "Websites do not open"
fi

# ---------------------------------------------------------------- 6. speed
download=""; upload=""; rpm=""
if ! $quick && [[ "$internet_ok" != "no" && "$web_ok" == "yes" ]]; then
    step "6. Speed (about 20 seconds)"
    json=$(networkQuality -c -M 20 2>/dev/null)
    read -r download upload rpm <<<"$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except ValueError:
    data = {}
def mbit(key):
    value = data.get(key)
    return f"{value / 1e6:.0f}" if isinstance(value, (int, float)) and value > 0 else "-"
rpm = data.get("responsiveness") or data.get("dl_responsiveness")
print(mbit("dl_throughput"), mbit("ul_throughput"), f"{rpm:.0f}" if isinstance(rpm, (int, float)) else "-")
' <<<"$json")"
    if [[ "$download" == "-" || -z "$download" ]]; then
        say "$WARN" "Speed test failed (Apple test servers unreachable or VPN)"
    else
        mark="$OK"
        (( download < 10 )) && mark="$WARN" && verdicts+=("Download speed is low (${download} Mbit/s): fine for mail and web, short for video calls and streaming.")
        say "$mark" "Download ${download} Mbit/s, upload ${upload} Mbit/s"
        if [[ "$rpm" != "-" ]]; then
            if (( rpm < 200 )); then
                say "$WARN" "Responsiveness ${rpm} RPM: the connection lags under load (video calls may freeze)"
                verdicts+=("The connection lags when busy: pause big downloads, backups or other devices streaming.")
            else
                say "$OK" "Responsiveness ${rpm} RPM"
            fi
        fi
    fi
fi

# ---------------------------------------------------------------- verdict
printf '\n%sVerdict%s\n' "$BOLD" "$NC"
main=""
if [[ "$internet_ok" == "no" ]]; then
    if [[ "$gateway_ok" == "no" ]]; then
        main="Neither the box nor Internet answer: restart the box (unplug 30 seconds), then reconnect the Wi-Fi."
    else
        main="The Mac reaches the box but the box has no Internet: restart the box; if it persists, the problem is on the provider's side (check its outage page from your phone)."
    fi
elif [[ "$web_ok" == "captive" ]]; then
    main="Open Safari on any page and fill in the Wi-Fi login page."
elif [[ "$dns_ok" == "no" ]]; then
    main="Internet works but names (websites) are not resolved: restart the box, or set the DNS to 1.1.1.1 in System Settings > Network > Details > DNS."
elif [[ "$web_ok" != "yes" ]]; then
    main="Internet answers but websites do not open: check a VPN, a firewall or a security app (antivirus, parental control)."
elif [[ "$gateway_ok" == "lossy" || "$gateway_ok" == "slow" ]] && $wifi; then
    main="The weak link is the Wi-Fi between the Mac and the box."
elif [[ "$internet_ok" == "lossy" || "$internet_ok" == "slow" ]]; then
    main="The box is fine but the Internet line is unstable or slow: restart the box; if it persists, contact the provider."
elif [[ "$dns_ok" == "slow" ]]; then
    main="Everything works, but websites start slowly because of the DNS: use 1.1.1.1 (System Settings > Network > Details > DNS)."
fi
if [[ -z "$main" && ${#verdicts[@]} -eq 0 ]]; then
    printf '  %s The connection looks healthy. If one site or app is slow, the problem is probably on its side.\n' "$OK"
else
    [[ -n "$main" ]] && printf '  ➜ %s\n' "$main"
    for line in "${verdicts[@]+"${verdicts[@]}"}"; do printf '  • %s\n' "$line"; done
fi
