-- =====================================================================
-- CORRECTNESS CHECK of the fragmentation (run before the original is dropped)
-- Runs in: DBVS1 / isdb_global
-- psql variables: dbvs1_host, dbvs1_port, pg_user, pg_password
--
-- For every original relation R and its reconstruction R' (global view):
--   completeness + reconstruction : count(R) = count(R') and R EXCEPT R' = {} and R' EXCEPT R = {}
--   disjointness                  : no key appears in both horizontal fragments
-- Any failure raises an exception (the build stops).
-- =====================================================================

CREATE SERVER src_original FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host :'dbvs1_host', port :'dbvs1_port', dbname 'isdb_original');
CREATE USER MAPPING FOR PUBLIC SERVER src_original OPTIONS (user :'pg_user', password :'pg_password');
CREATE SCHEMA orig;
IMPORT FOREIGN SCHEMA public FROM SERVER src_original INTO orig;

DO $$
DECLARE
    t text;
    n_orig bigint; n_glob bigint; missing bigint; extra bigint; overlap bigint;
    keys constant jsonb := '{"branch":"branch_id","customer":"customer_id","rental":"rental_id","payment":"payment_id",
                             "employee":"employee_id","maintenance":"maintenance_id","flight_log":"flight_id"}';
BEGIN
    FOREACH t IN ARRAY ARRAY['country', 'drone_category', 'drone_model', 'branch', 'customer', 'drone',
                             'rental', 'payment', 'employee', 'maintenance', 'flight_log']
    LOOP
        EXECUTE format('SELECT count(*) FROM orig.%I', t) INTO n_orig;
        EXECUTE format('SELECT count(*) FROM global.%I', t) INTO n_glob;
        EXECUTE format('SELECT count(*) FROM (SELECT * FROM orig.%I EXCEPT SELECT * FROM global.%I) x', t, t) INTO missing;
        EXECUTE format('SELECT count(*) FROM (SELECT * FROM global.%I EXCEPT SELECT * FROM orig.%I) x', t, t) INTO extra;
        IF n_orig <> n_glob OR missing <> 0 OR extra <> 0 THEN
            RAISE EXCEPTION 'FAILED %: original=% reconstructed=% missing=% extra=%', t, n_orig, n_glob, missing, extra;
        END IF;
        RAISE NOTICE 'OK  %  (% rows: original = reconstructed)', rpad(t, 15), n_orig;
    END LOOP;

    -- horizontal fragments must be disjoint
    FOR t IN SELECT jsonb_object_keys(keys) LOOP
        EXECUTE format(
            'SELECT count(*) FROM %1$s.%2$I a JOIN %3$s.%2$I b USING (%4$I)',
            CASE WHEN t IN ('employee', 'maintenance', 'flight_log') THEN 'db21' ELSE 'db11' END, t,
            CASE WHEN t IN ('employee', 'maintenance', 'flight_log') THEN 'db22' ELSE 'db12' END, keys ->> t)
        INTO overlap;
        IF overlap <> 0 THEN
            RAISE EXCEPTION 'FAILED disjointness of %: % keys in both fragments', t, overlap;
        END IF;
    END LOOP;
    SELECT count(*) INTO overlap FROM db11.drone_commercial a JOIN db12.drone_commercial b USING (drone_id);
    IF overlap <> 0 THEN RAISE EXCEPTION 'FAILED disjointness of drone_commercial'; END IF;
    SELECT count(*) INTO overlap FROM db21.drone_technical a JOIN db22.drone_technical b USING (drone_id);
    IF overlap <> 0 THEN RAISE EXCEPTION 'FAILED disjointness of drone_technical'; END IF;
    RAISE NOTICE 'OK  horizontal fragments are disjoint';

    -- vertical fragments must contain the same keys
    SELECT count(*) INTO overlap FROM (
        (SELECT drone_id FROM db11.drone_commercial UNION ALL SELECT drone_id FROM db12.drone_commercial)
        EXCEPT
        (SELECT drone_id FROM db21.drone_technical UNION ALL SELECT drone_id FROM db22.drone_technical)) x;
    IF overlap <> 0 THEN RAISE EXCEPTION 'FAILED vertical fragments have different drone_id sets'; END IF;
    RAISE NOTICE 'OK  vertical fragments drone_commercial / drone_technical have the same keys';
END $$;

SET client_min_messages = warning;
DROP SCHEMA orig CASCADE;
DROP SERVER src_original CASCADE;
