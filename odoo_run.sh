#!/bin/bash

################################################################################
# Script:       odoo_run.sh
# Description:  Runs the Odoo project of the current directory from the
#               terminal, with the interpreter, odoo-bin and arguments of its
#               VS Code launch configuration, plus shortcuts to update/install
#               modules, run module tests or open an Odoo shell.
#               -i/-u/--test-tags/--stop-after-init lines of the configuration
#               are replaced by the requested mode.
# Usage:        bash odoo_run.sh [mode] [options] [-- extra odoo-bin args]
#   Modes:      (none)            run the server as configured
#               -u MODULES        update modules (comma-separated), keep serving
#               -i MODULES        install modules, keep serving
#               --test MODULES    update + run the tests of the modules, then stop
#               --test-tags TAGS  run exactly these test tags (e.g. /mod:Class), then stop
#               shell             odoo-bin shell on the project database
#   Options:    -d DB             use another database
#               -p PORT           HTTP port (e.g. to run next to the debugger)
#               -c NAME           launch configuration (default: "Odoo D-Bug")
#               -C DIR            project directory (default: current directory)
#               --dry-run         print the command without running it
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fatal() { echo "[ERROR] $*" >&2; exit 1; }
usage() { sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

mode="run"
modules=""
test_tags=""
db=""
port=""
config_name=""
project="$PWD"
dry_run=false
extra=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u) mode="update"; modules="$2"; shift 2 ;;
        -i) mode="install"; modules="$2"; shift 2 ;;
        --test) mode="test"; modules="$2"; shift 2 ;;
        --test-tags) mode="test-tags"; test_tags="$2"; shift 2 ;;
        shell) mode="shell"; shift ;;
        -d) db="$2"; shift 2 ;;
        -p) port="$2"; shift 2 ;;
        -c) config_name="$2"; shift 2 ;;
        -C) project="${2/#\~/$HOME}"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --) shift; extra=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) fatal "Unknown option: $1 (see --help)" ;;
    esac
done

fields=()
while IFS= read -r -d '' field; do
    fields+=("$field")
done < <(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" argv "$project" ${config_name:+"$config_name"})
[[ ${#fields[@]} -ge 2 ]] || fatal "No Odoo launch configuration found in $project/.vscode"

python="${fields[0]}"
program="${fields[1]}"
config_args=("${fields[@]:2}")
[[ -x "$python" ]] || fatal "Python interpreter not found: $python"
[[ -f "$program" ]] || fatal "odoo-bin not found: $program"

# Keep the configuration arguments, minus the ones the chosen mode replaces
args=()
skip_next=false
for arg in "${config_args[@]}"; do
    if $skip_next; then skip_next=false; continue; fi
    case "$arg" in
        -i|-u|--init|--update|--test-tags)
            [[ "$mode" == "run" ]] || { skip_next=true; continue; } ;;
        --init=*|--update=*|--test-tags=*|--test-enable|--stop-after-init)
            [[ "$mode" == "run" ]] || continue ;;
        -d|--database)
            [[ -n "$db" ]] && { skip_next=true; continue; } ;;
        --database=*)
            [[ -n "$db" ]] && continue ;;
        -p|--http-port)
            [[ -n "$port" ]] && { skip_next=true; continue; } ;;
        --http-port=*)
            [[ -n "$port" ]] && continue ;;
    esac
    args+=("$arg")
done
[[ -n "$db" ]] && args+=("--database=$db")
[[ -n "$port" ]] && args+=("--http-port=$port")

case "$mode" in
    update) args+=(-u "$modules") ;;
    install) args+=(-i "$modules") ;;
    test)
        tags=""
        IFS=',' read -ra mods <<<"$modules"
        for m in "${mods[@]}"; do tags+="${tags:+,}/$m"; done
        args+=(-i "$modules" -u "$modules" --test-enable "--test-tags=$tags" --stop-after-init) ;;
    test-tags) args+=(--test-enable "--test-tags=$test_tags" --stop-after-init) ;;
    shell)
        # The shell subcommand must come first; server-only options are dropped
        shell_args=()
        skip_next=false
        for arg in "${args[@]}"; do
            if $skip_next; then shell_args+=("$arg"); skip_next=false; continue; fi
            case "$arg" in
                -d|--database) shell_args+=("$arg"); skip_next=true ;;
                --addons-path=*|--database=*|--data-dir=*|--db_*|--log-level=*) shell_args+=("$arg") ;;
            esac
        done
        args=(shell "${shell_args[@]}" --no-http) ;;
esac
args+=(${extra[@]+"${extra[@]}"})

if $dry_run; then
    printf '%q ' "$python" "$program" "${args[@]}"
    echo
    exit 0
fi

cd "$project"
exec "$python" "$program" "${args[@]}"
