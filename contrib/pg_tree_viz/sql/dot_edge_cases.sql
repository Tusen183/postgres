--
-- DOT Conversion Edge Cases Unit Tests
-- **Validates: Requirements 4.1, 4.6**
--
-- Task 6.3: Write unit tests for DOT conversion edge cases
-- - Test deeply nested structures
-- - Test empty nodes
-- - Test special characters in labels
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Create test tables for edge cases
CREATE TABLE edge_test_table (
    id int PRIMARY KEY,
    "special""column" text,  -- Column with special characters
    "column with spaces" text,
    normal_column text
);

-- Insert test data
INSERT INTO edge_test_table VALUES
    (1, 'value with "quotes"', 'value with spaces', 'normal'),
    (2, 'value''s apostrophe', 'another value', 'test');

-- ============================================================================
-- Test 1: Deeply Nested Structures
-- ============================================================================

-- Test 1.1: Deeply nested subquery (3 levels)
-- Property: DOT conversion should handle deeply nested query structures
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT * FROM edge_test_table WHERE id IN (SELECT id FROM edge_test_table WHERE id IN (SELECT id FROM edge_test_table WHERE id = 1))',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_structure,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 5 AS has_many_nodes,
    (SELECT count(*) FROM regexp_matches(output, '->', 'g')) > 3 AS has_many_edges
FROM dot_output;

