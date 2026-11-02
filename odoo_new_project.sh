#!/bin/bash

################################################################################
# Script:       odoo_new_project.sh
# Description:  Creates a new Odoo client project from the template
#               ~/Documents/Odoo/_templates/client-project:
#               .odoo-project.json (commits of the shared worktrees), VS Code
#               settings (database name), .ruff.toml (target Python), user/,
#               .gitignore, worktrees + addons-path (odoo_project_sync.py),
#               uv virtualenv (requirements of the Community worktree,
#               psycopg2 built against Postgres.app) and, optionally, an
#               initialized database.
# Usage:        bash odoo_new_project.sh <project_dir> <version> [options]
#               --db NAME        database name (default: derived from the folder)
#               --no-enterprise  Community only
#               --latest         fetch and use the latest commit of the branch
#                                (default: reuse the most recent <version>@<hash>
#                                worktree already on disk, no new checkout)
#               --python X.Y     Python version (default: by Odoo version)
#               --init-db        create the database with base (no demo data)
#               --lang CODE      language installed with --init-db (e.g. fr_FR)
# Example:      bash odoo_new_project.sh "~/Desktop/Indépendant BApps/Clients/Acme/ERP/Odoo" 19.0 --db acme-dev --init-db --lang fr_FR
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

ODOO_ROOT="$HOME/Documents/Odoo"
TEMPLATE="$ODOO_ROOT/_templates/client-project"
VERSIONS_DIR="$ODOO_ROOT/versions"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"

fatal() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() { sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

[[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]] && { usage; exit 0; }
[[ $# -ge 2 ]] || { usage >&2; exit 1; }

project_dir="${1/#\~/$HOME}"
version="$2"
shift 2
db_name=""
with_enterprise=true
latest=false
python_version=""
init_db=false
lang=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) db_name="$2"; shift 2 ;;
        --no-enterprise) with_enterprise=false; shift ;;
        --latest) latest=true; shift ;;
        --python) python_version="$2"; shift 2 ;;
        --init-db) init_db=true; shift ;;
        --lang) lang="$2"; shift 2 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

[[ "$version" =~ ^([0-9]+)\.0$ ]] || fatal "Version must look like 19.0 (got '$version')"
major="${BASH_REMATCH[1]}"

# Python version recommended by Odoo version (user choice: 3.13 for 19/20)
if [[ -z "$python_version" ]]; then
    if (( major >= 19 )); then python_version="3.13"
    elif (( major == 18 )); then python_version="3.12"
    else python_version="3.10"
    fi
fi

[[ -d "$TEMPLATE" ]] || fatal "Template not found: $TEMPLATE"
[[ -e "$project_dir/.odoo-project.json" ]] && fatal "$project_dir already contains a .odoo-project.json"
command -v uv >/dev/null || fatal "uv is required (brew install uv)"
[[ -x "$PG_BIN/psql" ]] || fatal "Postgres.app not found ($PG_BIN)"
export PATH="$PG_BIN:$PATH"   # psycopg2 must be built against Postgres.app's libpq

# Default database name: "<parent folder>-dev" in lower case, e.g. acme-dev
if [[ -z "$db_name" ]]; then
    base=$(basename "$project_dir")
    [[ "$base" == "Odoo" ]] && base=$(basename "$(dirname "$project_dir")")
    db_name="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')-dev"
fi
[[ "$db_name" =~ ^[A-Za-z0-9_.-]+$ ]] || fatal "Invalid database name: $db_name"
if $init_db && psql -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$db_name'" | grep -q 1; then
    fatal "Database '$db_name' already exists (choose another --db or drop it with odoo_db.sh)"
fi

# Commit to use: the most recent <version>@<hash> worktree already on disk (no
# new checkout, disk space shared with other projects), or the latest commit of
# the branch with --latest
commit_for() {
    local edition="$1" repo="$ODOO_ROOT/_repos/$2" existing
    existing=$(ls -dt "$VERSIONS_DIR/$edition/$version@"* 2>/dev/null | head -n 1 || true)
    if $latest; then
        git -C "$repo" fetch -q origin "+refs/heads/$version:refs/remotes/origin/$version" >&2 || true
        git -C "$repo" rev-parse --short=8 "refs/remotes/origin/$version"
    elif [[ -n "$existing" ]]; then
        echo "${existing##*@}"
    else
        git -C "$repo" rev-parse --short=8 "refs/remotes/origin/$version" 2>/dev/null ||
            git -C "$repo" rev-parse --short=8 "refs/heads/$version"
    fi
}

community_commit=$(commit_for community odoo.git) || fatal "Branch $version not found in odoo.git"
enterprise_json=""
enterprise_commit=""
if $with_enterprise; then
    enterprise_commit=$(commit_for enterprise enterprise.git) || fatal "Branch $version not found in enterprise.git"
    enterprise_json=$(printf ',\n    "enterprise": { "version": "%s", "commit": "%s" }' "$version" "$enterprise_commit")
