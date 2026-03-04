-- Test 1: Parse stage (raw parse tree)
SELECT pg_tree_viz_parse('SELECT * FROM t WHERE a = 1', 'raw');

-- Test 2: Analyze stage (Query structure)
SELECT pg_tree_viz('SELECT * FROM t WHERE a = 1', 'raw');

-- Test 3: Test UPDATE with alias
SELECT pg_tree_viz_parse('UPDATE t AS t1 SET a=1 WHERE t1.a=1', 'raw');

-- Test 4: Analyze stage for UPDATE
SELECT pg_tree_viz('UPDATE t AS t1 SET a=1 WHERE t1.a=1', 'raw');

-- Test 5: Test DOT format for parse stage
SELECT pg_tree_viz_parse('SELECT * FROM t WHERE a = 1', 'dot');
