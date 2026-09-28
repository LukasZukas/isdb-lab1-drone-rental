-- =====================================================================
-- HORIZONTAL FRAGMENTATION of M2 - fragment DB22 = LATVIA + ESTONIA
-- Runs in: DBVS2 / db22   (a clone of db21 made with CREATE DATABASE ... TEMPLATE)
-- =====================================================================
BEGIN;

DELETE FROM flight_log f
USING drone_technical d JOIN branch b ON b.branch_id = d.branch_id
WHERE f.drone_id = d.drone_id AND b.country_code = 'LT';

DELETE FROM maintenance m
USING drone_technical d JOIN branch b ON b.branch_id = d.branch_id
WHERE m.drone_id = d.drone_id AND b.country_code = 'LT';

DELETE FROM drone_technical d USING branch b
WHERE d.branch_id = b.branch_id AND b.country_code = 'LT';

DELETE FROM employee e USING branch b
WHERE e.branch_id = b.branch_id AND b.country_code = 'LT';

DELETE FROM branch WHERE country_code = 'LT';

COMMIT;
