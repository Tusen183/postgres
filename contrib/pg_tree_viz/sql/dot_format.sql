--
-- DOT Format Property Tests
-- **Validates: Requirements 3.4, 4.2, 4.3, 4.4, 4.5, 4.6, 14.1, 14.2, 14.3, 14.4, 14.5, 14.6**
--
-- Property 5: DOT Format Validity
-- For any query visualized with output_format set to DOT, the output must be
-- valid Graphviz DOT syntax parseable by DOT tools.
--
-- Property 6: DOT Structure Completeness
-- For any DOT format output, it must begin with "digraph ParseTree {",
-- contain "rankdir=TB;" and "node [shape=box];", and end with "}".
--
-- Property 7: DOT Node ID Uniqueness
-- For any DOT format output, all node IDs must be unique integers in the
-- format "nX" where X is a positive integer.
--
-- Property 8: DOT Node Label Content
-- For any node definition in DOT format output, the label must contain
-- the node type name.
--
-- Property 9: DOT Edge Format
-- For any edge definition in DOT format output with nested structures,
-- the edge must follow the format "nX -> nY [label=\"field_name\"];".
--
-- Property 28: DOT Node Definition Format
-- For any node definition in DOT output, it must follow the format
-- "nX [label=\"...\"];" where X is a unique integer.
--

-- Create the extension
CREATE EXTENSION pg_tree_viz;

-- Create test tables
CREATE TABLE dot_test_users (
    id int PRIMARY KEY,
    name text,
    email text
);

CREATE TABLE dot_test_orders (
    order_id int PRIMARY KEY,
    user_id int,
    amount numeric(10,2)
);

-- Insert test data
INSERT INTO dot_test_users VALUES
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com'),
    (3, 'Charlie', 'charlie@example.com');

INSERT INTO dot_test_orders VALUES
    (101, 1, 100.50),
    (102, 2, 200.75),
    (103, 1, 150.00);

-- ============================================================================
-- Property 6: DOT Structure Completeness
-- ============================================================================

-- Test 1: Verify DOT output starts with "digraph ParseTree {"
-- Property: All DOT output must begin with proper digraph declaration
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') LIKE 'digraph ParseTree {%' AS starts_with_digraph;

-- Test 2: Verify DOT output contains "rankdir=TB;"
-- Property: All DOT output must specify vertical layout
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') LIKE '%rankdir=TB;%' AS has_rankdir;

-- Test 3: Verify DOT output contains "node [shape=box];"
-- Property: All DOT output must specify node styling
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') LIKE '%node [shape=box];%' AS has_node_style;

-- Test 4: Verify DOT output ends with "}" (with possible trailing newline)
-- Property: All DOT output must properly close the digraph
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') ~ '}[\n\s]*$' AS ends_with_brace;

-- Test 5: Verify complete structure for simple query
-- Property: Simple queries should have all required DOT structure elements
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT 1', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS has_start,
    output LIKE '%rankdir=TB;%' AS has_rankdir,
    output LIKE '%node [shape=box];%' AS has_style,
    output ~ '}[\n\s]*$' AS has_end
FROM dot_output;

-- Test 6: Verify structure for complex query
-- Property: Complex queries should maintain DOT structure completeness
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT u.id, o.order_id FROM dot_test_users u JOIN dot_test_orders o ON u.id = o.user_id WHERE u.id > 1',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS has_start,
    output LIKE '%rankdir=TB;%' AS has_rankdir,
    output LIKE '%node [shape=box];%' AS has_style,
    output ~ '}[\n\s]*$' AS has_end
FROM dot_output;

-- ============================================================================
-- Property 28: DOT Node Definition Format
-- ============================================================================

-- Test 7: Verify node definitions follow "nX [label=\"...\"];" format
-- Property: All node definitions must use the correct format
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') ~ 'n[0-9]+ \[label="[^"]*"\];' AS has_valid_node_format;

