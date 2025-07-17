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

# === Detect platform-specific filestore base
detect_filestore_base() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$HOME/Library/Application Support/Odoo/filestore"
    else
        echo "$HOME/.local/share/Odoo/filestore"
    fi
}

log() {
    if [ "$VERBOSE" = true ]; then echo "$@"; fi
}

fatal() {
    echo "❌ $1"
    exit 1
}

# === Parse CLI args ===
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -t|--threads)
            NB_THREADS="$2"; shift 2 ;;
        --loop-until-fail)
            MAX_RUNS="$2"; shift 2 ;;
        -v|--verbose)
            VERBOSE=true; shift ;;
        -h|--help)
            echo "Usage: ./odooTests.sh [--threads N] [--loop-until-fail N] [--verbose]"
            exit 0 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

# === Check required tools ===
for tool in jq createdb dropdb rsync; do
    if ! command -v $tool &>/dev/null; then
        fatal "'$tool' is required but not installed."
    fi
done

# === Clean and parse settings.json to valid JSON ===
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

# === Parse config
ODOO_BIN=$(jq -r '.launch.configurations[] | select(.name == "'"$CONFIG_NAME"'") | .program' "$TEMP_JSON")
[[ -z "$ODOO_BIN" || "$ODOO_BIN" == "null" ]] && fatal "Could not find program in $SETTINGS_FILE"

# === Parse args
ARGS_ARRAY=()
while IFS= read -r arg; do
    ARGS_ARRAY+=("$arg")
done < <(jq -r '.launch.configurations[] | select(.name == "'"$CONFIG_NAME"'") | .args[] | select(startswith("//") | not)' "$TEMP_JSON")
rm "$TEMP_JSON"

# === Replace ${workspaceFolder}
WORKSPACE_DIR=$(pwd)
ODOO_BIN="${ODOO_BIN//\$\{workspaceFolder\}/$WORKSPACE_DIR}"
PROCESSED_ARGS_RAW=()
for arg in "${ARGS_ARRAY[@]}"; do
    PROCESSED_ARGS_RAW+=("${arg//\$\{workspaceFolder\}/$WORKSPACE_DIR}")
done

# === Get filestore base
FILESTORE_BASE=$(detect_filestore_base)

# === Run a single test instance
run_test_instance() {
    INSTANCE_NUM=$1
    PORT=$((BASE_PORT + INSTANCE_NUM - 1))

    if [[ "$INSTANCE_NUM" -eq 1 ]]; then
        DB_NAME="$BASE_DB"
        CLONED=false
    else
        DB_NAME="${BASE_DB}_thread_$INSTANCE_NUM"
        CLONED=true

        log "🌀 Cloning DB: $BASE_DB → $DB_NAME"
        createdb "$DB_NAME" -T "$BASE_DB" || fatal "Failed to clone $BASE_DB to $DB_NAME"

        ORIG_FS="$FILESTORE_BASE/$BASE_DB"
        NEW_FS="$FILESTORE_BASE/$DB_NAME"

        if [ -d "$ORIG_FS" ]; then
            log "📁 Cloning filestore: $ORIG_FS → $NEW_FS"
            rsync -a "$ORIG_FS/" "$NEW_FS/"
        else
            log "⚠️ Filestore source not found: $ORIG_FS"
        fi
    fi

    # Replace -d DB_NAME
    ARGS=()
    USE_NEXT=false
    for val in "${PROCESSED_ARGS_RAW[@]}"; do
        if $USE_NEXT; then
            val="$DB_NAME"
            USE_NEXT=false
        fi
        if [[ "$val" == "-d" ]]; then
            USE_NEXT=true
        fi
        ARGS+=("$val")
    done
    ARGS+=("--http-port=$PORT")

    log "▶️  Starting instance $INSTANCE_NUM on port $PORT (DB: $DB_NAME)"
    "$ODOO_BIN" "${ARGS[@]}"
    STATUS=$?

    if [[ $STATUS -eq 0 ]]; then
        log "✅  Instance $INSTANCE_NUM succeeded on port $PORT"
    else
        echo "❌  Instance $INSTANCE_NUM failed on port $PORT (code $STATUS)"
    fi

    # Clean cloned DB and filestore
    if $CLONED; then
        log "🧹 Dropping temp DB: $DB_NAME"
        dropdb "$DB_NAME" || echo "⚠️ Failed to drop $DB_NAME"
        FS="$FILESTORE_BASE/$DB_NAME"
        if [ -d "$FS" ]; then
            log "🧹 Removing filestore: $FS"
            rm -rf "$FS"
        fi
    fi

    return $STATUS
}

# === Run all test instances in parallel
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

# === Main loop
if [[ "$MAX_RUNS" -gt 0 ]]; then
    for ((run=1; run<=MAX_RUNS; run++)); do
        echo "🔁 Run $run/$MAX_RUNS..."
        run_all_instances
        if [[ $? -ne 0 ]]; then
            echo "❌ A test failed during run $run. Exiting."
            exit 1
        fi
    done
    echo "🎉 All $MAX_RUNS runs succeeded with $NB_THREADS thread(s)."
else
    run_all_instances
    if [[ $? -eq 0 ]]; then
        echo "🎉 Tests passed on $NB_THREADS thread(s)."
    else
        echo "❌ At least one test failed."
        exit 1
    fi
fi
