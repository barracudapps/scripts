#!/bin/bash

################################################################################
# Script:       odoo_i18n.sh
# Description:  Full translation pipeline of a custom module in one command:
#               1. export <module>/i18n/<module>.pot from the project database
#                  (odoo-bin i18n export in 19+, --i18n-export before),
#               2. create the missing <lang>.po files,
#               3. sync every .po with the .pot and fill the empty entries
#                  from a source module (odoo_translate.py),
#               4. report the untranslated entries left per language.
#               The module must be installed in the database.
# Usage:        bash odoo_i18n.sh <module> [-l fr,nl] [--source module] [-d db] [-C dir]
#               -l LANGS       languages to create if missing (e.g. fr,nl,de)
#               --source MOD   module to copy existing translations from
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"
[[ -x "$PG_BIN/psql" ]] && export PATH="$PG_BIN:$PATH"

fatal() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "==> $*"; }
usage() { sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

[[ $# -ge 1 && "$1" != -* ]] || { usage; exit 1; }
module="$1"
shift
langs=""
source_module=""
db=""
project="$PWD"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l) langs="$2"; shift 2 ;;
        --source) source_module="$2"; shift 2 ;;
        -d) db="$2"; shift 2 ;;
        -C) project="${2/#\~/$HOME}"; shift 2 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

# Project configuration: interpreter, odoo-bin, database, resolved addons path
read_config() {
    python3 - "$SCRIPTS_DIR/lib" "$project" "$module" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import odoo_projects as op
project, module = Path(sys.argv[2]).resolve(), sys.argv[3]
summary = op.config_summary(project)
if summary is None:
    sys.exit("No Odoo launch configuration found in " + str(project))
paths = [p for p in op.addons_paths(summary["args"], project) if p.is_dir()]
module_dir = next((p / module for p in paths if (p / module / "__manifest__.py").is_file()), None)
if module_dir is None:
    sys.exit(f"Module {module} not found in the addons path")
python = summary["python"] or str(project / ".venv" / "bin" / "python3")
print("\0".join([python, summary["program"], summary["database"] or "", ",".join(map(str, paths)), str(module_dir)]), end="\0")
PYEOF
}

fields=()
while IFS= read -r -d '' f; do fields+=("$f"); done < <(read_config)
[[ ${#fields[@]} -eq 5 ]] || exit 1
python="${fields[0]}"; program="${fields[1]}"; db="${db:-${fields[2]}}"; addons_path="${fields[3]}"; module_dir="${fields[4]}"
[[ -n "$db" ]] || fatal "No database: use -d"

state=$(psql -d "$db" -Atc "SELECT state FROM ir_module_module WHERE name = '$module'" 2>/dev/null || true)
[[ "$state" == "installed" ]] || fatal "Module '$module' is not installed in '$db' (state: ${state:-unknown}). Install it first: odoo_run.sh -i $module -d $db"

i18n_dir="$module_dir/i18n"
pot="$i18n_dir/$module.pot"
mkdir -p "$i18n_dir"
odoo_dir=$(dirname "$program")

info "Exporting $module.pot from '$db'..."
if [[ -f "$odoo_dir/odoo/cli/i18n.py" ]]; then
    conf=$(mktemp)
    trap 'rm -f "$conf"' EXIT
    printf '[options]\naddons_path = %s\ndb_name = %s\n' "$addons_path" "$db" > "$conf"
    "$python" "$program" i18n export -c "$conf" -l pot -o "$pot" "$module" 2>&1 | grep -v ' INFO ' || true
else
    "$python" "$program" -d "$db" "--addons-path=$addons_path" --i18n-export="$pot" \
        "--modules=$module" --stop-after-init --no-http --log-level=warn
fi
[[ -s "$pot" ]] || fatal "The .pot export failed"
echo "    $(grep -c '^msgid "' "$pot") msgid(s) in $pot"

# Missing languages: copy of the .pot with the Language header set
IFS=',' read -ra wanted <<<"$langs"
for lang in "${wanted[@]}"; do
    [[ -z "$lang" ]] && continue
    po="$i18n_dir/$lang.po"
    if [[ ! -f "$po" ]]; then
        # The exported .pot has no "Language:" header: add it after Language-Team
        awk -v lang="$lang" '
            /^"Language: / { next }
            { print }
            /^"Language-Team: / && !done { printf "\"Language: %s\\n\"\n", lang; done = 1 }
        ' "$pot" > "$po"
        info "Created $po"
    fi
done

if compgen -G "$i18n_dir/*.po" >/dev/null; then
    info "Syncing .po files${source_module:+ and copying translations from $source_module}..."
    (cd "$(dirname "$module_dir")/.." && "$SCRIPTS_DIR/odoo_translate.py" "$module_dir" "${source_module:-$module_dir}") |
        sed 's/\x1b\[[0-9;]*m//g' | grep -E '✓|!|ERREUR' || true

    info "Untranslated entries left:"
    for po in "$i18n_dir"/*.po; do
        stats=$(msgfmt --statistics -o /dev/null "$po" 2>&1 || true)
        printf '    %-10s %s\n' "$(basename "$po" .po)" "$stats"
    done
else
    echo "No .po file yet: add languages with -l fr,nl"
fi
