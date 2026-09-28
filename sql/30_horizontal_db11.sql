-- =====================================================================
-- HORIZONTAL FRAGMENTATION of M1 - fragment DB11 = LITHUANIA
-- Runs in: DBVS1 / db11
--
-- Primary horizontal fragmentation : branch   WHERE country_code =  'LT'
-- Derived fragmentation (semi-join) : customer, drone_commercial, rental, payment
-- Classifiers (country, drone_category, drone_model) stay complete.
-- Rows of the other fragment are deleted child-first so FKs stay valid.
-- =====================================================================
BEGIN;

DELETE FROM payment p
USING rental r JOIN branch b ON b.branch_id = r.branch_id
WHERE p.rental_id = r.rental_id AND b.country_code <> 'LT';

DELETE FROM rental r USING branch b
WHERE r.branch_id = b.branch_id AND b.country_code <> 'LT';

DELETE FROM drone_commercial d USING branch b
WHERE d.branch_id = b.branch_id AND b.country_code <> 'LT';

DELETE FROM customer c USING branch b
WHERE c.home_branch_id = b.branch_id AND b.country_code <> 'LT';

DELETE FROM branch WHERE country_code <> 'LT';

COMMIT;
