-- =====================================================================
-- VERTICAL FRAGMENTATION - data migration isdb_original (DBVS1) -> db21 (M2)
-- Runs in: DBVS2 / db21   (pulls the data from the OTHER DBMS instance)
-- psql variables: orig_host, orig_port, pg_user, pg_password
-- =====================================================================

CREATE EXTENSION postgres_fdw;
CREATE SERVER src_original FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'orig_host', port :'orig_port', dbname 'isdb_original');
CREATE USER MAPPING FOR CURRENT_USER SERVER src_original
    OPTIONS (user :'pg_user', password :'pg_password');

CREATE SCHEMA src;
IMPORT FOREIGN SCHEMA public
    LIMIT TO (country, drone_category, drone_model, branch, drone, employee, maintenance, flight_log)
    FROM SERVER src_original INTO src;

BEGIN;

-- replicated classifiers: full copy
INSERT INTO country        SELECT country_code, name, currency_code, phone_prefix FROM src.country;
INSERT INTO drone_category SELECT category_id, name, description FROM src.drone_category;
INSERT INTO drone_model    SELECT model_id, category_id, manufacturer, model_name, max_flight_time_min,
                                  max_payload_kg, max_range_km, camera_mp, weight_g, launch_year
                           FROM src.drone_model;

INSERT INTO branch SELECT branch_id, name, city, country_code, address, phone, email, opened_on FROM src.branch;

-- vertical split: only the TECHNICAL columns of drone (+ key + replicated FKs)
INSERT INTO drone_technical (drone_id, model_id, branch_id, serial_number, firmware_version,
                             total_flight_hours, battery_cycles, last_inspection_date, condition)
SELECT drone_id, model_id, branch_id, serial_number, firmware_version,
       total_flight_hours, battery_cycles, last_inspection_date, condition
FROM src.drone;

-- domain tables that belong to M2
INSERT INTO employee    SELECT employee_id, branch_id, first_name, last_name, email, role, certification, hired_on FROM src.employee;
INSERT INTO maintenance SELECT maintenance_id, drone_id, employee_id, maintenance_date, maintenance_type,
                               description, cost, downtime_hours
                        FROM src.maintenance;
INSERT INTO flight_log  SELECT flight_id, drone_id, rental_id, started_at, duration_min, max_altitude_m,
                               distance_km, battery_used_pct, incident_reported
                        FROM src.flight_log;

COMMIT;

SET client_min_messages = warning;
DROP SCHEMA src CASCADE;
DROP SERVER src_original CASCADE;
DROP EXTENSION postgres_fdw;