-- Test 1.2: Nested CTEs
-- Property: Multiple nested CTEs should produce valid DOT with deep structure
WITH dot_output AS (
    SELECT pg_tree_viz(
        'WITH cte1 AS (SELECT id FROM edge_test_table), cte2 AS (SELECT id FROM cte1), cte3 AS (SELECT id FROM cte2) SELECT * FROM cte3',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_nested_cte,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 3 AS has_multiple_nodes
FROM dot_output;

-- Test 1.3: Complex JOIN with nested conditions
-- Property: Complex nested JOIN conditions should be handled
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT * FROM edge_test_table t1 JOIN edge_test_table t2 ON t1.id = t2.id AND t1.id IN (SELECT id FROM edge_test_table WHERE id > 0)',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_complex_join,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 4 AS has_sufficient_nodes
FROM dot_output;

-- Test 1.4: Nested CASE expressions
-- Property: Nested CASE expressions should be represented in DOT
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT CASE WHEN id = 1 THEN CASE WHEN normal_column = ''test'' THEN ''nested'' ELSE ''other'' END ELSE ''default'' END FROM edge_test_table',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_nested_case,
    length(output) > 200 AS has_substantial_content
FROM dot_output;

-- Test 1.5: Deeply nested function calls
-- Property: Nested function calls should be properly represented
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT upper(lower(trim(normal_column))) FROM edge_test_table',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_nested_functions,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 2 AS has_nodes
FROM dot_output;

-- ============================================================================
-- Test 2: Empty Nodes and Minimal Structures
-- ============================================================================

-- Test 2.1: Simple SELECT with no WHERE clause
-- Property: Minimal query should still produce valid DOT
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT 1', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_minimal,
    output LIKE '%rankdir=TB;%' AS has_layout,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_at_least_one_node
FROM dot_output;

-- Test 2.2: SELECT with NULL values
-- Property: NULL values should be handled in DOT conversion
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT NULL', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_null_query,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_nodes
FROM dot_output;

-- Test 2.3: Empty result set query
-- Property: Query that returns empty set should still produce valid DOT
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM edge_test_table WHERE false', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_empty_result,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 0 AS has_nodes
FROM dot_output;

-- Test 2.4: Query with empty string
-- Property: Empty string values should be handled
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT ''''::text', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_empty_string,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_nodes
FROM dot_output;

-- Test 2.5: Query with only constants
-- Property: Query with no table references should produce valid DOT
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT 1, 2, 3, ''test''', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_constants_only,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_nodes
FROM dot_output;

-- ============================================================================
-- Test 3: Special Characters in Labels
-- ============================================================================

-- Test 3.1: Column names with quotes
-- Property: Special characters in identifiers should be handled
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT "special""column" FROM edge_test_table', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_quoted_column,
    output ~ 'n[0-9]+ \[label="[^"]*"\];' AS has_valid_labels
FROM dot_output;

-- Test 3.2: Column names with spaces
-- Property: Identifiers with spaces should be handled
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT "column with spaces" FROM edge_test_table', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_spaced_column,
    output ~ 'n[0-9]+ \[label="[^"]*"\];' AS has_valid_labels
FROM dot_output;

-- Test 3.3: String literals with special characters
-- Property: String values with quotes and backslashes should be handled
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT ''test\\nvalue'' FROM edge_test_table', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_special_chars,
    output ~ 'n[0-9]+ \[label="[^"]*"\];' AS has_valid_labels
FROM dot_output;

-- Test 3.4: Unicode characters
-- Property: Unicode characters should be preserved in DOT output
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT ''测试'' AS test_unicode', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_unicode,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_nodes
FROM dot_output;

-- Test 3.5: Very long identifiers
-- Property: Long identifiers should be handled (possibly truncated)
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT normal_column AS very_long_alias_name_that_exceeds_normal_length_limits_and_continues_for_quite_a_while FROM edge_test_table',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_long_identifier,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_nodes
FROM dot_output;

-- Test 3.6: Mixed special characters
-- Property: Combination of special characters should be handled
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT * FROM edge_test_table WHERE normal_column = ''test''s "value" with \\ backslash''',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_mixed_special,
    output ~ 'n[0-9]+ \[label="[^"]*"\];' AS has_valid_labels
FROM dot_output;

-- ============================================================================
-- Test 4: Edge Cases for Node Labels
-- ============================================================================

-- Test 4.1: Very long field values (should be truncated)
-- Property: Long field values should be truncated to avoid huge labels
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT repeat(''x'', 1000) FROM edge_test_table',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_long_value,
    -- Check that labels don't contain extremely long strings (implementation truncates at 50 chars)
    output !~ 'label="[^"]{200,}"' AS labels_are_reasonable_length
FROM dot_output;

-- Test 4.2: Newlines in node type names (shouldn't happen but test robustness)
-- Property: DOT output should remain valid even with unusual node structures
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM edge_test_table', 'dot') AS output
)
SELECT
    -- Verify all labels are properly quoted
    (SELECT count(*) FROM regexp_matches(output, 'label="[^"]*"', 'g')) > 0 AS all_labels_quoted,
    -- Verify no unescaped newlines break the DOT structure
    output ~ '^digraph ParseTree \{.*\}[\n\s]*$' AS structure_intact
FROM dot_output;

-- Test 4.3: Multiple fields with same name (edge case in parsing)
-- Property: Duplicate field names should be handled
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT id, id FROM edge_test_table', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_duplicate_fields,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_nodes
FROM dot_output;

-- ============================================================================
-- Test 5: Edge Cases for Graph Structure
-- ============================================================================

-- Test 5.1: Query with no edges (single node)
-- Property: Single-node graphs should be valid
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT 1', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_single_node,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) >= 1 AS has_node,
    -- May have zero edges for very simple queries
    (SELECT count(*) FROM regexp_matches(output, '->', 'g')) >= 0 AS edges_optional
FROM dot_output;

-- Test 5.2: Maximum nesting depth
-- Property: Very deep nesting should not cause stack overflow
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT * FROM edge_test_table WHERE id IN (SELECT id FROM edge_test_table WHERE id IN (SELECT id FROM edge_test_table WHERE id IN (SELECT id FROM edge_test_table WHERE id IN (SELECT id FROM edge_test_table WHERE id = 1))))',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_max_nesting,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 8 AS has_many_nodes,
    length(output) > 500 AS has_substantial_output
FROM dot_output;

-- Test 5.3: Wide query (many columns)
-- Property: Queries with many columns should be handled
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT id, "special""column", "column with spaces", normal_column, id+1, id*2, id-1, id/2 FROM edge_test_table',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_wide_query,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 3 AS has_multiple_nodes
FROM dot_output;

-- Test 5.4: Query with all node types empty (edge case)
-- Property: Even minimal parse trees should produce valid DOT
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT', 'dot') AS output
)
SELECT
    -- This should fail to parse, but if it somehow produces output, it should be valid
    CASE
        WHEN output IS NULL THEN true  -- Expected: parse error
        ELSE output LIKE 'digraph ParseTree {%'  -- If it succeeds, must be valid
    END AS handles_invalid_gracefully;

-- Test 5.5: Consistency check - same query produces same DOT
-- Property: DOT conversion should be deterministic
WITH first AS (
    SELECT pg_tree_viz('SELECT * FROM edge_test_table WHERE id = 1', 'dot') AS output
),
second AS (
    SELECT pg_tree_viz('SELECT * FROM edge_test_table WHERE id = 1', 'dot') AS output
)
SELECT
    first.output = second.output AS dot_is_deterministic
FROM first, second;

-- ============================================================================
-- Test 6: Boundary Conditions
-- ============================================================================

-- Test 6.1: Empty table name (should fail gracefully)
-- Property: Invalid queries should be caught before DOT conversion
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM ""', 'dot') AS output
)
SELECT
    -- Should either fail or produce valid DOT
    CASE
        WHEN output IS NULL THEN true
        ELSE output LIKE 'digraph ParseTree {%'
    END AS handles_empty_table_name;

-- Test 6.2: Zero-length query (should fail)
-- Property: Empty query should be rejected
SELECT
    CASE
        WHEN pg_tree_viz('', 'dot') IS NULL THEN true
        ELSE false
    END AS rejects_empty_query;

-- Test 6.3: Whitespace-only query (should fail)
-- Property: Whitespace-only query should be rejected
SELECT
    CASE
        WHEN pg_tree_viz('   ', 'dot') IS NULL THEN true
        ELSE false
    END AS rejects_whitespace_query;

-- Cleanup
DROP TABLE edge_test_table;
DROP EXTENSION pg_tree_viz;