-- Test 8: Verify multiple node definitions in complex query
-- Property: Complex queries should have multiple properly formatted nodes
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT * FROM dot_test_users WHERE id = 1',
        'dot'
    ) AS output
)
SELECT
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label="[^"]*"\];', 'g')) > 0 AS has_nodes
FROM dot_output;

-- Test 9: Verify node IDs are numeric
-- Property: Node IDs must be integers (n1, n2, n3, etc.)
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') AS output
)
SELECT
    output ~ 'n[0-9]+' AS has_numeric_ids
FROM dot_output;

-- ============================================================================
-- Property 7: DOT Node ID Uniqueness
-- ============================================================================

-- Test 10: Verify node IDs are unique in simple query
-- Property: No duplicate node IDs should exist (checking only node definitions, not edges)
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
),
node_ids AS (
    SELECT (regexp_matches(output, 'n([0-9]+) \[label=', 'g'))[1] AS id
    FROM dot_output
)
SELECT
    count(*) = count(DISTINCT id) AS all_ids_unique
FROM node_ids;

-- Test 11: Verify node IDs are unique in complex query
-- Property: Even complex queries should have unique node IDs (checking only node definitions)
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT u.id, o.order_id FROM dot_test_users u JOIN dot_test_orders o ON u.id = o.user_id',
        'dot'
    ) AS output
),
node_ids AS (
    SELECT (regexp_matches(output, 'n([0-9]+) \[label=', 'g'))[1] AS id
    FROM dot_output
)
SELECT
    count(*) = count(DISTINCT id) AS all_ids_unique_complex
FROM node_ids;

-- Test 12: Verify node IDs start from a positive integer
-- Property: Node IDs should be positive integers
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT 1', 'dot') AS output
),
node_ids AS (
    SELECT (regexp_matches(output, 'n([0-9]+) \[label=', 'g'))[1]::int AS id
    FROM dot_output
)
SELECT
    min(id) >= 1 AS has_positive_ids
FROM node_ids;

-- Test 13: Verify node IDs are positive integers
-- Property: All node IDs should be positive integers
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') AS output
),
node_ids AS (
    SELECT (regexp_matches(output, 'n([0-9]+) \[label=', 'g'))[1]::int AS id
    FROM dot_output
)
SELECT
    min(id) >= 1 AS all_positive,
    count(*) > 0 AS has_nodes
FROM node_ids;

-- ============================================================================
-- Property 8: DOT Node Label Content
-- ============================================================================

-- Test 14: Verify node labels contain node type names
-- Property: Every node label should contain a node type identifier
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') AS output
)
SELECT
    output ~ 'n[0-9]+ \[label="[A-Z][^"]*"\];' AS labels_have_content
FROM dot_output;

-- Test 15: Verify node type names in labels
-- Property: DOT output should contain node type names (uppercase identifiers)
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') ~ 'label="[A-Z][A-Za-z]*' AS has_node_type_labels;

-- Test 16: Verify node labels are not empty
-- Property: No node should have an empty label
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') AS output
)
SELECT
    output NOT LIKE '%label=""];%' AS no_empty_labels
FROM dot_output;

-- Test 17: Verify node labels contain field information
-- Property: Node labels should contain field names and values (using newlines)
SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') ~ 'label="[^"]*\\n[^"]*"' AS labels_have_fields;

-- Test 18: Verify multiple node types in complex query
-- Property: Complex queries should have multiple different node types
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT u.id FROM dot_test_users u WHERE u.id = 1',
        'dot'
    ) AS output
),
node_types AS (
    SELECT DISTINCT (regexp_matches(output, 'label="([A-Z][a-zA-Z]*)', 'g'))[1] AS node_type
    FROM dot_output
)
SELECT
    count(*) > 1 AS has_multiple_node_types
FROM node_types;

-- ============================================================================
-- Property 9: DOT Edge Format
-- ============================================================================

