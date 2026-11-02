#!/bin/bash

################################################################################
# Script:       odoo_demo_share.sh
# Description:  Shares a running local Odoo with a prospect or a client for a
#               demo: opens an ngrok tunnel, points and freezes web.base.url on
#               the public URL (links in mails, portal, website), then restores
#               everything when stopped (Ctrl-C). The running Odoo picks the
#               new URL up without restart (cache invalidation signal).
# Usage:        bash odoo_demo_share.sh [-C project_dir] [-d db] [-p port]
#               bash odoo_demo_share.sh --restore [-d db]   (after a crash)
#               Defaults: database of the project's launch configuration, port 8069.
# Notes:        Start Odoo first (VS Code debugger or odoo_run.sh). Adding
#               --proxy-mode to the launch configuration makes Odoo see https.
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"
[[ -x "$PG_BIN/psql" ]] && export PATH="$PG_BIN:$PATH"
STATE_DIR="$HOME/.local/state/odoo_demo_share"

fatal() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "==> $*"; }
usage() { sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

project="$PWD"
db=""
port="8069"
restore_only=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -C) project="${2/#\~/$HOME}"; shift 2 ;;
        -d) db="$2"; shift 2 ;;
        -p) port="$2"; shift 2 ;;
        --restore) restore_only=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

config_args=()
if config=$(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" argv "$project" 2>/dev/null | tr '\0' '\n'); then
    while IFS= read -r line; do config_args+=("$line"); done <<<"$config"
fi
if [[ -z "$db" && ${#config_args[@]} -gt 2 ]]; then
    db=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import odoo_projects as op; print(op.database_of(sys.argv[2:]) or "")' \
        "$SCRIPTS_DIR/lib" "${config_args[@]:2}")
fi
[[ -n "$db" ]] || fatal "No database: run from the project folder or use -d"
[[ "$db" =~ ^[A-Za-z0-9_.-]+$ ]] || fatal "Invalid database name: $db"
state_file="$STATE_DIR/$db.state"

sql() { psql -X -q -d "$db" -v ON_ERROR_STOP=1 -At "$@"; }

get_param() { sql -c "SELECT value FROM ir_config_parameter WHERE key = '$1'"; }

set_param() {   # key, value ("" = delete the parameter)
    if [[ -z "$2" ]]; then
        sql -c "DELETE FROM ir_config_parameter WHERE key = '$1'" >/dev/null
    else
        sql -v key="$1" -v value="$2" >/dev/null <<'SQL'
INSERT INTO ir_config_parameter (key, value, create_date, write_date)
VALUES (:'key', :'value', now() at time zone 'utc', now() at time zone 'utc')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, write_date = EXCLUDED.write_date;
SQL
    fi
}

# Tell the running Odoo workers to drop their parameter cache
signal_cache() {
    sql >/dev/null <<'SQL'
DO $$
BEGIN
    IF to_regclass('orm_signaling_stable') IS NOT NULL THEN
        INSERT INTO orm_signaling_stable DEFAULT VALUES;            -- Odoo 18+
    ELSIF to_regclass('base_cache_signaling_stable') IS NOT NULL THEN
        PERFORM nextval('base_cache_signaling_stable');             -- Odoo 17
    ELSIF to_regclass('base_cache_signaling') IS NOT NULL THEN
        PERFORM nextval('base_cache_signaling');                    -- Odoo 16
    END IF;
END $$;
SQL
}

restore() {
    [[ -f "$state_file" ]] || return 0
    local base_url freeze
    base_url=$(sed -n 's/^base_url=//p' "$state_file")
    freeze=$(sed -n 's/^freeze=//p' "$state_file")
    set_param web.base.url "$base_url"
    set_param web.base.url.freeze "$freeze"
    signal_cache
    rm -f "$state_file"
    info "web.base.url restored to '${base_url:-(none)}' on '$db'"
}

if $restore_only; then
    [[ -f "$state_file" ]] || fatal "Nothing to restore for '$db'"
    restore
    exit 0
fi

command -v ngrok >/dev/null || fatal "ngrok is required (brew install ngrok, then ngrok config add-authtoken ...)"
command -v curl >/dev/null || fatal "curl is required"
[[ "$(sql -c "SELECT 1 FROM pg_database WHERE datname = current_database()")" == "1" ]] || fatal "Database '$db' not reachable"
lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || fatal "Nothing listens on port $port: start Odoo first"
[[ -f "$state_file" ]] && fatal "A share is already active (or crashed) for '$db': bash $0 --restore -d $db"
if ! printf '%s\n' "${config_args[@]+"${config_args[@]}"}" | grep -q -- '--proxy-mode'; then
    echo "[WARN] Odoo runs without --proxy-mode: some redirects may use http instead of https." >&2
fi

mkdir -p "$STATE_DIR"
printf 'base_url=%s\nfreeze=%s\n' "$(get_param web.base.url)" "$(get_param web.base.url.freeze)" > "$state_file"

log=$(mktemp)
ngrok http "$port" --log=stdout > "$log" 2>&1 &
ngrok_pid=$!
cleanup() {
    trap - EXIT INT TERM
    kill "$ngrok_pid" 2>/dev/null || true
    wait "$ngrok_pid" 2>/dev/null || true
    restore
    rm -f "$log"
}
trap cleanup EXIT INT TERM

# The local ngrok API gives the public URL once the tunnel is up
public_url=""
for _ in $(seq 1 30); do
    api_port=$(sed -n 's/.*addr=127.0.0.1:\([0-9]*\).*/\1/p' "$log" | head -n 1)
    public_url=$(curl -s "http://127.0.0.1:${api_port:-4040}/api/tunnels" 2>/dev/null |
        python3 -c 'import json, sys; t = json.load(sys.stdin).get("tunnels", []); print(next((x["public_url"] for x in t if x["public_url"].startswith("https")), ""))' 2>/dev/null || true)
    [[ -n "$public_url" ]] && break
    kill -0 "$ngrok_pid" 2>/dev/null || { tail -n 5 "$log" >&2; fatal "ngrok stopped"; }
    sleep 1
done
[[ -n "$public_url" ]] || { tail -n 5 "$log" >&2; fatal "No public URL from ngrok"; }

set_param web.base.url "$public_url"
set_param web.base.url.freeze "True"
signal_cache
command -v pbcopy >/dev/null && printf '%s' "$public_url/odoo" | pbcopy

echo ""
echo "  Demo URL: $public_url/odoo   (copied to the clipboard)"
echo "  Database: $db (web.base.url frozen on the public URL)"
echo "  Press Ctrl-C to stop sharing and restore the configuration."
echo ""
wait "$ngrok_pid"
