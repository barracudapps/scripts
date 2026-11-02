#!/bin/bash

################################################################################
# Script: 	odooTests.sh
# Description: 	Run Odoo tests in multiple threads using cloned databases and filestores.
# 		The Odoo command (program, python interpreter, args, database) is read
# 		from a launch configuration of .vscode/settings.json (or launch.json).
# 		Compatible with macOS & Linux (PostgreSQL client tools, rsync, python3)
# Usage: 	./odooTests.sh [--threads N] [--loop-until-fail N] [--config NAME] [--verbose]
# Author: 	Pierre LAMOTTE
# Date: 	17 JUL 2025
################################################################################

NB_THREADS=3
VERBOSE=false
MAX_RUNS=0
BASE_PORT=8069
CONFIG_NAME=""   # default: "Odoo All Tests" if it exists, else "Odoo D-Bug"
WORKSPACE_DIR=$(pwd)

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

usage() {
    echo "Usage: ./odooTests.sh [--threads N] [--loop-until-fail N] [--config NAME] [--verbose]"
    echo "  --threads N          number of parallel Odoo instances (default: $NB_THREADS)"
    echo "  --loop-until-fail N  repeat the whole run up to N times, stop at the first failure"
    echo "  --config NAME        launch configuration to use (default: 'Odoo All Tests', else 'Odoo D-Bug')"
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -t|--threads) NB_THREADS="$2"; shift 2 ;;
        --loop-until-fail) MAX_RUNS="$2"; shift 2 ;;
        -c|--config) CONFIG_NAME="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

[[ "$NB_THREADS" =~ ^[1-9][0-9]*$ ]] || fatal "--threads expects a positive number"
[[ "$MAX_RUNS" =~ ^[0-9]+$ ]] || fatal "--loop-until-fail expects a number"

for tool in python3 createdb dropdb rsync; do
    command -v "$tool" >/dev/null || fatal "'$tool' is required"
done

# Read the launch configuration (VS Code files are JSON with comments and
# trailing commas: they are cleaned by a small Python parser, stdlib only).
# Output: program, python, then one argument per line (NUL separated).
read_launch_config() {
    python3 - "$WORKSPACE_DIR" "$CONFIG_NAME" <<'PYEOF'
import json, re, sys
from pathlib import Path

workspace, wanted = sys.argv[1], sys.argv[2]

def load_jsonc(path):
    text = path.read_text()
    out, i, in_str = [], 0, False
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1]); i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True; out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            i = text.find("*/", i + 2) + 2
            continue
        else:
            out.append(c)
        i += 1
    return json.loads(re.sub(r",(\s*[\]}])", r"\1", "".join(out)))

configs = []
for name in ("settings.json", "launch.json"):
    path = Path(workspace, ".vscode", name)
    if path.is_file():
        data = load_jsonc(path)
        launch = data.get("launch", data) if name == "settings.json" else data
        configs += launch.get("configurations", []) if isinstance(launch, dict) else []

names = [c.get("name") for c in configs]
for candidate in ([wanted] if wanted else ["Odoo All Tests", "Odoo D-Bug"]):
    if candidate in names:
        config = configs[names.index(candidate)]
        break
else:
    sys.exit(f"Launch configuration not found ({wanted or 'Odoo All Tests / Odoo D-Bug'}). Available: {names}")

def expand(value):
    return value.replace("${workspaceFolder}", workspace)

sys.stderr.write(f"[INFO] Using launch configuration '{config['name']}'\n")
fields = [expand(config.get("program", "")), expand(config.get("python", ""))]
fields += [expand(a) for a in config.get("args", [])]
sys.stdout.write("\0".join(fields) + "\0")
PYEOF
}

CONFIG_FIELDS=()
while IFS= read -r -d '' field; do
    CONFIG_FIELDS+=("$field")
