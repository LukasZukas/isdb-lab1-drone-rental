-- =====================================================================
-- DEMO QUERIES for the defence - open in pgAdmin Query Tool on
--   DBVS1 -> Databases -> isdb_global
-- Run one statement at a time: highlight it and press F5 (F5 runs only the selection).
-- =====================================================================

-- 1. Where is the data? Row count of every table in every fragment (live via postgres_fdw)
SELECT * FROM global.fragment_overview;


-- 2. HORIZONTAL fragmentation criterion: branch.country_code
SELECT 'DB11' AS fragment, branch_id, name, country_code FROM db11.branch
UNION ALL
SELECT 'DB12', branch_id, name, country_code FROM db12.branch
ORDER BY fragment, branch_id;

-- derived fragmentation: every customer / rental lives in the fragment of its branch
SELECT 'DB11' AS fragment, b.country_code, count(*) AS rentals
FROM db11.rental r JOIN db11.branch b USING (branch_id) GROUP BY 1, 2
UNION ALL
SELECT 'DB12', b.country_code, count(*)
FROM db12.rental r JOIN db12.branch b USING (branch_id) GROUP BY 1, 2
ORDER BY 1, 2;


-- 3. VERTICAL fragmentation: one drone = two halves on two different DBMS instances
SELECT 'M1 drone_commercial  (DBVS1 / db11)' AS half, to_jsonb(c) AS attributes
FROM db11.drone_commercial c WHERE drone_id = 1
UNION ALL
SELECT 'M2 drone_technical   (DBVS2 / db21)', to_jsonb(t)
FROM db21.drone_technical t WHERE drone_id = 1;

-- ...and the original 14-attribute row reconstructed with a JOIN on drone_id
SELECT * FROM global.drone WHERE drone_id = 1;


-- 4. The whole original table reconstructed (UNION ALL of horizontal + JOIN of vertical)
SELECT * FROM global.drone ORDER BY drone_id;


-- 5. DISTRIBUTED QUERY across both DBMS: who flies the most?
--    customer, rental, branch -> M1 on DBVS1;  flight_log -> M2 on DBVS2
SELECT c.first_name || ' ' || c.last_name AS customer,
       b.city,
       count(f.flight_id)  AS flights,
       sum(f.duration_min) AS minutes_flown,
       sum(f.distance_km)  AS km_flown
FROM global.flight_log f
JOIN global.rental   r ON r.rental_id   = f.rental_id
JOIN global.customer c ON c.customer_id = r.customer_id
JOIN global.branch   b ON b.branch_id   = r.branch_id
GROUP BY 1, 2
ORDER BY minutes_flown DESC
LIMIT 10;


-- 6. DISTRIBUTED QUERY: income (M1) vs. maintenance cost (M2) per drone model
WITH income AS (
    SELECT r.drone_id, sum(p.amount) AS income
    FROM global.rental r JOIN global.payment p USING (rental_id)
    WHERE p.payment_type IN ('rental_fee', 'damage_fee')
    GROUP BY r.drone_id
), costs AS (
    SELECT drone_id, sum(cost) AS maintenance_cost
    FROM global.maintenance GROUP BY drone_id
)
SELECT m.manufacturer || ' ' || m.model_name AS model,
       count(*)                           AS drones,
       coalesce(sum(i.income), 0)         AS income_eur,
       coalesce(sum(c.maintenance_cost), 0) AS maintenance_eur,
       sum(d.total_flight_hours)          AS flight_hours
FROM global.drone d
JOIN global.drone_model m USING (model_id)
LEFT JOIN income i USING (drone_id)
LEFT JOIN costs  c USING (drone_id)
GROUP BY 1
ORDER BY income_eur DESC;


-- 7. How PostgreSQL executes it: the plan shows a Foreign Scan sent to each fragment
EXPLAIN (VERBOSE, COSTS OFF)
SELECT * FROM global.drone WHERE drone_id = 1;


-- 8. DISTRIBUTED DATA MANIPULATION in one transaction on both DBMS:
--    a new drone arrives in Riga (branch 11 -> fragments DB12 + DB22)
--    run BEGIN..SELECT together, then run ROLLBACK separately
BEGIN;
INSERT INTO db12.drone_commercial (drone_id, model_id, branch_id, purchase_date, purchase_price,
                                   daily_rate, deposit_amount, status)
VALUES (41, 2, 11, current_date, 1099, 38, 330, 'available');
INSERT INTO db22.drone_technical (drone_id, model_id, branch_id, serial_number, firmware_version,
                                  total_flight_hours, battery_cycles, last_inspection_date, condition)
VALUES (41, 2, 11, '1581F0000000041', '01.03.0500', 0, 0, current_date, 'excellent');
SELECT * FROM global.drone WHERE drone_id = 41;   -- visible as ONE row again
ROLLBACK;                                          -- undo on both servers
