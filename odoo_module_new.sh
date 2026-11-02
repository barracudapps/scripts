#!/bin/bash

################################################################################
# Script:       odoo_module_new.sh
# Description:  Creates a new custom Odoo module in the user/ folder of the
#               current project, following the project conventions: manifest
#               keys and order, author/license/category taken from the
#               existing manifests, version-specific idioms (list/tree views,
#               ir.access.csv in Odoo 20, ir.model.access.csv before).
#               Only what is asked is generated (no placeholder files).
# Usage:        bash odoo_module_new.sh <module_name> [options]
#               --depends a,b      dependencies (default: base)
#               --model x.y        add a model with its access rights
#               --views            with --model: list/form views, action, menu
#               --summary TEXT     manifest summary
#               --author NAME      default: most common author in user/
#               -C DIR             project directory (default: current directory)
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

fatal() { echo "[ERROR] $*" >&2; exit 1; }
usage() { sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

[[ $# -ge 1 && "$1" != -* ]] || { usage; [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; exit $?; }
module="$1"
shift
depends="base"
model=""
views=false
summary=""
author=""
project="$PWD"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --depends) depends="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        --views) views=true; shift ;;
        --summary) summary="$2"; shift 2 ;;
        --author) author="$2"; shift 2 ;;
        -C) project="${2/#\~/$HOME}"; shift 2 ;;
        *) fatal "Unknown option: $1" ;;
    esac
done

[[ "$module" =~ ^[a-z][a-z0-9_]*$ ]] || fatal "Module name must be snake_case: $module"
[[ -z "$model" || "$model" =~ ^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$ ]] || fatal "Invalid model name: $model"
$views && [[ -z "$model" ]] && fatal "--views needs --model"

# Project root: folder holding .odoo-project.json (current folder or a parent)
root="$project"
while [[ "$root" != "/" && ! -f "$root/.odoo-project.json" ]]; do root=$(dirname "$root"); done
[[ -f "$root/.odoo-project.json" ]] || fatal "No .odoo-project.json found from $project"
addons_dir="$root/user"
target="$addons_dir/$module"
[[ -e "$target" ]] && fatal "$target already exists"

version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["community"]["version"])' "$root/.odoo-project.json")
major="${version%%.*}"

# Conventions of the existing manifests (most common value), else defaults
manifest_value() {
    local key="$1" default="$2" value
    value=$(find "$addons_dir" -maxdepth 2 -name __manifest__.py -exec grep -h "'$key'" {} + 2>/dev/null |
        sed -E "s/.*'$key'[[:space:]]*:[[:space:]]*['\"]([^'\"]*)['\"].*/\1/" | sort | uniq -c | sort -rn | awk 'NR == 1 { $1 = ""; sub(/^ /, ""); print }')
    printf '%s' "${value:-$default}"
}
author="${author:-$(manifest_value author "BarracudApps")}"
license=$(manifest_value license "OPL-1")
category=$(manifest_value category "Customizations")

# Warn when the client prefix differs from the existing modules
prefix="${module%%_*}"
other_prefixes=""
for existing in "$addons_dir"/*_*/; do
    [[ -f "$existing/__manifest__.py" ]] || continue
    name=$(basename "$existing")
    [[ "${name%%_*}" == "$prefix" ]] && { other_prefixes=""; break; }
    other_prefixes+="${other_prefixes:+,}${name%%_*}"
done
if [[ -n "$other_prefixes" ]]; then
    echo "[WARN] Existing modules use another prefix ($(tr ',' '\n' <<<"$other_prefixes" | sort -u | paste -sd, -)): check the client prefix of '$module'." >&2
fi

title=$(printf '%s' "$module" | tr '_' ' ' | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2) } 1')
mkdir -p "$target"

data_lines=""
if [[ -n "$model" ]]; then
    model_us="${model//./_}"
    model_title=$(printf '%s' "$model" | tr '._' '  ' | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2) } 1')
    class_name="${model_title// /}"
    if (( major >= 20 )); then
        security_file="security/ir.access.csv"
    else
        security_file="security/ir.model.access.csv"
    fi
    data_lines="        '$security_file',"$'\n'
    $views && data_lines+="        'views/${model_us}_views.xml',"$'\n'
fi

depends_lines=""
IFS=',' read -ra deps <<<"$depends"
for dep in $(printf '%s\n' "${deps[@]}" | sed 's/ //g' | sort -u); do
    depends_lines+="        '$dep',"$'\n'
done

{
    echo "{"
    echo "    'name': \"$title\","
    echo "    'summary': \"${summary:-$title}\","
    echo "    'description': \"\"\""
    echo "${summary:-$title}"
    echo "    \"\"\","
    echo "    'author': \"$author\","
    echo "    'website': \"\","
    echo "    'category': \"$category\","
    echo "    'version': '1.0',"
    echo "    'license': '$license',"
    echo "    'depends': ["
    printf '%s' "$depends_lines"
    echo "    ],"
    echo "    'data': ["
    printf '%s' "$data_lines"
    echo "    ],"
    echo "    'installable': True,"
    echo "    'application': False,"
    echo "    'auto_install': False,"
    echo "}"
} > "$target/__manifest__.py"

if [[ -z "$model" ]]; then
    : > "$target/__init__.py"
else
    echo "from . import models" > "$target/__init__.py"
    mkdir -p "$target/models" "$target/security"
    echo "from . import $model_us" > "$target/models/__init__.py"
    cat > "$target/models/$model_us.py" <<EOF
from odoo import fields, models


class $class_name(models.Model):
    _name = '$model'
    _description = "$model_title"

    name = fields.Char(
        string="Name",
        required=True,
    )
EOF
    if (( major >= 20 )); then
        cat > "$target/$security_file" <<EOF
id,name,model_id,group_id/id,operation,domain
${model_us}_user,$model_title: read,$model,base.group_user,r,
${model_us}_system,$model_title: all,$model,base.group_system,crud,
EOF
    else
        cat > "$target/$security_file" <<EOF
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_${model_us}_user,$model user,model_${model_us},base.group_user,1,0,0,0
access_${model_us}_system,$model system,model_${model_us},base.group_system,1,1,1,1
EOF
    fi
fi

if $views; then
    list_tag="list"
    (( major < 18 )) && list_tag="tree"
    mkdir -p "$target/views"
    cat > "$target/views/${model_us}_views.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_${model_us}_list" model="ir.ui.view">
        <field name="name">$model.list</field>
        <field name="model">$model</field>
        <field name="arch" type="xml">
            <$list_tag>
                <field name="name"/>
            </$list_tag>
        </field>
    </record>

    <record id="view_${model_us}_form" model="ir.ui.view">
        <field name="name">$model.form</field>
        <field name="model">$model</field>
        <field name="arch" type="xml">
            <form>
                <sheet>
                    <group>
                        <field name="name"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_${model_us}" model="ir.actions.act_window">
        <field name="name">$model_title</field>
        <field name="res_model">$model</field>
        <field name="view_mode">$list_tag,form</field>
    </record>

    <menuitem
        id="menu_${model_us}"
        name="$model_title"
        action="action_${model_us}"
        sequence="100"
    />
</odoo>
EOF
fi

echo "Module created: $target"
find "$target" -type f | sed "s|^$target/|  |" | sort
echo "Next: bash $(dirname "$0")/odoo_run.sh -C \"$root\" -i $module"
