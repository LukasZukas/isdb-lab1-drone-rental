-- =====================================================================
-- HORIZONTAL FRAGMENTATION of M2 - fragment DB21 = LITHUANIA
-- Runs in: DBVS2 / db21
--
-- Same criterion as M1 (branch.country_code = 'LT'), so DB11 and DB21
-- hold the two vertical halves of exactly the same Lithuanian drones.
-- Derived fragmentation: drone_technical, employee, maintenance, flight_log
-- =====================================================================
BEGIN;

DELETE FROM flight_log f
USING drone_technical d JOIN branch b ON b.branch_id = d.branch_id
WHERE f.drone_id = d.drone_id AND b.country_code <> 'LT';

DELETE FROM maintenance m
USING drone_technical d JOIN branch b ON b.branch_id = d.branch_id
WHERE m.drone_id = d.drone_id AND b.country_code <> 'LT';

DELETE FROM drone_technical d USING branch b
WHERE d.branch_id = b.branch_id AND b.country_code <> 'LT';

DELETE FROM employee e USING branch b
WHERE e.branch_id = b.branch_id AND b.country_code <> 'LT';

DELETE FROM branch WHERE country_code <> 'LT';

COMMIT;
