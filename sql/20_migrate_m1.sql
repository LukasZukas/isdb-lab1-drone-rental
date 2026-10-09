-- =====================================================================
-- VERTICAL FRAGMENTATION - data migration isdb_original -> m1_lt (M1)
-- Runs in: m1_lt
-- psql variables: orig_host, orig_port, pg_user, pg_password
--
-- The original database is attached through postgres_fdw, the M1
-- columns are copied with INSERT ... SELECT, then the link is removed.
-- =====================================================================

CREATE EXTENSION postgres_fdw;
CREATE SERVER src_original FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'orig_host', port :'orig_port', dbname 'isdb_original');
CREATE USER MAPPING FOR CURRENT_USER SERVER src_original
    OPTIONS (user :'pg_user', password :'pg_password');

CREATE SCHEMA src;
IMPORT FOREIGN SCHEMA public
    LIMIT TO (country, drone_category, drone_model, branch, customer, drone, rental, payment)
    FROM SERVER src_original INTO src;

BEGIN;

-- replicated classifiers: full copy
INSERT INTO country        SELECT country_code, name, currency_code, phone_prefix FROM src.country;
INSERT INTO drone_category SELECT category_id, name, description FROM src.drone_category;
INSERT INTO drone_model    SELECT model_id, category_id, manufacturer, model_name, max_flight_time_min,
                                  max_payload_kg, max_range_km, camera_mp, weight_g, launch_year
                           FROM src.drone_model;

-- domain tables that belong to M1
INSERT INTO branch   SELECT branch_id, name, city, country_code, address, phone, email, opened_on FROM src.branch;
INSERT INTO customer SELECT customer_id, first_name, last_name, email, phone, birth_date, country_code,
                            home_branch_id, pilot_license_no, license_class, registered_at
                     FROM src.customer;

-- vertical split: only the COMMERCIAL columns of drone (+ key + replicated FKs)
INSERT INTO drone_commercial (drone_id, model_id, branch_id, purchase_date, purchase_price,
                              daily_rate, deposit_amount, status)
SELECT drone_id, model_id, branch_id, purchase_date, purchase_price, daily_rate, deposit_amount, status
FROM src.drone;

INSERT INTO rental  SELECT rental_id, customer_id, drone_id, branch_id, start_date, end_date, total_price, status FROM src.rental;
INSERT INTO payment SELECT payment_id, rental_id, amount, method, payment_type, paid_at FROM src.payment;

COMMIT;

-- remove the temporary link to the original database
SET client_min_messages = warning;
DROP SCHEMA src CASCADE;
DROP SERVER src_original CASCADE;
DROP EXTENSION postgres_fdw;
