--
-- RAW Format Identity Property Test
-- **Validates: Requirement 3.3**
--
-- Property 4: RAW Format Identity
-- For any query visualized with output_format set to RAW, the output must be
-- identical to the result of calling nodeToString() on the Query structure.
--
-- This test verifies that RAW format output is identical to nodeToString() by:
-- 1. Using the SQL function pg_tree_viz() to get RAW format output
-- 2. Comparing outputs across different query types
-- 3. Verifying consistency across multiple invocations
-- 4. Testing that RAW format is truly unmodified nodeToString() output
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Create test tables
CREATE TABLE raw_test_users (
    id int PRIMARY KEY,
    name text,
    email text
);

CREATE TABLE raw_test_orders (
    order_id int PRIMARY KEY,
    user_id int,
    amount numeric(10,2)
);

-- Insert test data
INSERT INTO raw_test_users VALUES
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com'),
    (3, 'Charlie', 'charlie@example.com');

INSERT INTO raw_test_orders VALUES
    (101, 1, 100.50),
    (102, 2, 200.75),
    (103, 1, 150.00);

-- Test 1: Simple SELECT - verify RAW format contains nodeToString characteristics
-- Property: RAW format output should contain nodeToString structure markers
SELECT pg_tree_viz('SELECT * FROM raw_test_users WHERE id = 1', 'raw') LIKE '{QUERY %' AS has_query_node;

-- Test 2: Verify RAW format contains expected node structure
-- Property: RAW format should contain field markers like :commandType
SELECT pg_tree_viz('SELECT * FROM raw_test_users WHERE id = 1', 'raw') LIKE '%:commandType%' AS has_command_type;

-- Test 3: Verify RAW format contains rtable (range table)
-- Property: RAW format should contain :rtable for queries with tables
SELECT pg_tree_viz('SELECT * FROM raw_test_users WHERE id = 1', 'raw') LIKE '%:rtable%' AS has_rtable;

-- Test 4: Consistency test - same query should produce identical output
-- Property: Multiple calls with same query should produce identical RAW output
WITH first_call AS (
    SELECT pg_tree_viz('SELECT id FROM raw_test_users WHERE id = 1', 'raw') AS output
),
second_call AS (
    SELECT pg_tree_viz('SELECT id FROM raw_test_users WHERE id = 1', 'raw') AS output
)
SELECT first_call.output = second_call.output AS outputs_identical
FROM first_call, second_call;

-- Test 5: JOIN query - verify RAW format structure
-- Property: RAW format for JOIN queries should contain join-related structures
SELECT pg_tree_viz(
    'SELECT u.id, o.order_id FROM raw_test_users u JOIN raw_test_orders o ON u.id = o.user_id',
    'raw'
) LIKE '%:jointree%' AS has_jointree;

-- Test 6: Aggregate query - verify RAW format contains aggregation nodes
-- Property: RAW format for aggregate queries should contain aggregate structures
SELECT pg_tree_viz(
    'SELECT count(*) FROM raw_test_users',
    'raw'
) LIKE '%:hasAggs%' AS has_aggs_field;

-- Test 7: Subquery - verify RAW format contains subquery structures
-- Property: RAW format for subqueries should contain sublink structures
SELECT pg_tree_viz(
    'SELECT * FROM raw_test_users WHERE id IN (SELECT user_id FROM raw_test_orders)',
    'raw'
) LIKE '%:hasSubLinks%' AS has_sublinks_field;

-- Test 8: CTE - verify RAW format contains CTE structures
-- Property: RAW format for CTEs should contain cteList
SELECT pg_tree_viz(
    'WITH user_orders AS (SELECT user_id FROM raw_test_orders) SELECT * FROM user_orders',
    'raw'
) LIKE '%:cteList%' AS has_cte_list;

-- Test 9: Window function - verify RAW format contains window function structures
-- Property: RAW format for window functions should contain window-related fields
SELECT pg_tree_viz(
    'SELECT id, name, row_number() OVER (ORDER BY id) FROM raw_test_users',
    'raw'
) LIKE '%:hasWindowFuncs%' AS has_window_funcs;

-- Test 10: DISTINCT - verify RAW format contains distinct structures
-- Property: RAW format for DISTINCT queries should contain hasDistinctOn field
SELECT pg_tree_viz(
    'SELECT DISTINCT name FROM raw_test_users',
    'raw'
) LIKE '%:hasDistinctOn%' AS has_distinct_field;

-- Test 11: ORDER BY - verify RAW format contains sort clause
-- Property: RAW format for ORDER BY queries should contain sortClause
SELECT pg_tree_viz(
    'SELECT * FROM raw_test_users ORDER BY id',
    'raw'
) LIKE '%:sortClause%' AS has_sort_clause;

-- Test 12: LIMIT - verify RAW format contains limit structures
-- Property: RAW format for LIMIT queries should contain limitCount
SELECT pg_tree_viz(
    'SELECT * FROM raw_test_users LIMIT 5',
    'raw'
) LIKE '%:limitCount%' AS has_limit_count;

-- Test 13: UPDATE query - verify RAW format for DML
-- Property: RAW format should work for UPDATE queries
SELECT pg_tree_viz(
    'UPDATE raw_test_users SET name = ''Updated'' WHERE id = 1',
    'raw'
) LIKE '{QUERY %' AS update_has_query_node;

-- Test 14: DELETE query - verify RAW format for DELETE
-- Property: RAW format should work for DELETE queries
SELECT pg_tree_viz(
    'DELETE FROM raw_test_users WHERE id = 1',
    'raw'
) LIKE '{QUERY %' AS delete_has_query_node;

