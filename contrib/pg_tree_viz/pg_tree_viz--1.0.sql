/* contrib/pg_tree_viz/pg_tree_viz--1.0.sql */

\echo Use "CREATE EXTENSION pg_tree_viz" to load this file. \quit

CREATE FUNCTION pg_tree_viz_parse(
    query text,
    format text DEFAULT 'raw'
)
RETURNS text
AS 'MODULE_PATHNAME', 'pg_tree_viz_parse'
LANGUAGE C STRICT;

CREATE FUNCTION pg_tree_viz(
    query text
)
RETURNS text
AS 'MODULE_PATHNAME', 'pg_tree_viz_query'
LANGUAGE C STRICT;

CREATE FUNCTION pg_tree_viz(
    query text,
    format text
)
RETURNS text
AS 'MODULE_PATHNAME', 'pg_tree_viz_query'
LANGUAGE C STRICT;