fi

info "Project:    $project_dir"
info "Odoo:       $version (community $community_commit${enterprise_commit:+, enterprise $enterprise_commit})"
info "Python:     $python_version    Database: $db_name"

# 1. Files from the template
mkdir -p "$project_dir"
cp -Rn "$TEMPLATE/." "$project_dir/"
mkdir -p "$project_dir/user"
printf '{\n    "community": { "version": "%s", "commit": "%s" }%s\n}\n' \
    "$version" "$community_commit" "$enterprise_json" > "$project_dir/.odoo-project.json"

settings="$project_dir/.vscode/settings.json"
sed -i '' "s/REMPLACER_PAR_LE_NOM_DB/$db_name/g" "$settings"
if ! $with_enterprise; then
    sed -i '' 's/,enterprise,user"/,user"/g' "$settings"
fi
if (( major < 19 )); then
    # Odoo <= 18 loads demo data by default: keep the existing commented option active
    sed -i '' 's|// "--without-demo=all",|"--without-demo=all",|' "$settings"
fi
[[ -f "$project_dir/.ruff.toml" ]] &&
    sed -i '' -E "s/^target-version = \"py[0-9]+\"/target-version = \"py${python_version/./}\"/" "$project_dir/.ruff.toml"

if [[ ! -f "$project_dir/.gitignore" ]]; then
    cat > "$project_dir/.gitignore" <<'EOF'
# dotfiles
.*
!.gitignore
!.odoo-project.json
!.ruff.toml

# Claude Code assistant files (not part of this repo)
CLAUDE.md

# Odoo sources come from the shared worktrees (~/Documents/Odoo/versions)
/odoo/
/odoo-bin
/enterprise/
*.pyc
__pycache__/

# venv
/.venv/
EOF
fi

# 2. Worktrees + absolute addons-path / program in VS Code settings
info "Syncing worktrees..."
python3 "$SCRIPTS_DIR/odoo_project_sync.py" "$project_dir"
community_path="$VERSIONS_DIR/community/$version@$(git -C "$ODOO_ROOT/_repos/odoo.git" rev-parse --short=8 "$community_commit^{commit}")"
[[ -f "$community_path/requirements.txt" ]] || fatal "requirements.txt not found in $community_path"

# 3. Virtualenv managed by uv
info "Creating the virtualenv (Python $python_version)..."
uv python install "$python_version" >/dev/null
uv venv --quiet --managed-python --python "$python_version" "$project_dir/.venv"
venv_python="$project_dir/.venv/bin/python3"
requirements=$(mktemp)
# cbor2 5.4.2 (pinned for Python < 3.12) has no wheel and fails to build
grep -v '^cbor2==5\.4\.2' "$community_path/requirements.txt" > "$requirements"
uv pip install --quiet --python "$venv_python" -r "$requirements"
rm -f "$requirements"
if grep -q '^cbor2==5\.4\.2' "$community_path/requirements.txt"; then
    uv pip install --quiet --python "$venv_python" "cbor2==5.6.2"
fi
"$venv_python" -c 'import psycopg2, lxml.etree, PIL.Image, babel, werkzeug' ||
    fatal "The virtualenv is incomplete (see the errors above)"
info "Virtualenv OK: $("$venv_python" -c 'import platform, sys; print(sys.version.split()[0], platform.machine())')"

# 4. Optional: initialized database
if $init_db; then
    info "Initializing database '$db_name' (base${lang:+, $lang})..."
    addons_path=$(grep -o '"--addons-path=[^"]*"' "$settings" | head -n 1 | sed 's/^"--addons-path=//; s/"$//')
    # An empty user/ folder is rejected by Odoo ("invalid addons directory")
    if find "$project_dir/user" -name __manifest__.py -print -quit | grep -q .; then
        addons_path="${addons_path//,user/,$project_dir/user}"
    else
        addons_path="${addons_path//,user/}"
    fi
    init_args=(-d "$db_name" -i base --stop-after-init "--addons-path=$addons_path")
    (( major < 19 )) && init_args+=(--without-demo=all)
    [[ -n "$lang" ]] && init_args+=("--load-language=$lang")
    (cd "$project_dir" && "$venv_python" "$community_path/odoo-bin" "${init_args[@]}" --log-level=warn)
fi

echo ""
echo "Project ready. Next steps:"
echo "  code \"$project_dir\""
$init_db || echo "  (the database will be created on the first launch, or rerun with --init-db)"
echo "  python3 \"$SCRIPTS_DIR/odoo_doctor.py\" \"$project_dir\""