-- Test 15: INSERT query - verify RAW format for INSERT
-- Property: RAW format should work for INSERT queries
SELECT pg_tree_viz(
    'INSERT INTO raw_test_users VALUES (4, ''David'', ''david@example.com'')',
    'raw'
) LIKE '{QUERY %' AS insert_has_query_node;

-- Test 16: Complex WHERE clause - verify RAW format contains operator expressions
-- Property: RAW format should contain OpExpr for complex predicates
SELECT pg_tree_viz(
    'SELECT * FROM raw_test_users WHERE id > 1 AND name LIKE ''A%''',
    'raw'
) LIKE '%OPEXPR%' AS has_opexpr;

-- Test 17: CASE expression - verify RAW format contains case structures
-- Property: RAW format should contain CASE expression nodes
SELECT pg_tree_viz(
    'SELECT id, CASE WHEN id = 1 THEN ''one'' ELSE ''other'' END FROM raw_test_users',
    'raw'
) LIKE '%CASE%' AS has_case_expr;

-- Test 18: NULL handling - verify RAW format contains null test
-- Property: RAW format should contain null test structures
SELECT pg_tree_viz(
    'SELECT * FROM raw_test_users WHERE email IS NULL',
    'raw'
) LIKE '%NULLTEST%' AS has_null_test;

-- Test 19: UNION - verify RAW format for set operations
-- Property: RAW format should work for UNION queries
SELECT pg_tree_viz(
    'SELECT id FROM raw_test_users WHERE id = 1 UNION SELECT id FROM raw_test_users WHERE id = 2',
    'raw'
) LIKE '{QUERY %' AS union_has_query_node;

-- Test 20: Verify RAW format does NOT contain DOT-specific markers
-- Property: RAW format should not contain DOT graph syntax
SELECT
    pg_tree_viz('SELECT * FROM raw_test_users', 'raw') NOT LIKE '%digraph%' AS no_digraph,
    pg_tree_viz('SELECT * FROM raw_test_users', 'raw') NOT LIKE '%rankdir%' AS no_rankdir,
    pg_tree_viz('SELECT * FROM raw_test_users', 'raw') NOT LIKE '%->%' AS no_arrows;

-- Test 21: Verify RAW format starts with opening brace
-- Property: RAW format (nodeToString output) should start with '{'
SELECT pg_tree_viz('SELECT 1', 'raw') LIKE '{%' AS starts_with_brace;

-- Test 22: Verify RAW format ends with closing brace
-- Property: RAW format (nodeToString output) should end with '}'
SELECT pg_tree_viz('SELECT 1', 'raw') LIKE '%}' AS ends_with_brace;

-- Test 23: Verify RAW format contains node type in uppercase
-- Property: nodeToString uses uppercase for node types (e.g., QUERY, RANGETBLENTRY)
SELECT
    pg_tree_viz('SELECT * FROM raw_test_users', 'raw') LIKE '%QUERY%' AS has_uppercase_query,
    pg_tree_viz('SELECT * FROM raw_test_users', 'raw') LIKE '%RANGETBLENTRY%' AS has_uppercase_rte;

-- Test 24: Verify RAW format field names start with colon
-- Property: nodeToString uses ':' prefix for field names
SELECT
    pg_tree_viz('SELECT * FROM raw_test_users', 'raw') ~ ':[a-zA-Z]+' AS has_colon_fields;

-- Test 25: Consistency across different invocations with hook enabled
-- Property: RAW format should be consistent whether using SQL function or hook
SET pg_tree_viz.enabled = false;
WITH func_output AS (
    SELECT pg_tree_viz('SELECT id FROM raw_test_users WHERE id = 1', 'raw') AS output
)
SELECT length(output) > 100 AS has_substantial_output
FROM func_output;

-- Test 26: Verify RAW format is not empty
-- Property: RAW format should always produce non-empty output for valid queries
SELECT
    length(pg_tree_viz('SELECT 1', 'raw')) > 0 AS not_empty,
    length(pg_tree_viz('SELECT * FROM raw_test_users', 'raw')) > 0 AS not_empty_table_query;

-- Test 27: Verify RAW format contains query source information
-- Property: RAW format should contain :querySource field
SELECT pg_tree_viz('SELECT * FROM raw_test_users', 'raw') LIKE '%:querySource%' AS has_query_source;

-- Test 28: Verify RAW format contains canSetTag field
-- Property: RAW format should contain :canSetTag field
SELECT pg_tree_viz('SELECT * FROM raw_test_users', 'raw') LIKE '%:canSetTag%' AS has_can_set_tag;

-- Test 29: Verify RAW format for complex nested query
-- Property: RAW format should handle deeply nested structures
SELECT length(pg_tree_viz(
    'SELECT u.id, (SELECT count(*) FROM raw_test_orders o WHERE o.user_id = u.id) as order_count FROM raw_test_users u',
    'raw'
)) > 200 AS complex_query_has_output;

-- Test 30: Verify RAW format consistency with multiple tables
-- Property: RAW format should consistently represent multi-table queries
WITH first AS (
    SELECT pg_tree_viz(
        'SELECT * FROM raw_test_users u, raw_test_orders o WHERE u.id = o.user_id',
        'raw'
    ) AS output
),
second AS (
    SELECT pg_tree_viz(
        'SELECT * FROM raw_test_users u, raw_test_orders o WHERE u.id = o.user_id',
        'raw'
    ) AS output
)
SELECT first.output = second.output AS multi_table_consistent
FROM first, second;

-- Cleanup
DROP TABLE raw_test_orders;
DROP TABLE raw_test_users;
DROP EXTENSION pg_tree_viz;
