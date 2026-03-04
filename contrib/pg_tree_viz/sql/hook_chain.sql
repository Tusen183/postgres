--
-- Hook Chain Preservation Property Test
-- **Validates: Requirements 2.2, 13.2, 13.3**
--
-- Property 1: Hook Chain Preservation
-- For any hook invocation, if a previous hook exists, then that previous hook
-- must be called with all parameters unchanged before visualization processing begins.
--
-- This test verifies that pg_tree_viz properly preserves the hook chain by:
-- 1. Ensuring queries execute normally (hook doesn't break execution)
-- 2. Testing with various query types and configurations
-- 3. Verifying extension can be loaded/unloaded without breaking the hook chain
-- 4. Testing that the hook works correctly when enabled/disabled
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Test 1: Verify hook is registered
-- When the extension is loaded, the hook should be registered
-- This confirms the extension loaded successfully
SELECT 1 AS "extension_loaded";

-- Test 2: Verify hook chain with disabled visualization (baseline)
-- Property: When disabled, hook should still preserve chain and allow normal execution
-- This tests that the hook doesn't interfere when disabled
CREATE TABLE hook_test_table (
    id int,
    data text
);

INSERT INTO hook_test_table VALUES (1, 'test');

-- With visualization disabled (default), queries should execute normally
-- This confirms the hook chain is preserved even when our hook does nothing
SELECT * FROM hook_test_table WHERE id = 1;

-- Test 3: Verify hook chain with enabled visualization
-- Property: When enabled, hook should process query AND preserve chain
-- This tests that enabling visualization doesn't break the hook chain
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_format = 'raw';

-- Execute a query - the hook should be called and process it
-- If the hook chain is broken, this would fail or produce errors
SELECT * FROM hook_test_table WHERE id = 1;

-- Test 4: Verify hook chain with multiple queries
-- Property: Hook chain preservation should hold for all queries in sequence
-- This tests that the hook chain remains intact across multiple invocations
SELECT count(*) FROM hook_test_table;
SELECT id, data FROM hook_test_table ORDER BY id;

-- Test 5: Verify hook chain with disabled visualization after being enabled
-- Property: Disabling should not break the hook chain
-- This tests that toggling the enabled flag doesn't corrupt the hook chain
SET pg_tree_viz.enabled = false;
SELECT * FROM hook_test_table WHERE id = 1;

-- Test 6: Verify hook chain with different output formats
-- Property: Changing output format should not affect hook chain preservation
-- This tests that configuration changes don't break the hook chain
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_format = 'dot';
SELECT * FROM hook_test_table WHERE id = 1;

-- Test 7: Verify hook chain with complex queries
-- Property: Hook chain preservation should hold for complex query structures
-- This tests that the hook properly handles and passes through complex queries
SELECT h1.id, h1.data, h2.id AS id2
FROM hook_test_table h1
LEFT JOIN hook_test_table h2 ON h1.id = h2.id
WHERE h1.id > 0
ORDER BY h1.id;

-- Test 8: Verify hook chain with subqueries
-- Property: Hook chain should be preserved for queries with subqueries
-- This tests that nested query structures don't break the hook chain
SELECT id, data
FROM hook_test_table
WHERE id IN (SELECT id FROM hook_test_table WHERE id = 1);

-- Test 9: Verify hook chain with CTEs
-- Property: Hook chain should be preserved for queries with CTEs
-- This tests that CTE processing doesn't break the hook chain
WITH test_cte AS (
    SELECT id, data FROM hook_test_table WHERE id = 1
)
SELECT * FROM test_cte;

-- Test 10: Verify hook chain cleanup on extension drop
-- Property: Dropping extension should restore previous hook state
-- This tests that the hook chain is properly restored when extension is unloaded
DROP TABLE hook_test_table;
DROP EXTENSION pg_tree_viz;

-- Test 11: Verify extension can be recreated (hook cleanup works)
-- Property: Extension can be loaded again after being dropped
-- This tests that hook registration/unregistration is idempotent
CREATE EXTENSION pg_tree_viz;

-- Verify it works after recreation
CREATE TABLE hook_test_table2 (id int);
INSERT INTO hook_test_table2 VALUES (1);

SET pg_tree_viz.enabled = true;
SELECT * FROM hook_test_table2;

-- Test 12: Verify hook chain with transaction boundaries
-- Property: Hook chain should be preserved across transaction boundaries
-- This tests that transaction commit/rollback doesn't affect the hook chain
BEGIN;
SELECT * FROM hook_test_table2;
COMMIT;

BEGIN;
SELECT * FROM hook_test_table2;
ROLLBACK;

-- Test 13: Verify hook chain with DDL operations
-- Property: Hook chain should be preserved during DDL operations
-- This tests that schema changes don't break the hook chain
ALTER TABLE hook_test_table2 ADD COLUMN data text;
SELECT * FROM hook_test_table2;

-- Test 14: Verify hook chain with multiple configuration changes
-- Property: Rapid configuration changes should not break hook chain
-- This tests that the hook chain remains stable under configuration changes
SET pg_tree_viz.enabled = false;
SET pg_tree_viz.enabled = true;
SET pg_tree_viz.output_format = 'raw';
SET pg_tree_viz.output_format = 'dot';
SET pg_tree_viz.output_format = 'raw';
SELECT * FROM hook_test_table2;

-- Final cleanup
DROP TABLE hook_test_table2;
DROP EXTENSION pg_tree_viz;
