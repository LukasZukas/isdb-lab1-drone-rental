-- =====================================================================
-- CORRECTNESS CHECK of M1 (M0 projection = m1_lt UNION ALL m1_lvee)
-- Runs in: isdb_original
-- psql variables: dbvs1_host, dbvs1_port, pg_user, pg_password
--
-- For every M1 table: count, EXCEPT both ways, and the two horizontal
-- fragments must not share a key. Any failure stops the build.
-- The fdw link is temporary and is removed at the end.
-- =====================================================================

CREATE EXTENSION postgres_fdw;
CREATE SERVER srv_lt   FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host :'dbvs1_host', port :'dbvs1_port', dbname 'm1_lt');
CREATE SERVER srv_lvee FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host :'dbvs1_host', port :'dbvs1_port', dbname 'm1_lvee');
CREATE USER MAPPING FOR CURRENT_USER SERVER srv_lt   OPTIONS (user :'pg_user', password :'pg_password');
CREATE USER MAPPING FOR CURRENT_USER SERVER srv_lvee OPTIONS (user :'pg_user', password :'pg_password');
CREATE SCHEMA h1;
CREATE SCHEMA h2;
IMPORT FOREIGN SCHEMA public FROM SERVER srv_lt   INTO h1;
IMPORT FOREIGN SCHEMA public FROM SERVER srv_lvee INTO h2;

DO $$
DECLARE
    r record;
    n_orig bigint; n_frag bigint; missing bigint; extra bigint; overlap bigint;
BEGIN
    -- M1 table, the M0 query that gives its content, key, horizontally fragmented?
    FOR r IN SELECT * FROM (VALUES
        ('country',          'SELECT * FROM public.country',        'country_code', false),
        ('drone_category',   'SELECT * FROM public.drone_category', 'category_id',  false),
        ('drone_model',      'SELECT * FROM public.drone_model',    'model_id',     false),
        ('branch',           'SELECT * FROM public.branch',         'branch_id',    true),
        ('customer',         'SELECT * FROM public.customer',       'customer_id',  true),
        ('drone_commercial', 'SELECT drone_id, model_id, branch_id, purchase_date, purchase_price,
                                     daily_rate, deposit_amount, status FROM public.drone', 'drone_id', true),
        ('rental',           'SELECT * FROM public.rental',         'rental_id',    true),
        ('payment',          'SELECT * FROM public.payment',        'payment_id',   true)
    ) v(tbl, src, key, horizontal)
    LOOP
        IF r.horizontal THEN
            -- union of the two horizontal fragments must equal the M0 projection
            EXECUTE format('SELECT count(*) FROM (%s) x', r.src) INTO n_orig;
            EXECUTE format('SELECT (SELECT count(*) FROM h1.%1$I) + (SELECT count(*) FROM h2.%1$I)', r.tbl) INTO n_frag;
            EXECUTE format('SELECT count(*) FROM ((%s) EXCEPT (SELECT * FROM h1.%2$I UNION ALL SELECT * FROM h2.%2$I)) x', r.src, r.tbl) INTO missing;
            EXECUTE format('SELECT count(*) FROM ((SELECT * FROM h1.%2$I UNION ALL SELECT * FROM h2.%2$I) EXCEPT (%1$s)) x', r.src, r.tbl) INTO extra;
            EXECUTE format('SELECT count(*) FROM h1.%1$I a JOIN h2.%1$I b USING (%2$I)', r.tbl, r.key) INTO overlap;
        ELSE
            -- classifiers: each fragment holds a full copy
            EXECUTE format('SELECT count(*) FROM (%s) x', r.src) INTO n_orig;
            EXECUTE format('SELECT count(*) FROM h1.%I', r.tbl) INTO n_frag;
            EXECUTE format('SELECT count(*) FROM ((%1$s) EXCEPT SELECT * FROM h1.%2$I) x', r.src, r.tbl) INTO missing;
            EXECUTE format('SELECT count(*) FROM ((%1$s) EXCEPT SELECT * FROM h2.%2$I) x', r.src, r.tbl) INTO extra;
            overlap := 0;
        END IF;
        IF n_orig <> n_frag OR missing <> 0 OR extra <> 0 OR overlap <> 0 THEN
            RAISE EXCEPTION 'FAILED %: M0=% fragments=% missing=% extra=% overlap=%',
                r.tbl, n_orig, n_frag, missing, extra, overlap;
        END IF;
        RAISE NOTICE 'OK  %  % rows  %', rpad(r.tbl, 17), lpad(n_orig::text, 3),
            CASE WHEN r.horizontal THEN '(m1_lt + m1_lvee, disjoint)' ELSE '(full copy in both)' END;
    END LOOP;
END $$;

-- row counts per fragment
SELECT t AS "table",
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM h1.%I', t), false, true, '')))[1]::text::int AS m1_lt,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM h2.%I', t), false, true, '')))[1]::text::int AS m1_lvee
FROM unnest(ARRAY['country', 'drone_category', 'drone_model', 'branch', 'customer',
                  'drone_commercial', 'rental', 'payment']) t;

SET client_min_messages = warning;
DROP SCHEMA h1 CASCADE;
DROP SCHEMA h2 CASCADE;
DROP SERVER srv_lt CASCADE;
DROP SERVER srv_lvee CASCADE;
DROP EXTENSION postgres_fdw;