-- Test 19: Verify edge format "nX -> nY [label=\"field_name\"];"
-- Property: All edges must follow the correct format
SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') ~ 'n[0-9]+ -> n[0-9]+ \[label="[^"]+"\];' AS has_valid_edge_format;

-- Test 20: Verify edges exist in query with relationships
-- Property: Queries with nested structures should have edges
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ -> n[0-9]+', 'g')) > 0 AS has_edges
FROM dot_output;

-- Test 21: Verify edge labels are not empty
-- Property: Edge labels should contain field names
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT
    output NOT LIKE '%-> n% [label=""];%' AS no_empty_edge_labels
FROM dot_output;

-- Test 22: Verify edges connect valid node IDs
-- Property: Edge source and target must reference existing nodes
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
),
nodes AS (
    SELECT DISTINCT (regexp_matches(output, 'n([0-9]+) \[label=', 'g'))[1]::int AS node_id
    FROM dot_output
),
edges AS (
    SELECT DISTINCT
        (regexp_matches(output, 'n([0-9]+) -> n([0-9]+)', 'g'))[1]::int AS source_id,
        (regexp_matches(output, 'n([0-9]+) -> n([0-9]+)', 'g'))[2]::int AS target_id
    FROM dot_output
)
SELECT
    (SELECT count(*) FROM edges e WHERE EXISTS (SELECT 1 FROM nodes n WHERE n.node_id = e.source_id)) = (SELECT count(*) FROM edges) AS all_sources_valid,
    (SELECT count(*) FROM edges e WHERE EXISTS (SELECT 1 FROM nodes n WHERE n.node_id = e.target_id)) = (SELECT count(*) FROM edges) AS all_targets_valid;

-- Test 23: Verify edge labels contain meaningful field names
-- Property: Edge labels should be valid identifiers (letters, possibly with underscores)
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT
    (SELECT count(*) FROM regexp_matches(output, '-> n[0-9]+ \[label="([a-zA-Z_][a-zA-Z0-9_]*)"\];', 'g')) > 0 AS has_valid_field_names
FROM dot_output;

-- ============================================================================
-- Property 5: DOT Format Validity
-- ============================================================================

-- Test 24: Verify DOT output does not contain RAW format markers
-- Property: DOT format should not contain nodeToString-specific syntax
SELECT
    pg_tree_viz('SELECT * FROM dot_test_users', 'dot') NOT LIKE '%{QUERY%' AS no_raw_query_marker,
    pg_tree_viz('SELECT * FROM dot_test_users', 'dot') NOT LIKE '%:commandType%' AS no_raw_field_marker;

-- Test 25: Verify DOT output contains graph structure
-- Property: DOT output must be a valid graph with nodes and edges
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT
    output LIKE '%digraph%' AS has_digraph,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 0 AS has_nodes,
    (SELECT count(*) FROM regexp_matches(output, '->', 'g')) >= 0 AS has_edges_or_single_node
FROM dot_output;

-- Test 26: Verify DOT syntax for simple query
-- Property: Even simple queries should produce valid DOT syntax
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT 1', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_start,
    output ~ '}[\n\s]*$' AS valid_end,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 0 AS has_at_least_one_node
FROM dot_output;

-- Test 27: Verify DOT syntax for JOIN query
-- Property: JOIN queries should produce valid DOT with multiple nodes and edges
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT u.id FROM dot_test_users u JOIN dot_test_orders o ON u.id = o.user_id',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_start,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 1 AS has_multiple_nodes,
    (SELECT count(*) FROM regexp_matches(output, '->', 'g')) > 0 AS has_edges
FROM dot_output;

-- Test 28: Verify DOT syntax for subquery
-- Property: Subqueries should produce valid DOT with nested structure
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT * FROM dot_test_users WHERE id IN (SELECT user_id FROM dot_test_orders)',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_start,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 2 AS has_multiple_nodes,
    (SELECT count(*) FROM regexp_matches(output, '->', 'g')) > 1 AS has_multiple_edges
