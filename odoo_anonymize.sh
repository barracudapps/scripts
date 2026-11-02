#!/bin/bash

################################################################################
# Script:       odoo_anonymize.sh
# Description:  Creates an anonymized copy of an Odoo database, safe to share
#               or to use for debugging. The source database is never modified.
#               1. clone (database + filestore),
#               2. native "odoo-bin obfuscate" (Odoo 17+) with a random password
#                  that is never stored, plus extra personal fields (bank
#                  accounts, employee private data, custom x_ fields of
#                  contacts, mails) when they exist,
#               3. user logins replaced (admin kept, its password set to "admin"),
#               4. attachments of business records deleted and removed from
#                  the copied filestore (technical/product/company files kept),
#               5. neutralization (crons, mail servers...).
#               Only counters are printed, never data.
# Usage:        bash odoo_anonymize.sh <source_db> [target_db] [--project DIR] [--keep-attachments]
#               target_db defaults to <source_db>-anon
# Author:       Pierre LAMOTTE
# Date:         02 NOV 2026
################################################################################

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"
[[ -x "$PG_BIN/psql" ]] && export PATH="$PG_BIN:$PATH"
FILESTORE_BASE="$HOME/Library/Application Support/Odoo/filestore"

fatal() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "==> $*"; }
usage() { sed -n '/^# Usage:/,/^# Author:/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

[[ $# -ge 1 && "$1" != -* ]] || { usage; exit 1; }
source_db="$1"
shift
target_db=""
project=""
keep_attachments=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) project="${2/#\~/$HOME}"; shift 2 ;;
        --keep-attachments) keep_attachments=true; shift ;;
        -*) fatal "Unknown option: $1" ;;
        *) target_db="$1"; shift ;;
    esac
done
target_db="${target_db:-${source_db}-anon}"
[[ "$target_db" =~ ^[A-Za-z0-9_.-]+$ ]] || fatal "Invalid database name: $target_db"

sql() { psql -X -q -d "$target_db" -v ON_ERROR_STOP=1 -Atc "$1"; }

