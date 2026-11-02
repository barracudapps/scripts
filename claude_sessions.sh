#!/bin/bash

################################################################################
# Script:       claude_sessions.sh
# Description:  Talks to every Claude Code session running in a terminal
#               (Terminal.app or iTerm2): list them, ask them to save their
#               context and memory for a later resumption (optionally followed
#               by /compact), ask them to reload it, or send any message.
#               Text is typed into a session only while it is idle, never while
#               it works or shows a question / permission prompt. The session
#               running this script is always skipped.
# Usage:        bash claude_sessions.sh list
#               bash claude_sessions.sh save [--compact] [--wait] [--dry-run]
#               bash claude_sessions.sh reload [--wait] [--dry-run]
#               bash claude_sessions.sh compact [--wait] [--dry-run]
#               bash claude_sessions.sh send "message" [--wait] [--dry-run]
#               --wait      wait (up to 30 min) for busy sessions to become idle
#               --only TXT  only the sessions whose name or folder contains TXT
# Notes:        The first use asks macOS to let the terminal control
#               Terminal/iTerm (System Settings > Privacy > Automation).
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -uo pipefail

SAVE_PROMPT="Mets à jour ton contexte et ta mémoire pour une reprise ultérieure dans une nouvelle conversation, sans régression : décisions prises, état d'avancement, points en attente, pièges rencontrés et vérifications à refaire. Ne supprime que ce qui est périmé ou faux, et vérifie le résultat."
RELOAD_PROMPT="Relis ton contexte et ta mémoire (CLAUDE.md, fichiers de mémoire), puis vérifie l'état réel du projet avant de continuer, et résume-moi où on en est."
WAIT_TIMEOUT=1800
POLL=5