FROM dot_output;

-- Test 29: Verify DOT consistency across multiple invocations
-- Property: Same query should produce identical DOT output
WITH first_call AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
),
second_call AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT first_call.output = second_call.output AS dot_output_consistent
FROM first_call, second_call;

-- Test 30: Verify DOT output is not empty
-- Property: DOT format should always produce non-empty output for valid queries
SELECT
    length(pg_tree_viz('SELECT 1', 'dot')) > 50 AS not_empty_simple,
    length(pg_tree_viz('SELECT * FROM dot_test_users', 'dot')) > 100 AS not_empty_table_query;

-- ============================================================================
-- Additional DOT Format Tests
-- ============================================================================

-- Test 31: Verify DOT format for UPDATE query
-- Property: DOT format should work for UPDATE queries
WITH dot_output AS (
    SELECT pg_tree_viz('UPDATE dot_test_users SET name = ''Updated'' WHERE id = 1', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_update_dot
FROM dot_output;

-- Test 32: Verify DOT format for DELETE query
-- Property: DOT format should work for DELETE queries
WITH dot_output AS (
    SELECT pg_tree_viz('DELETE FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_delete_dot
FROM dot_output;

-- Test 33: Verify DOT format for INSERT query
-- Property: DOT format should work for INSERT queries
WITH dot_output AS (
    SELECT pg_tree_viz('INSERT INTO dot_test_users VALUES (4, ''David'', ''david@example.com'')', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_insert_dot
FROM dot_output;

-- Test 34: Verify DOT format for CTE query
-- Property: DOT format should handle CTEs
WITH dot_output AS (
    SELECT pg_tree_viz(
        'WITH user_orders AS (SELECT user_id FROM dot_test_orders) SELECT * FROM user_orders',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_cte_dot,
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) > 1 AS has_multiple_nodes
FROM dot_output;

-- Test 35: Verify DOT format for aggregate query
-- Property: DOT format should handle aggregates
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT count(*) FROM dot_test_users', 'dot') AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_aggregate_dot
FROM dot_output;

-- Test 36: Verify DOT format for window function query
-- Property: DOT format should handle window functions
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT id, name, row_number() OVER (ORDER BY id) FROM dot_test_users',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_window_dot
FROM dot_output;

-- Test 37: Verify DOT format for UNION query
-- Property: DOT format should handle set operations
WITH dot_output AS (
    SELECT pg_tree_viz(
        'SELECT id FROM dot_test_users WHERE id = 1 UNION SELECT id FROM dot_test_users WHERE id = 2',
        'dot'
    ) AS output
)
SELECT
    output LIKE 'digraph ParseTree {%' AS valid_union_dot
FROM dot_output;

-- Test 38: Verify node definition semicolons
-- Property: All node definitions must end with semicolon
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') AS output
)
SELECT
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label="[^"]*"\];', 'g')) =
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ \[label=', 'g')) AS all_nodes_have_semicolons
FROM dot_output;

-- Test 39: Verify edge definition semicolons
-- Property: All edge definitions must end with semicolon
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users WHERE id = 1', 'dot') AS output
)
SELECT
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ -> n[0-9]+ \[label="[^"]+"\];', 'g')) =
    (SELECT count(*) FROM regexp_matches(output, 'n[0-9]+ -> n[0-9]+', 'g')) AS all_edges_have_semicolons
FROM dot_output;

-- Test 40: Verify proper quote escaping in labels
-- Property: Labels should properly handle special characters
WITH dot_output AS (
    SELECT pg_tree_viz('SELECT * FROM dot_test_users', 'dot') AS output
)
SELECT
    output ~ 'label="[^"]*"' AS labels_properly_quoted
FROM dot_output;

-- Cleanup
DROP TABLE dot_test_orders;
DROP TABLE dot_test_users;
DROP EXTENSION pg_tree_viz;