# Project providing python + odoo-bin: --project, else one using the source database
if [[ -z "$project" ]]; then
    project=$(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" dbs | awk -F'\t' -v db="$source_db" '$1 == db { print $2; exit }')
fi
[[ -n "$project" ]] || fatal "No project uses '$source_db': pass --project <dir> (same Odoo version)"
fields=()
while IFS= read -r -d '' f; do fields+=("$f"); done < <(python3 "$SCRIPTS_DIR/lib/odoo_projects.py" argv "$project")
python="${fields[0]}"; program="${fields[1]}"
addons=""
for a in "${fields[@]:2}"; do [[ "$a" == --addons-path=* ]] && addons="$a"; done
[[ -f "$(dirname "$program")/odoo/cli/obfuscate.py" ]] || fatal "This Odoo version has no 'obfuscate' command (Odoo 17+ required)"

info "Cloning '$source_db' into '$target_db'..."
bash "$SCRIPTS_DIR/odoo_db.sh" clone "$source_db" "$target_db" >/dev/null

# Extra personal fields, kept only when the column exists and holds text
extra=$(sql "
    SELECT string_agg(table_name || '.' || column_name, ',' ORDER BY table_name, column_name)
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND data_type IN ('character varying', 'text')
      AND (
        (table_name, column_name) IN (
            ('res_partner_bank', 'acc_number'), ('res_partner_bank', 'acc_holder_name'),
            ('res_partner', 'comment'), ('res_partner', 'ref'), ('res_partner', 'company_registry'),
            ('res_partner', 'phone_sanitized'), ('res_partner', 'email_normalized'),
            ('hr_employee', 'name'), ('hr_employee', 'work_email'), ('hr_employee', 'work_phone'),
            ('hr_employee', 'mobile_phone'), ('hr_employee', 'private_email'), ('hr_employee', 'private_phone'),
            ('hr_employee', 'private_street'), ('hr_employee', 'private_street2'), ('hr_employee', 'private_city'),
            ('hr_employee', 'private_zip'), ('hr_employee', 'identification_id'), ('hr_employee', 'ssnid'),
            ('hr_employee', 'passport_id'), ('hr_employee', 'permit_no'), ('hr_employee', 'emergency_contact'),
            ('hr_employee', 'emergency_phone'),
            ('mail_mail', 'body_html'), ('mail_mail', 'email_to'), ('mail_mail', 'email_cc'),
            ('account_move', 'narration'), ('sale_order', 'note')
        )
        OR (table_name = 'res_partner' AND column_name LIKE 'x\_%')
      )")

info "Obfuscating personal fields (native odoo-bin obfuscate, random password not kept)..."
password=$(openssl rand -hex 24)
# Odoo logs "Invalid fields" for its default tables that are not installed: only shown on failure
log=$(mktemp)
if ! (cd "$project" && "$python" "$program" obfuscate -d "$target_db" ${addons:+"$addons"} --pwd "$password" -y \
    --exclude res_country.name ${extra:+--fields "$extra"} --log-level=warn) >"$log" 2>&1; then
    tail -n 20 "$log" >&2
    rm -f "$log"
    fatal "obfuscate failed"
fi
rm -f "$log"
unset password

info "Replacing user logins..."
logins=$(sql "WITH updated AS (
        UPDATE res_users SET login = 'user' || id || '@example.invalid'
        WHERE login NOT IN ('admin', '__system__', 'default', 'public', 'portaltemplate')
          AND login NOT LIKE '%@example.invalid'
        RETURNING 1)
    SELECT count(*) FROM updated")
echo "    $logins login(s) replaced"

if ! $keep_attachments; then
    info "Deleting attachments of business records..."
    deleted=$(sql "WITH deleted AS (
            DELETE FROM ir_attachment
            WHERE res_model IS NOT NULL
              AND res_model NOT LIKE 'ir.%'
              AND res_model NOT IN ('res.company', 'res.lang', 'res.country', 'website', 'website.page',
                                    'theme.ir.attachment', 'web_editor.assets', 'mail.template',
                                    'product.template', 'product.product', 'product.image',
                                    'product.public.category')
            RETURNING 1)
        SELECT count(*) FROM deleted")
    echo "    $deleted attachment(s) deleted"

    # Remove from the copied filestore every file no attachment references anymore
    if [[ -d "$FILESTORE_BASE/$target_db" ]]; then
        sql "SELECT DISTINCT store_fname FROM ir_attachment WHERE store_fname IS NOT NULL" |
        python3 -c '
import os, sys
root = sys.argv[1]
keep = {line.strip() for line in sys.stdin if line.strip()}
removed = 0
for dirpath, _dirs, files in os.walk(root):
    for name in files:
        rel = os.path.relpath(os.path.join(dirpath, name), root)
        if rel not in keep and not rel.startswith("checklist"):
            os.remove(os.path.join(dirpath, name))
            removed += 1
print(f"    {removed} file(s) removed from the filestore copy")
' "$FILESTORE_BASE/$target_db"
    fi
fi

info "Resetting the admin password to 'admin'..."
# Same hashing as Odoo (passlib pbkdf2_sha512), computed with the project venv
admin_hash=$("$python" -c 'from passlib.context import CryptContext; print(CryptContext(["pbkdf2_sha512"], pbkdf2_sha512__rounds=600_000).hash("admin"))')
reset=$(psql -X -q -d "$target_db" -v ON_ERROR_STOP=1 -v hash="$admin_hash" -At <<'SQL'
WITH updated AS (UPDATE res_users SET password = :'hash' WHERE login = 'admin' RETURNING 1) SELECT count(*) FROM updated;
SQL
)
[[ "$reset" == "1" ]] || echo "[WARN] admin password not reset (no 'admin' login)" >&2

bash "$SCRIPTS_DIR/odoo_db.sh" neutralize "$target_db" --project "$project"

echo ""
echo "Anonymized copy ready: '$target_db' (login admin / admin)."
echo "Obfuscated fields: native list${extra:+ + $(tr ',' '\n' <<<"$extra" | wc -l | tr -d ' ') extra}. Share it with: odoo_db.sh dump $target_db"
