# contrib/pg_tree_viz/Makefile

MODULE_big = pg_tree_viz
OBJS = \
	$(WIN32RES) \
	pg_tree_viz.o

EXTENSION = pg_tree_viz
DATA = pg_tree_viz--1.0.sql
PGFILEDESC = "pg_tree_viz - visualize SQL query parse trees"

REGRESS = hook_chain disabled_state query_immutability hook_error_handling raw_format_identity dot_format dot_edge_cases
REGRESS_OPTS = --temp-config=$(top_srcdir)/contrib/pg_tree_viz/pg_tree_viz.conf
NO_INSTALLCHECK = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pg_tree_viz
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
