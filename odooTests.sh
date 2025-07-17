#!/bin/bash

################################################################################
# Script: 	odooTests.sh
# Description: 	Run Odoo tests in multiple threads using cloned databases and filestores.
# 		Compatible with macOS & Linux (PostgreSQL, rsync, jq required)
# Usage: 	./odooTests.sh [--threads N] [--loop-until-fail N] [--verbose]
# Author: 	Pierre LAMOTTE
# Date: 	17 JUL 2025
################################################################################

NB_THREADS=3
VERBOSE=false
MAX_RUNS=0
BASE_PORT=8069
SETTINGS_FILE=".vscode/settings.json"
CONFIG_NAME="Odoo D-Bug"
BASE_DB="odoo18"

detect_filestore_base() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$HOME/Library/Application Support/Odoo/filestore"
    else
        echo "$HOME/.local/share/Odoo/filestore"
    fi
}

log() {
    [ "$VERBOSE" = true ] && echo "$@"
}

fatal() {
    echo "[ERROR] $1" >&2
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -t|--threads) NB_THREADS="$2"; shift 2 ;;
        --loop-until-fail) MAX_RUNS="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help)
            echo "Usage: ./odooTests.sh [--threads N] [--loop-until-fail N] [--verbose]"
            exit 0 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

for tool in jq createdb dropdb rsync; do
    command -v "$tool" >/dev/null || fatal "'$tool' is required"
done

TEMP_JSON=$(mktemp)
sed '/^[[:space:]]*\/\//d' "$SETTINGS_FILE" > "$TEMP_JSON.1"
awk '
    {
        if (prev ~ /,$/ && $0 ~ /^[[:space:]]*[\]}]/) {
            sub(/,$/, "", prev)
        }
        if (NR > 1) print prev
        prev = $0
    }
    END { print prev }
' "$TEMP_JSON.1" > "$TEMP_JSON"
rm "$TEMP_JSON.1"

ODOO_BIN=$(jq -r '.launch.configurations[] | select(.name == "'"$CONFIG_NAME"'") | .program' "$TEMP_JSON")
[[ -z "$ODOO_BIN" || "$ODOO_BIN" == "null" ]] && fatal "Missing Odoo program path"

ARGS_ARRAY=()
while IFS= read -r arg; do
    ARGS_ARRAY+=("$arg")
done < <(jq -r '.launch.configurations[] | select(.name == "'"$CONFIG_NAME"'") | .args[] | select(startswith("//") | not)' "$TEMP_JSON")
rm "$TEMP_JSON"

WORKSPACE_DIR=$(pwd)
ODOO_BIN="${ODOO_BIN//\$\{workspaceFolder\}/$WORKSPACE_DIR}"

PROCESSED_ARGS_RAW=()
for arg in "${ARGS_ARRAY[@]}"; do
    PROCESSED_ARGS_RAW+=("${arg//\$\{workspaceFolder\}/$WORKSPACE_DIR}")
done

FILESTORE_BASE=$(detect_filestore_base)

run_test_instance() {
    INSTANCE_NUM=$1
    PORT=$((BASE_PORT + INSTANCE_NUM - 1))

    if [[ "$INSTANCE_NUM" -eq 1 ]]; then
        DB_NAME="$BASE_DB"
        CLONED=false
    else
        DB_NAME="${BASE_DB}_thread_$INSTANCE_NUM"
        CLONED=true

        createdb "$DB_NAME" -T "$BASE_DB" || fatal "Failed to clone DB $DB_NAME"
        ORIG_FS="$FILESTORE_BASE/$BASE_DB"
        NEW_FS="$FILESTORE_BASE/$DB_NAME"
        [ -d "$ORIG_FS" ] && rsync -a "$ORIG_FS/" "$NEW_FS/" || log "[WARN] No filestore to clone for $DB_NAME"
    fi

    ARGS=()
    USE_NEXT=false
    for val in "${PROCESSED_ARGS_RAW[@]}"; do
        if $USE_NEXT; then val="$DB_NAME"; USE_NEXT=false; fi
        [ "$val" == "-d" ] && USE_NEXT=true
        ARGS+=("$val")
    done
    ARGS+=("--http-port=$PORT")

    log "[INFO] Instance $INSTANCE_NUM starting on port $PORT with DB $DB_NAME"
    "$ODOO_BIN" "${ARGS[@]}"
    STATUS=$?

    if $CLONED; then
        dropdb "$DB_NAME" || echo "[WARN] Failed to drop $DB_NAME"
        [ -d "$FILESTORE_BASE/$DB_NAME" ] && rm -rf "$FILESTORE_BASE/$DB_NAME"
    fi

    return $STATUS
}

run_all_instances() {
    local PIDS=()
    local FAIL=0

    for ((i=1; i<=NB_THREADS; i++)); do
        run_test_instance "$i" &
        PIDS+=($!)
    done

    for pid in "${PIDS[@]}"; do
        wait "$pid" || FAIL=1
    done

    return $FAIL
}

if [[ "$MAX_RUNS" -gt 0 ]]; then
    for ((run=1; run<=MAX_RUNS; run++)); do
        echo "[RUN] $run/$MAX_RUNS"
        run_all_instances
        if [[ $? -ne 0 ]]; then
            echo "[FAIL] A test failed during run $run"
            exit 1
        fi
    done
    echo "[OK] All $MAX_RUNS runs passed"
else
    run_all_instances
    if [[ $? -eq 0 ]]; then
        echo "[OK] Tests passed on $NB_THREADS thread(s)"
    else
        echo "[FAIL] At least one test failed"
        exit 1
    fi
fi
