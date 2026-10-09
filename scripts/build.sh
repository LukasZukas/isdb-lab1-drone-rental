#!/usr/bin/env bash
# =====================================================================
# Builds M0 and M1 from scratch (idempotent).
#   1. isdb_original  - M0, full original DB with data (kept as control source)
#   2. m1_lt          - M1 schema, M1 columns copied from M0 with INSERT ... SELECT
#   3. m1_lvee        - clone of m1_lt (CREATE DATABASE ... TEMPLATE)
#   4. horizontal split: LT rows stay in m1_lt, LV+EE rows in m1_lvee
#   5. correctness check against M0
#
# Settings: DBVS1_HOST, DBVS1_PORT, PGUSER, PGPASSWORD (from the environment)
# =====================================================================
set -euo pipefail

SQL_DIR="${SQL_DIR:-$(cd "$(dirname "$0")/../sql" && pwd)}"
DBVS1_HOST="${DBVS1_HOST:-dbvs1}"; DBVS1_PORT="${DBVS1_PORT:-5432}"
: "${PGUSER:?set PGUSER}" "${PGPASSWORD:?set PGPASSWORD}"
export PGUSER PGPASSWORD

VARS=(-v orig_host="$DBVS1_HOST" -v orig_port="$DBVS1_PORT"
      -v dbvs1_host="$DBVS1_HOST" -v dbvs1_port="$DBVS1_PORT"
      -v pg_user="$PGUSER" -v pg_password="$PGPASSWORD")

dbvs1() { psql -X -q -v ON_ERROR_STOP=1 -h "$DBVS1_HOST" -p "$DBVS1_PORT" "${VARS[@]}" "$@"; }
step()  { printf '\n==> %s\n' "$*"; }

step "0. Clean up previous run"
for db in m1_lvee m1_lt isdb_original; do
    dbvs1 -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)"
done

step "1. M0: isdb_original (schema + data)"
dbvs1 -d postgres -c "CREATE DATABASE isdb_original" \
                  -c "COMMENT ON DATABASE isdb_original IS 'M0 original full database (control source)'"
dbvs1 -d isdb_original -f "$SQL_DIR/00_original_schema.sql"
dbvs1 -d isdb_original -f "$SQL_DIR/01_original_data.sql"

step "2. Vertical fragmentation: M1 -> m1_lt"
dbvs1 -d postgres -c "CREATE DATABASE m1_lt"
dbvs1 -d m1_lt -f "$SQL_DIR/10_m1_schema.sql"
dbvs1 -d m1_lt -f "$SQL_DIR/20_migrate_m1.sql"

step "3. Clone: m1_lvee := m1_lt"
dbvs1 -d postgres -c "CREATE DATABASE m1_lvee TEMPLATE m1_lt"

step "4. Horizontal fragmentation by branch.country_code"
dbvs1 -d m1_lt   -f "$SQL_DIR/30_horizontal_m1_lt.sql"
dbvs1 -d m1_lvee -f "$SQL_DIR/31_horizontal_m1_lvee.sql"
dbvs1 -d postgres -c "COMMENT ON DATABASE m1_lt   IS 'M1-H1 Customers & Rentals: Lithuania (branch.country_code = ''LT'')'" \
                  -c "COMMENT ON DATABASE m1_lvee IS 'M1-H2 Customers & Rentals: Latvia + Estonia (branch.country_code IN (''LV'',''EE''))'"

step "5. Correctness check (M0 vs m1_lt + m1_lvee)"
dbvs1 -d isdb_original -f "$SQL_DIR/50_verify.sql"

step "DONE"
