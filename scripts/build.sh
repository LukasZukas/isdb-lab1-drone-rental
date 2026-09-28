#!/usr/bin/env bash
# =====================================================================
# Builds the whole distributed database from scratch (idempotent).
#
# Scenario 2 of the lab task:
#   1. full original DB (isdb_original) on DBVS1, filled with data
#   2. vertical fragments: db11 (M1) on DBVS1, db21 (M2) on DBVS2, data moved with queries
#   3. clones: db12 := db11, db22 := db21  (CREATE DATABASE ... TEMPLATE)
#   4. horizontal fragmentation: LT rows in db11/db21, LV+EE rows in db12/db22
#   5. isdb_global coordinator DB with postgres_fdw + reconstruction views
#   6. correctness check, then the original DB is dropped
#
# Connection settings (defaults = docker-compose network):
#   DBVS1_HOST/DBVS1_PORT, DBVS2_HOST/DBVS2_PORT  - where psql connects
#   FDW1_HOST/FDW1_PORT,   FDW2_HOST/FDW2_PORT    - how the servers reach each other
#   PGUSER, PGPASSWORD, KEEP_ORIGINAL=1 to keep isdb_original
# =====================================================================
set -euo pipefail

SQL_DIR="${SQL_DIR:-$(cd "$(dirname "$0")/../sql" && pwd)}"
DBVS1_HOST="${DBVS1_HOST:-dbvs1}"; DBVS1_PORT="${DBVS1_PORT:-5432}"
DBVS2_HOST="${DBVS2_HOST:-dbvs2}"; DBVS2_PORT="${DBVS2_PORT:-5432}"
FDW1_HOST="${FDW1_HOST:-$DBVS1_HOST}"; FDW1_PORT="${FDW1_PORT:-$DBVS1_PORT}"
FDW2_HOST="${FDW2_HOST:-$DBVS2_HOST}"; FDW2_PORT="${FDW2_PORT:-$DBVS2_PORT}"
export PGUSER="${PGUSER:-postgres}" PGPASSWORD="${PGPASSWORD:-postgres}"

VARS=(-v orig_host="$FDW1_HOST" -v orig_port="$FDW1_PORT"
      -v dbvs1_host="$FDW1_HOST" -v dbvs1_port="$FDW1_PORT"
      -v dbvs2_host="$FDW2_HOST" -v dbvs2_port="$FDW2_PORT"
      -v pg_user="$PGUSER" -v pg_password="$PGPASSWORD")

dbvs1() { psql -X -q -v ON_ERROR_STOP=1 -h "$DBVS1_HOST" -p "$DBVS1_PORT" "${VARS[@]}" "$@"; }
dbvs2() { psql -X -q -v ON_ERROR_STOP=1 -h "$DBVS2_HOST" -p "$DBVS2_PORT" "${VARS[@]}" "$@"; }
step()  { printf '\n==> %s\n' "$*"; }

step "0. Clean up previous run"
dbvs1 -d postgres -c "DROP DATABASE IF EXISTS isdb_global WITH (FORCE)" \
                  -c "DROP DATABASE IF EXISTS db12 WITH (FORCE)" \
                  -c "DROP DATABASE IF EXISTS db11 WITH (FORCE)" \
                  -c "DROP DATABASE IF EXISTS isdb_original WITH (FORCE)"
dbvs2 -d postgres -c "DROP DATABASE IF EXISTS db22 WITH (FORCE)" \
                  -c "DROP DATABASE IF EXISTS db21 WITH (FORCE)"

step "1. Original database isdb_original (DBVS1): schema M0 + data"
dbvs1 -d postgres -c "CREATE DATABASE isdb_original"
dbvs1 -d isdb_original -f "$SQL_DIR/00_original_schema.sql"
dbvs1 -d isdb_original -f "$SQL_DIR/01_original_data.sql"

step "2. Vertical fragmentation: db11 <- M1 (DBVS1), db21 <- M2 (DBVS2)"
dbvs1 -d postgres -c "CREATE DATABASE db11"
dbvs2 -d postgres -c "CREATE DATABASE db21"
dbvs1 -d db11 -f "$SQL_DIR/10_m1_schema.sql"
dbvs2 -d db21 -f "$SQL_DIR/11_m2_schema.sql"
dbvs1 -d db11 -f "$SQL_DIR/20_migrate_m1.sql"
dbvs2 -d db21 -f "$SQL_DIR/21_migrate_m2.sql"

step "3. Identical clones: db12 := db11 (DBVS1), db22 := db21 (DBVS2)"
dbvs1 -d postgres -c "CREATE DATABASE db12 TEMPLATE db11"
dbvs2 -d postgres -c "CREATE DATABASE db22 TEMPLATE db21"

step "4. Horizontal fragmentation by branch.country_code: LT -> db11/db21, LV+EE -> db12/db22"
dbvs1 -d db11 -f "$SQL_DIR/30_horizontal_db11.sql"
dbvs1 -d db12 -f "$SQL_DIR/31_horizontal_db12.sql"
dbvs2 -d db21 -f "$SQL_DIR/32_horizontal_db21.sql"
dbvs2 -d db22 -f "$SQL_DIR/33_horizontal_db22.sql"
dbvs1 -d postgres -c "COMMENT ON DATABASE db11 IS 'M1 Customers & Rentals | horizontal fragment: Lithuania (branch.country_code = ''LT'')'" \
                  -c "COMMENT ON DATABASE db12 IS 'M1 Customers & Rentals | horizontal fragment: Latvia + Estonia (branch.country_code <> ''LT'')'"
dbvs2 -d postgres -c "COMMENT ON DATABASE db21 IS 'M2 Fleet & Maintenance | horizontal fragment: Lithuania (branch.country_code = ''LT'')'" \
                  -c "COMMENT ON DATABASE db22 IS 'M2 Fleet & Maintenance | horizontal fragment: Latvia + Estonia (branch.country_code <> ''LT'')'"

step "5. Coordinator database isdb_global (DBVS1): postgres_fdw + reconstruction views"
dbvs1 -d postgres -c "CREATE DATABASE isdb_global" \
                  -c "COMMENT ON DATABASE isdb_global IS 'Distributed access layer: foreign tables to db11/db12/db21/db22 + global views (no own data)'"
dbvs1 -d isdb_global -f "$SQL_DIR/40_global_views.sql"

step "6. Correctness check (original vs. reconstructed from fragments)"
dbvs1 -d isdb_global -f "$SQL_DIR/50_verify.sql"
dbvs1 -d isdb_global -c "SELECT * FROM global.fragment_overview"

if [[ "${KEEP_ORIGINAL:-0}" != "1" ]]; then
    step "7. Migration verified -> dropping the original database isdb_original"
    dbvs1 -d postgres -c "DROP DATABASE isdb_original WITH (FORCE)"
fi

step "DONE"
