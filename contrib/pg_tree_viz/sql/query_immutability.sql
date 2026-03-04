--
-- Query Structure Immutability Property Test
-- **Validates: Requirement 2.4**
--
-- Property 2: Query Structure Immutability
-- For any Query structure processed by the hook, the Query structure must
-- remain unchanged after hook processing completes.
--
-- This test verifies that pg_tree_viz does not modify the Query structure by:
-- 1. Comparing query results with visualization disabled vs enabled
-- 2. Verifying query execution behavior is identical in both states
-- 3. Testing that multiple executions produce consistent results
-- 4. Ensuring query semantics are preserved across various query types
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Create test tables with various data types
CREATE TABLE immut_test_users (
    id int PRIMARY KEY,
    name text,
    age int,
    salary numeric(10,2),
    active boolean,
    created_at timestamp
);

CREATE TABLE immut_test_orders (
    order_id int PRIMARY KEY,
    user_id int,
    amount numeric(10,2),
    status text,
    order_date date
);

-- Insert test data
INSERT INTO immut_test_users VALUES
    (1, 'Alice', 30, 50000.00, true, '2024-01-01 10:00:00'),
    (2, 'Bob', 25, 45000.00, true, '2024-01-02 11:00:00'),
    (3, 'Charlie', 35, 60000.00, false, '2024-01-03 12:00:00'),
    (4, 'Diana', 28, 55000.00, true, '2024-01-04 13:00:00');

INSERT INTO immut_test_orders VALUES
    (101, 1, 100.50, 'completed', '2024-02-01'),
    (102, 1, 200.75, 'pending', '2024-02-02'),
    (103, 2, 150.00, 'completed', '2024-02-03'),
    (104, 3, 300.25, 'cancelled', '2024-02-04'),
    (105, 4, 175.50, 'completed', '2024-02-05');

-- Test 1: Simple SELECT - baseline without visualization
-- Property: Query results should be identical with visualization disabled
SELECT id, name, age FROM immut_test_users WHERE id = 1;

-- Test 2: Enable visualization and execute same query
-- Property: Query results must be identical to Test 1
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_format = 'raw';
SELECT id, name, age FROM immut_test_users WHERE id = 1;

-- Test 3: Disable and re-enable to verify consistency
-- Property: Results should remain consistent across enable/disable cycles
SET pg_tree_viz.enabled = false;
SELECT id, name, age FROM immut_test_users WHERE id = 1;

SET pg_tree_viz.enabled = true;
SELECT id, name, age FROM immut_test_users WHERE id = 1;

-- Test 4: Aggregate functions
-- Property: Aggregation results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT count(*), avg(age), sum(salary) FROM immut_test_users WHERE active = true;

SET pg_tree_viz.enabled = true;
SELECT count(*), avg(age), sum(salary) FROM immut_test_users WHERE active = true;

-- Test 5: JOIN operations
-- Property: JOIN results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT u.id, u.name, o.order_id, o.amount
FROM immut_test_users u
JOIN immut_test_orders o ON u.id = o.user_id
WHERE o.status = 'completed'
ORDER BY u.id, o.order_id;

SET pg_tree_viz.enabled = true;
SELECT u.id, u.name, o.order_id, o.amount
FROM immut_test_users u
JOIN immut_test_orders o ON u.id = o.user_id
WHERE o.status = 'completed'
ORDER BY u.id, o.order_id;

-- Test 6: Subqueries
-- Property: Subquery results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT id, name, salary
FROM immut_test_users
WHERE id IN (SELECT user_id FROM immut_test_orders WHERE amount > 150)
ORDER BY id;

SET pg_tree_viz.enabled = true;
SELECT id, name, salary
FROM immut_test_users
WHERE id IN (SELECT user_id FROM immut_test_orders WHERE amount > 150)
ORDER BY id;

-- Test 7: CTEs (Common Table Expressions)
-- Property: CTE results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
WITH high_value_orders AS (
    SELECT user_id, sum(amount) as total_amount
    FROM immut_test_orders
    WHERE status = 'completed'
    GROUP BY user_id
    HAVING sum(amount) > 100
)
SELECT u.id, u.name, h.total_amount
FROM immut_test_users u
JOIN high_value_orders h ON u.id = h.user_id
ORDER BY u.id;

SET pg_tree_viz.enabled = true;
WITH high_value_orders AS (
    SELECT user_id, sum(amount) as total_amount
    FROM immut_test_orders
    WHERE status = 'completed'
    GROUP BY user_id
    HAVING sum(amount) > 100
)
SELECT u.id, u.name, h.total_amount
FROM immut_test_users u
JOIN high_value_orders h ON u.id = h.user_id
ORDER BY u.id;

-- Test 8: Window functions
-- Property: Window function results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT id, name, salary,
       rank() OVER (ORDER BY salary DESC) as salary_rank,
       row_number() OVER (ORDER BY age) as age_order
FROM immut_test_users
ORDER BY id;

SET pg_tree_viz.enabled = true;
SELECT id, name, salary,
       rank() OVER (ORDER BY salary DESC) as salary_rank,
       row_number() OVER (ORDER BY age) as age_order