fatal() { echo "[ERROR] $*" >&2; exit 1; }
usage() { sed -n '/^# Usage:/,/^# Notes:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

command -v claude >/dev/null || fatal "claude CLI not found"
command="${1:-list}"
[[ $# -gt 0 ]] && shift
message=""
compact=false
wait_idle=false
dry_run=false
only=""
case "$command" in
    list|save|reload|compact) ;;
    send) [[ $# -ge 1 ]] || fatal "send needs a message"; message="$1"; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac
while [[ $# -gt 0 ]]; do
    case "$1" in
        --compact) compact=true; shift ;;
        --wait) wait_idle=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        --only) only="$2"; shift 2 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done
[[ "$command" == "save" ]] && message="$SAVE_PROMPT"
[[ "$command" == "reload" ]] && message="$RELOAD_PROMPT"
[[ "$command" == "compact" ]] && message="/compact"

# Sessions as TAB-separated lines: pid, kind, status, name, cwd, short id
sessions() {
    claude agents --json 2>/dev/null | python3 -c '
import json, sys
for s in json.load(sys.stdin):
    status = s.get("status") or s.get("state") or "?"
    print("\t".join(str(x) for x in (s.get("pid", "-"), s.get("kind", "?"), status, s.get("name", "?"), s.get("cwd", "?"), s.get("id", "-"))))
'
}

status_of() { sessions | awk -F'\t' -v pid="$1" '$1 == pid { print $3 }'; }

# Pids of this script's ancestors: the calling Claude session must be skipped
ancestors=" "
p=$$
while [[ -n "$p" && "$p" -gt 1 ]]; do ancestors+="$p "; p=$(ps -o ppid= -p "$p" | tr -d ' '); done

# Terminal application hosting a process (Terminal, iTerm2, or other)
terminal_app() {
    local p="$1" comm
    while [[ -n "$p" && "$p" -gt 1 ]]; do
        comm=$(ps -o comm= -p "$p")
        case "$comm" in
            */Terminal.app/*) echo "Terminal"; return ;;
            */iTerm.app/*|*iTerm2*) echo "iTerm2"; return ;;
            *"Visual Studio Code"*|*Code\ Helper*) echo "VS Code"; return ;;
        esac
        p=$(ps -o ppid= -p "$p" | tr -d ' ')
    done
    echo "unknown"
}

# Type one line into the terminal tab whose tty is $2, as if typed by the user
type_into() {
    local app="$1" tty="$2" text="$3"
    case "$app" in
        Terminal)
            osascript - "$tty" "$text" <<'APPLESCRIPT'
on run argv
    set ttyPath to item 1 of argv
    set theText to item 2 of argv
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is ttyPath then
                    do script theText in t
                    return "ok"
                end if
            end repeat
        end repeat
    end tell
    return "not found"
end run
APPLESCRIPT
            ;;
        iTerm2)
            osascript - "$tty" "$text" <<'APPLESCRIPT'
on run argv
    set ttyPath to item 1 of argv
    set theText to item 2 of argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if tty of s is ttyPath then
                        tell s to write text theText
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "not found"
end run
APPLESCRIPT
            ;;
        *) echo "unsupported" ;;
    esac
}

wait_for_idle() {
    local pid="$1" waited=0 status
    while :; do
        status=$(status_of "$pid")
        [[ "$status" == "idle" ]] && return 0
        [[ -z "$status" ]] && return 1            # session ended
        $wait_idle || return 1
        (( waited >= WAIT_TIMEOUT )) && return 1
        sleep "$POLL"; waited=$((waited + POLL))
    done
}

list=$(sessions)
[[ -n "$list" ]] || fatal "No Claude session found (claude agents --json)"

if [[ "$command" == "list" ]]; then
    printf '%-8s %-12s %-8s %-10s %-28s %s\n' PID KIND STATUS TERMINAL NAME FOLDER
    while IFS=$'\t' read -r pid kind status name cwd _id; do
        app="-"
        [[ "$pid" != "-" ]] && app=$(terminal_app "$pid")
        [[ "$ancestors" == *" $pid "* ]] && name="$name (this one)"
        printf '%-8s %-12s %-8s %-10s %-28s %s\n' "$pid" "$kind" "$status" "$app" "${name:0:28}" "${cwd/#$HOME/\~}"
    done <<<"$list"
    exit 0
fi

sent=0
skipped=0
while IFS=$'\t' read -r pid kind status name cwd id; do
    label="$name (${cwd/#$HOME/\~})"
    if [[ -n "$only" && "$name$cwd" != *"$only"* ]]; then continue; fi
    if [[ "$kind" != "interactive" || "$pid" == "-" ]]; then
        echo "  skip  $label: background session (open it with: claude attach $id)"
        skipped=$((skipped + 1)); continue
    fi
    if [[ "$ancestors" == *" $pid "* ]]; then
        echo "  skip  $label: this session"
        continue
    fi
    app=$(terminal_app "$pid")
    tty="/dev/$(ps -o tty= -p "$pid" | tr -d ' ')"
    if [[ "$app" != "Terminal" && "$app" != "iTerm2" ]]; then
        echo "  skip  $label: runs in $app (not scriptable), type the request there"
        skipped=$((skipped + 1)); continue
    fi
    if $dry_run; then
        echo "  would $label [$status, $app $tty]: ${message:0:70}..."
        $compact && echo "        then /compact once idle again"
        continue
    fi
    if ! wait_for_idle "$pid"; then
        echo "  skip  $label: $status (use --wait to wait until it is idle)"
        skipped=$((skipped + 1)); continue
    fi
    if [[ "$(type_into "$app" "$tty" "$message")" != "ok" ]]; then
        echo "  fail  $label: tab not found in $app"
        skipped=$((skipped + 1)); continue
    fi
    echo "  sent  $label"
    sent=$((sent + 1))
    if $compact; then
        # The session must first start, then finish saving its memory
        for _ in $(seq 1 30); do [[ "$(status_of "$pid")" == "idle" ]] || break; sleep 1; done
        saved_wait=$wait_idle
        wait_idle=true
        if wait_for_idle "$pid" && [[ "$(type_into "$app" "$tty" "/compact")" == "ok" ]]; then
            echo "        /compact sent"
        else
            echo "        /compact not sent (session not idle in time)"
        fi
        wait_idle=$saved_wait
    fi
done <<<"$list"

$dry_run || echo "Done: $sent session(s) reached, $skipped skipped."
