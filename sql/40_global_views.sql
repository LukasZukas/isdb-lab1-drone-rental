-- =====================================================================
-- GLOBAL (coordinator) database - distributed access to all 4 fragments
-- Runs in: DBVS1 / isdb_global
-- psql variables: dbvs1_host, dbvs1_port, dbvs2_host, dbvs2_port, pg_user, pg_password
--
-- Holds NO data. Schemas db11, db12, db21, db22 contain postgres_fdw
-- foreign tables pointing at the fragments; schema "global" contains
-- views that reconstruct the ORIGINAL relations:
--   horizontal fragments -> UNION ALL
--   vertical fragments   -> JOIN on the primary key (drone_id)
-- =====================================================================

CREATE EXTENSION postgres_fdw;

CREATE SERVER frag_db11 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host :'dbvs1_host', port :'dbvs1_port', dbname 'db11');
CREATE SERVER frag_db12 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host :'dbvs1_host', port :'dbvs1_port', dbname 'db12');
CREATE SERVER frag_db21 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host :'dbvs2_host', port :'dbvs2_port', dbname 'db21');
CREATE SERVER frag_db22 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host :'dbvs2_host', port :'dbvs2_port', dbname 'db22');

CREATE USER MAPPING FOR PUBLIC SERVER frag_db11 OPTIONS (user :'pg_user', password :'pg_password');
CREATE USER MAPPING FOR PUBLIC SERVER frag_db12 OPTIONS (user :'pg_user', password :'pg_password');
CREATE USER MAPPING FOR PUBLIC SERVER frag_db21 OPTIONS (user :'pg_user', password :'pg_password');
CREATE USER MAPPING FOR PUBLIC SERVER frag_db22 OPTIONS (user :'pg_user', password :'pg_password');

CREATE SCHEMA db11; COMMENT ON SCHEMA db11 IS 'Foreign tables -> DBVS1/db11 (M1, Lithuania)';
CREATE SCHEMA db12; COMMENT ON SCHEMA db12 IS 'Foreign tables -> DBVS1/db12 (M1, Latvia + Estonia)';
CREATE SCHEMA db21; COMMENT ON SCHEMA db21 IS 'Foreign tables -> DBVS2/db21 (M2, Lithuania)';
CREATE SCHEMA db22; COMMENT ON SCHEMA db22 IS 'Foreign tables -> DBVS2/db22 (M2, Latvia + Estonia)';

IMPORT FOREIGN SCHEMA public FROM SERVER frag_db11 INTO db11;
IMPORT FOREIGN SCHEMA public FROM SERVER frag_db12 INTO db12;
IMPORT FOREIGN SCHEMA public FROM SERVER frag_db21 INTO db21;
IMPORT FOREIGN SCHEMA public FROM SERVER frag_db22 INTO db22;

CREATE SCHEMA global;
COMMENT ON SCHEMA global IS 'Views that reconstruct the original (unfragmented) database from the 4 fragments';

-- classifiers are fully replicated -> any one replica is the global relation
CREATE VIEW global.country        AS SELECT * FROM db11.country;
CREATE VIEW global.drone_category AS SELECT * FROM db11.drone_category;
CREATE VIEW global.drone_model    AS SELECT * FROM db11.drone_model;

-- horizontally fragmented relations -> union of the fragments
CREATE VIEW global.branch      AS SELECT * FROM db11.branch      UNION ALL SELECT * FROM db12.branch;
CREATE VIEW global.customer    AS SELECT * FROM db11.customer    UNION ALL SELECT * FROM db12.customer;
CREATE VIEW global.rental      AS SELECT * FROM db11.rental      UNION ALL SELECT * FROM db12.rental;
CREATE VIEW global.payment     AS SELECT * FROM db11.payment     UNION ALL SELECT * FROM db12.payment;
CREATE VIEW global.employee    AS SELECT * FROM db21.employee    UNION ALL SELECT * FROM db22.employee;
CREATE VIEW global.maintenance AS SELECT * FROM db21.maintenance UNION ALL SELECT * FROM db22.maintenance;
CREATE VIEW global.flight_log  AS SELECT * FROM db21.flight_log  UNION ALL SELECT * FROM db22.flight_log;

-- vertically AND horizontally fragmented relation -> union per half, then join on the key
CREATE VIEW global.drone AS
SELECT c.drone_id, c.model_id, c.branch_id, t.serial_number, c.purchase_date, c.purchase_price,
       c.daily_rate, c.deposit_amount, c.status, t.firmware_version, t.total_flight_hours,
       t.battery_cycles, t.last_inspection_date, t.condition
FROM (SELECT * FROM db11.drone_commercial UNION ALL SELECT * FROM db12.drone_commercial) c   -- M1 half, DBVS1
JOIN (SELECT * FROM db21.drone_technical  UNION ALL SELECT * FROM db22.drone_technical)  t   -- M2 half, DBVS2
  ON t.drone_id = c.drone_id;

-- row counts of every table in every fragment (live, via the foreign tables)
CREATE FUNCTION global.fragment_row_counts()
RETURNS TABLE (fragment text, table_name text, row_count bigint)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT foreign_table_schema AS s, foreign_table_name AS t
             FROM information_schema.foreign_tables
             WHERE foreign_table_schema IN ('db11', 'db12', 'db21', 'db22')
             ORDER BY 1, 2
    LOOP
        fragment := upper(r.s);
        table_name := r.t;
        EXECUTE format('SELECT count(*) FROM %I.%I', r.s, r.t) INTO row_count;
        RETURN NEXT;
    END LOOP;
END $$;

CREATE VIEW global.fragment_overview AS
SELECT table_name,
       sum(row_count) FILTER (WHERE fragment = 'DB11') AS "DB11 (M1, LT)",
       sum(row_count) FILTER (WHERE fragment = 'DB12') AS "DB12 (M1, LV+EE)",
       sum(row_count) FILTER (WHERE fragment = 'DB21') AS "DB21 (M2, LT)",
       sum(row_count) FILTER (WHERE fragment = 'DB22') AS "DB22 (M2, LV+EE)"
FROM global.fragment_row_counts()
GROUP BY table_name
ORDER BY table_name;
