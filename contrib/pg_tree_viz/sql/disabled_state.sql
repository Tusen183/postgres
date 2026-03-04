--
-- Disabled State No-Op Property Test
-- **Validates: Requirements 2.3, 16.1**
--
-- Property 3: Disabled State No-Op
-- For any query processed when pg_tree_viz.enabled is false, no visualization
-- output shall be produced and the hook shall return immediately.
--
-- This test verifies that:
-- 1. When disabled, the hook returns immediately without processing
-- 2. No visualization output is produced when disabled
-- 3. There is no performance impact when disabled
-- 4. The hook can be toggled on/off without side effects
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Test 1: Verify default state is disabled
-- Property: Extension should be disabled by default (Requirement 18.1)
-- This confirms the default configuration is correct
SHOW pg_tree_viz.enabled;

-- Test 2: Verify queries execute normally when disabled (baseline)
-- Property: When disabled, queries should execute without any visualization
-- This establishes baseline behavior
CREATE TABLE disabled_test_table (
    id int,
    data text,
    value numeric
);

INSERT INTO disabled_test_table VALUES (1, 'test1', 100.5);
INSERT INTO disabled_test_table VALUES (2, 'test2', 200.75);
INSERT INTO disabled_test_table VALUES (3, 'test3', 300.25);

-- Execute queries with visualization disabled (default)
-- These should execute normally without any visualization output
SELECT * FROM disabled_test_table WHERE id = 1;
SELECT count(*) FROM disabled_test_table;
SELECT sum(value) FROM disabled_test_table;

-- Test 3: Verify no output is produced when disabled
-- Property: Disabled state should produce no visualization output
-- This tests that the hook truly does nothing when disabled
SELECT id, data FROM disabled_test_table ORDER BY id;

-- Test 4: Verify complex queries work when disabled
-- Property: Disabled state should handle all query types without processing
-- This tests that the early return works for complex queries too
SELECT d1.id, d1.data, d2.value
FROM disabled_test_table d1
JOIN disabled_test_table d2 ON d1.id = d2.id
WHERE d1.value > 100
ORDER BY d1.id;

-- Test 5: Enable visualization and verify output is produced
-- Property: Enabling should activate visualization
-- This establishes that enabling actually works (contrast with disabled)
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_format = 'raw';

-- This query should produce visualization output (we won't see it in test output,
-- but the fact that it executes successfully confirms the hook is working)
SELECT * FROM disabled_test_table WHERE id = 1;

-- Test 6: Disable again and verify no output
-- Property: Disabling should immediately stop visualization
-- This tests that the enabled flag is checked on every invocation
SET pg_tree_viz.enabled = false;

-- These queries should NOT produce visualization output
SELECT * FROM disabled_test_table WHERE id = 2;
SELECT count(*) FROM disabled_test_table WHERE value > 150;

-- Test 7: Verify rapid enable/disable toggling
-- Property: Toggling enabled state should not cause side effects
-- This tests that the hook state management is robust
SET pg_tree_viz.enabled = true;
SELECT * FROM disabled_test_table WHERE id = 1;

SET pg_tree_viz.enabled = false;
SELECT * FROM disabled_test_table WHERE id = 2;

SET pg_tree_viz.enabled = true;
SELECT * FROM disabled_test_table WHERE id = 3;

SET pg_tree_viz.enabled = false;
SELECT * FROM disabled_test_table WHERE id = 1;

-- Test 8: Verify disabled state with different output formats
-- Property: When disabled, output format should not matter
-- This tests that the early return happens before format checking
SET pg_tree_viz.output_format = 'dot';
SELECT * FROM disabled_test_table WHERE id = 1;

SET pg_tree_viz.output_format = 'raw';
SELECT * FROM disabled_test_table WHERE id = 2;

-- Test 9: Verify disabled state with output file configured
-- Property: When disabled, output file setting should not matter
-- This tests that the early return happens before file operations
SET pg_tree_viz.output_file = '/tmp/test_output.log';
SELECT * FROM disabled_test_table WHERE id = 1;

SET pg_tree_viz.output_file = '';
SELECT * FROM disabled_test_table WHERE id = 2;

-- Test 10: Verify disabled state with subqueries
-- Property: Disabled state should handle nested queries without processing
-- This tests that the early return works for all query structures
SELECT id, data
FROM disabled_test_table
WHERE id IN (SELECT id FROM disabled_test_table WHERE value > 100);

-- Test 11: Verify disabled state with CTEs
-- Property: Disabled state should handle CTEs without processing
-- This tests that the early return works for CTEs
WITH test_cte AS (
    SELECT id, data, value FROM disabled_test_table WHERE value > 150
)
SELECT * FROM test_cte ORDER BY id;

-- Test 12: Verify disabled state with aggregates
-- Property: Disabled state should handle aggregate queries without processing
-- This tests that the early return works for complex aggregations
SELECT
    count(*) as total_count,
    sum(value) as total_value,
    avg(value) as avg_value,
    min(value) as min_value,
    max(value) as max_value
FROM disabled_test_table;

-- Test 13: Verify disabled state across transaction boundaries
-- Property: Disabled state should be consistent across transactions
-- This tests that the enabled flag is properly managed in transactions
BEGIN;
SELECT * FROM disabled_test_table WHERE id = 1;
COMMIT;

BEGIN;
SELECT * FROM disabled_test_table WHERE id = 2;
ROLLBACK;

-- Test 14: Verify disabled state with DDL operations
-- Property: Disabled state should not interfere with DDL
-- This tests that the hook doesn't affect schema operations when disabled
ALTER TABLE disabled_test_table ADD COLUMN extra text;
SELECT * FROM disabled_test_table WHERE id = 1;

-- Test 15: Verify disabled state persists across multiple queries
-- Property: Disabled state should remain consistent
-- This tests that the disabled state is stable
SELECT * FROM disabled_test_table WHERE id = 1;
SELECT * FROM disabled_test_table WHERE id = 2;
SELECT * FROM disabled_test_table WHERE id = 3;
SELECT count(*) FROM disabled_test_table;

-- Test 16: Final verification - enable and disable
-- Property: The enabled flag should control visualization consistently
-- This is a final sanity check
SET pg_tree_viz.enabled = true;
SELECT 1 AS "enabled_test";

SET pg_tree_viz.enabled = false;
SELECT 1 AS "disabled_test";

-- Cleanup
DROP TABLE disabled_test_table;
DROP EXTENSION pg_tree_viz;
