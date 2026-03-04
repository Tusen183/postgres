-- Test hook-based visualization

-- Enable the extension
SET pg_tree_viz.enabled = true;

-- Test 1: Visualize analyze stage
SET pg_tree_viz.viz_stage = 'analyze';
SET pg_tree_viz.output_format = 'raw';
SET pg_tree_viz.output_file = '';

SELECT * FROM t WHERE a = 1;

-- Test 2: Visualize plan stage
SET pg_tree_viz.viz_stage = 'plan';
SELECT * FROM t WHERE a = 1;

-- Test 3: Test UPDATE with alias at analyze stage
SET pg_tree_viz.viz_stage = 'analyze';
UPDATE t AS t1 SET a=1 WHERE t1.a=1;

-- Test 4: Test UPDATE at plan stage
SET pg_tree_viz.viz_stage = 'plan';
UPDATE t AS t1 SET a=2 WHERE t1.a=1;