done < <(read_launch_config) || true
[[ ${#CONFIG_FIELDS[@]} -ge 2 ]] || fatal "Unable to read the launch configuration from .vscode/"

ODOO_BIN="${CONFIG_FIELDS[0]}"
PYTHON_BIN="${CONFIG_FIELDS[1]}"
PROCESSED_ARGS_RAW=("${CONFIG_FIELDS[@]:2}")

[[ -f "$ODOO_BIN" ]] || fatal "Odoo program not found: '$ODOO_BIN'"
# Never rely on odoo-bin's shebang (system python3 has no Odoo dependencies)
[[ -z "$PYTHON_BIN" && -x "$WORKSPACE_DIR/.venv/bin/python3" ]] && PYTHON_BIN="$WORKSPACE_DIR/.venv/bin/python3"
[[ -x "$PYTHON_BIN" ]] || fatal "Python interpreter not found: '$PYTHON_BIN' (set \"python\" in the launch configuration)"

# Base database: value of -d / --database in the configuration
BASE_DB=""
for ((i = 0; i < ${#PROCESSED_ARGS_RAW[@]}; i++)); do
    arg="${PROCESSED_ARGS_RAW[$i]}"
    case "$arg" in
        -d|--database) BASE_DB="${PROCESSED_ARGS_RAW[$((i + 1))]}" ;;
        --database=*) BASE_DB="${arg#--database=}" ;;
        -d?*) BASE_DB="${arg#-d}" ;;
    esac
done
[[ -n "$BASE_DB" ]] || fatal "No database (-d) found in the launch configuration"

if ! printf '%s\n' "${PROCESSED_ARGS_RAW[@]}" | grep -q -- '--stop-after-init'; then
    echo "[WARN] '--stop-after-init' is missing: the Odoo instances will keep running after the tests." >&2
fi

FILESTORE_BASE=$(detect_filestore_base)

cleanup_clone() {
    local db="$1"
    dropdb --if-exists "$db" 2>/dev/null || echo "[WARN] Failed to drop $db" >&2
    [[ -n "$db" && -d "$FILESTORE_BASE/$db" ]] && rm -rf "${FILESTORE_BASE:?}/$db"
}

on_interrupt() {
    echo "" >&2
    echo "[INFO] Interrupted: stopping instances and dropping cloned databases..." >&2
    jobs -p | xargs kill 2>/dev/null
    wait 2>/dev/null
    for ((n = 2; n <= NB_THREADS; n++)); do cleanup_clone "${BASE_DB}_thread_$n"; done
    exit 130
}
trap on_interrupt INT TERM

run_test_instance() {
    local INSTANCE_NUM=$1
    local PORT=$((BASE_PORT + INSTANCE_NUM - 1))
    local DB_NAME CLONED

    if [[ "$INSTANCE_NUM" -eq 1 ]]; then
        DB_NAME="$BASE_DB"
        CLONED=false
    else
        DB_NAME="${BASE_DB}_thread_$INSTANCE_NUM"
        CLONED=true

        dropdb --if-exists "$DB_NAME" 2>/dev/null
        if ! createdb "$DB_NAME" -T "$BASE_DB"; then
            echo "[ERROR] Failed to clone DB $DB_NAME (is '$BASE_DB' in use by another Odoo/psql session?)" >&2
            return 1
        fi
        local ORIG_FS="$FILESTORE_BASE/$BASE_DB"
        local NEW_FS="$FILESTORE_BASE/$DB_NAME"
        if [ -d "$ORIG_FS" ]; then
            rsync -a "$ORIG_FS/" "$NEW_FS/"
        else
            log "[WARN] No filestore to clone for $DB_NAME"
        fi
    fi

    local ARGS=() SKIP_NEXT=false val
    for val in "${PROCESSED_ARGS_RAW[@]}"; do
        if $SKIP_NEXT; then SKIP_NEXT=false; continue; fi
        case "$val" in
            -d|--database|-p|--http-port) SKIP_NEXT=true; continue ;;
            --database=*|-d?*|--http-port=*|-p?*) continue ;;
        esac
        ARGS+=("$val")
    done
    ARGS+=("--database=$DB_NAME" "--http-port=$PORT")

    log "[INFO] Instance $INSTANCE_NUM starting on port $PORT with DB $DB_NAME"
    # Prefix every output line with the instance number
    "$PYTHON_BIN" "$ODOO_BIN" "${ARGS[@]}" 2>&1 | sed -u "s/^/[t$INSTANCE_NUM] /"
    local STATUS=${PIPESTATUS[0]}

    if $CLONED; then
        cleanup_clone "$DB_NAME"
    fi

    return "$STATUS"
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
        if ! run_all_instances; then
            echo "[FAIL] A test failed during run $run"
            exit 1
        fi
    done
    echo "[OK] All $MAX_RUNS runs passed"
else
    if run_all_instances; then
        echo "[OK] Tests passed on $NB_THREADS thread(s)"
    else
        echo "[FAIL] At least one test failed"
        exit 1
    fi
fi