FROM immut_test_users
ORDER BY id;

-- Test 9: DISTINCT and GROUP BY
-- Property: DISTINCT and GROUP BY results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT status, count(*) as order_count, sum(amount) as total_amount
FROM immut_test_orders
GROUP BY status
ORDER BY status;

SET pg_tree_viz.enabled = true;
SELECT status, count(*) as order_count, sum(amount) as total_amount
FROM immut_test_orders
GROUP BY status
ORDER BY status;

-- Test 10: UNION operations
-- Property: UNION results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT id, name FROM immut_test_users WHERE age < 30
UNION
SELECT id, name FROM immut_test_users WHERE salary > 55000
ORDER BY id;

SET pg_tree_viz.enabled = true;
SELECT id, name FROM immut_test_users WHERE age < 30
UNION
SELECT id, name FROM immut_test_users WHERE salary > 55000
ORDER BY id;

-- Test 11: Complex WHERE clauses
-- Property: Complex predicates must evaluate identically with/without visualization
SET pg_tree_viz.enabled = false;
SELECT id, name, age, salary
FROM immut_test_users
WHERE (age > 25 AND salary < 55000) OR (age < 30 AND active = true)
ORDER BY id;

SET pg_tree_viz.enabled = true;
SELECT id, name, age, salary
FROM immut_test_users
WHERE (age > 25 AND salary < 55000) OR (age < 30 AND active = true)
ORDER BY id;

-- Test 12: LIMIT and OFFSET
-- Property: LIMIT/OFFSET results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT id, name FROM immut_test_users ORDER BY id LIMIT 2 OFFSET 1;

SET pg_tree_viz.enabled = true;
SELECT id, name FROM immut_test_users ORDER BY id LIMIT 2 OFFSET 1;

-- Test 13: NULL handling
-- Property: NULL handling must be identical with/without visualization
UPDATE immut_test_users SET age = NULL WHERE id = 3;

SET pg_tree_viz.enabled = false;
SELECT id, name, age FROM immut_test_users WHERE age IS NULL OR age > 30 ORDER BY id;

SET pg_tree_viz.enabled = true;
SELECT id, name, age FROM immut_test_users WHERE age IS NULL OR age > 30 ORDER BY id;

-- Test 14: CASE expressions
-- Property: CASE expression results must be identical with/without visualization
SET pg_tree_viz.enabled = false;
SELECT id, name, age,
       CASE
           WHEN age < 30 THEN 'Young'
           WHEN age >= 30 AND age < 35 THEN 'Middle'
           ELSE 'Senior'
       END as age_category
FROM immut_test_users
WHERE age IS NOT NULL
ORDER BY id;

SET pg_tree_viz.enabled = true;
SELECT id, name, age,
       CASE
           WHEN age < 30 THEN 'Young'
           WHEN age >= 30 AND age < 35 THEN 'Middle'
           ELSE 'Senior'
       END as age_category
FROM immut_test_users
WHERE age IS NOT NULL
ORDER BY id;

-- Test 15: Multiple executions with visualization enabled
-- Property: Same query executed multiple times should produce identical results
SET pg_tree_viz.enabled = true;
SELECT count(*) FROM immut_test_users WHERE active = true;
SELECT count(*) FROM immut_test_users WHERE active = true;
SELECT count(*) FROM immut_test_users WHERE active = true;

-- Test 16: Test with DOT format
-- Property: Query results must be identical regardless of output format
SET pg_tree_viz.output_format = 'dot';
SELECT id, name FROM immut_test_users WHERE id <= 2 ORDER BY id;

SET pg_tree_viz.output_format = 'raw';
SELECT id, name FROM immut_test_users WHERE id <= 2 ORDER BY id;

-- Test 17: Verify data integrity after many visualizations
-- Property: Data should not be corrupted by visualization operations
SET pg_tree_viz.enabled = true;
SELECT * FROM immut_test_users ORDER BY id;
SELECT * FROM immut_test_orders ORDER BY order_id;

-- Verify counts match original inserts
SELECT 'users' as table_name, count(*) as row_count FROM immut_test_users
UNION ALL
SELECT 'orders' as table_name, count(*) as row_count FROM immut_test_orders
ORDER BY table_name;

-- Test 18: Transaction boundaries
-- Property: Query immutability should hold across transaction boundaries
BEGIN;
SET pg_tree_viz.enabled = true;
SELECT id, name FROM immut_test_users WHERE id = 1;
COMMIT;

BEGIN;
SELECT id, name FROM immut_test_users WHERE id = 1;
ROLLBACK;

-- Test 19: Verify query results after disabling
-- Property: Disabling visualization should not affect subsequent query results
SET pg_tree_viz.enabled = false;
SELECT id, name, age FROM immut_test_users WHERE id = 1;

-- Final verification: Compare final state with initial expectations
SELECT count(*) as total_users FROM immut_test_users;
SELECT count(*) as total_orders FROM immut_test_orders;

-- Cleanup
DROP TABLE immut_test_orders;
DROP TABLE immut_test_users;
DROP EXTENSION pg_tree_viz;
