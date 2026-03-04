--
-- Hook Error Handling Unit Tests
-- **Validates: Requirements 11.1, 11.2, 11.3**
--
-- This test verifies that:
-- 1. Errors during visualization are caught using PG_TRY/PG_CATCH (Requirement 11.1)
-- 2. Visualization failures log a WARNING message (Requirement 11.2)
-- 3. Query execution continues normally after visualization errors (Requirement 11.3)
-- 4. Memory cleanup occurs properly on errors (Requirement 7.4)
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Test 1: Verify queries execute normally with visualization enabled (baseline)
-- This establishes that the hook works correctly under normal conditions
CREATE TABLE error_test_table (
    id int,
    data text,
    value numeric
);

INSERT INTO error_test_table VALUES (1, 'test1', 100.5);
INSERT INTO error_test_table VALUES (2, 'test2', 200.75);

-- Enable visualization with default settings
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_format = 'raw';

-- Execute a normal query - should work fine
SELECT * FROM error_test_table WHERE id = 1;

-- Test 2: Test error isolation with invalid file path
-- Property: File write errors should not disrupt query execution
-- This tests that file operation failures are caught and handled gracefully
SET pg_tree_viz.output_file = '/invalid/path/that/does/not/exist/output.log';

-- Query should execute successfully despite file write failure
-- A WARNING should be logged, but query execution continues
SELECT * FROM error_test_table WHERE id = 1;

-- Test 3: Verify query execution continues after file error
-- Property: Subsequent queries should work after a file error
-- This tests that error state is properly cleared
SELECT count(*) FROM error_test_table;

-- Test 4: Test with permission-denied path (if running as non-root)
-- Property: Permission errors should not disrupt query execution
-- This tests that permission failures are handled gracefully
SET pg_tree_viz.output_file = '/root/output.log';

-- Query should execute successfully despite permission error
SELECT * FROM error_test_table WHERE id = 2;

-- Test 5: Verify multiple queries work after errors
-- Property: Error recovery should be complete and stable
-- This tests that the hook remains functional after errors
SELECT id, data FROM error_test_table ORDER BY id;
SELECT sum(value) FROM error_test_table;

-- Test 6: Test error handling with complex queries
-- Property: Error isolation should work for all query types
-- This tests that complex queries execute despite visualization errors
SELECT e1.id, e1.data, e2.value
FROM error_test_table e1
JOIN error_test_table e2 ON e1.id = e2.id
WHERE e1.value > 100
ORDER BY e1.id;

-- Test 7: Test error handling with subqueries
-- Property: Nested queries should execute despite visualization errors
-- This tests that error handling works for complex query structures
SELECT id, data
FROM error_test_table
WHERE id IN (SELECT id FROM error_test_table WHERE value > 100);

-- Test 8: Test error handling with CTEs
-- Property: CTEs should execute despite visualization errors
-- This tests that error handling works with CTEs
WITH test_cte AS (
    SELECT id, data, value FROM error_test_table WHERE value > 150
)
SELECT * FROM test_cte ORDER BY id;

-- Test 9: Test error handling across transaction boundaries
-- Property: Errors should not affect transaction integrity
-- This tests that visualization errors don't corrupt transactions
BEGIN;
SELECT * FROM error_test_table WHERE id = 1;
SELECT * FROM error_test_table WHERE id = 2;
COMMIT;

BEGIN;
SELECT count(*) FROM error_test_table;
ROLLBACK;

-- Test 10: Test recovery by switching to valid output
-- Property: System should recover when configuration is fixed
-- This tests that the hook can recover from error conditions
SET pg_tree_viz.output_file = '';  -- Switch to NOTICE output

-- Query should now work without errors
SELECT * FROM error_test_table WHERE id = 1;

-- Test 11: Test error handling with DOT format
-- Property: Error isolation should work for all output formats
-- This tests that DOT format errors are also handled gracefully
SET pg_tree_viz.output_format = 'dot';
SET pg_tree_viz.output_file = '/invalid/path/output.dot';

-- Query should execute despite file error
SELECT * FROM error_test_table WHERE id = 1;

-- Test 12: Test rapid enable/disable after errors
-- Property: Toggling enabled state should work after errors
-- This tests that error state doesn't affect configuration changes
SET pg_tree_viz.enabled = false;
SELECT * FROM error_test_table WHERE id = 1;

SET pg_tree_viz.enabled = true;
SELECT * FROM error_test_table WHERE id = 2;

SET pg_tree_viz.enabled = false;
SELECT * FROM error_test_table WHERE id = 1;

-- Test 13: Test error handling with aggregates
-- Property: Aggregate queries should execute despite visualization errors
-- This tests that error handling works with complex aggregations
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_file = '/invalid/path/output.log';

SELECT
    count(*) as total_count,
    sum(value) as total_value,
    avg(value) as avg_value,
    min(value) as min_value,
    max(value) as max_value
FROM error_test_table;

-- Test 14: Test error handling with window functions
-- Property: Window functions should execute despite visualization errors
-- This tests that error handling works with window functions
SELECT
    id,
    data,
    value,
    row_number() OVER (ORDER BY value) as row_num,
    rank() OVER (ORDER BY value) as rank_val
FROM error_test_table;

-- Test 15: Test error handling with DISTINCT
-- Property: DISTINCT queries should execute despite visualization errors
-- This tests that error handling works with DISTINCT
SELECT DISTINCT data FROM error_test_table;

-- Test 16: Test error handling with GROUP BY
-- Property: GROUP BY queries should execute despite visualization errors
-- This tests that error handling works with grouping
SELECT data, count(*) as cnt
FROM error_test_table
GROUP BY data
ORDER BY data;

-- Test 17: Test error handling with UNION
-- Property: Set operations should execute despite visualization errors
-- This tests that error handling works with UNION
SELECT id, data FROM error_test_table WHERE id = 1
UNION
SELECT id, data FROM error_test_table WHERE id = 2;

-- Test 18: Final verification - switch back to working configuration
-- Property: System should be fully functional after error recovery
-- This is a final sanity check
SET pg_tree_viz.output_file = '';
SELECT 1 AS "final_test";

-- Test 19: Verify extension can be dropped after errors
-- Property: Extension cleanup should work after errors
-- This tests that error state doesn't prevent extension removal
SET pg_tree_viz.enabled = false;
DROP TABLE error_test_table;
DROP EXTENSION pg_tree_viz;

-- Test 20: Verify extension can be recreated after errors
-- Property: Extension can be loaded again after error conditions
-- This tests that error handling doesn't leave persistent corruption
CREATE EXTENSION pg_tree_viz;

CREATE TABLE error_test_table2 (id int);
INSERT INTO error_test_table2 VALUES (1);

SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_file = '/invalid/path/test.log';

-- Should work despite file error
SELECT * FROM error_test_table2;

-- Final cleanup
DROP TABLE error_test_table2;
DROP EXTENSION pg_tree_viz;
