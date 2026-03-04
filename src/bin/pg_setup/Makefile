#-------------------------------------------------------------------------
#
# Makefile for src/bin/pg_setup
#
# Portions Copyright (c) 1996-2023, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/bin/pg_setup/Makefile
#
#-------------------------------------------------------------------------

PGFILEDESC = "pg_setup - simplified PostgreSQL installation tool"
PGAPPICON=win32

subdir = src/bin/pg_setup
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

override CPPFLAGS := -I$(libpq_srcdir) $(CPPFLAGS)

# We need libpq for connection verification and fe_utils for common utilities
LDFLAGS_INTERNAL += -L$(top_builddir)/src/fe_utils -lpgfeutils $(libpq_pgport)

OBJS = \
	$(WIN32RES) \
	pg_setup.o

TEST_OBJS = \
	test_config_defaults.o

all: pg_setup

# Build test executables
test_config_defaults: $(TEST_OBJS) | submake-libpgport submake-libpgfeutils
	$(CC) $(CFLAGS) $(TEST_OBJS) $(LDFLAGS) $(LDFLAGS_EX) $(LIBS) -o $@$(X)

pg_setup: $(OBJS) | submake-libpq submake-libpgport submake-libpgfeutils
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) $(LDFLAGS_EX) $(LIBS) -o $@$(X)

install: all installdirs
	$(INSTALL_PROGRAM) pg_setup$(X) '$(DESTDIR)$(bindir)/pg_setup$(X)'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(bindir)'

uninstall:
	rm -f '$(DESTDIR)$(bindir)/pg_setup$(X)'

clean distclean maintainer-clean:
	rm -f pg_setup$(X) $(OBJS) test_config_defaults$(X) $(TEST_OBJS)
	rm -rf tmp_check

# ensure that changes in datadir propagate into object file
pg_setup.o: pg_setup.c $(top_builddir)/src/Makefile.global

check:
	$(MAKE) test_config_defaults
	./test_config_defaults$(X)
	$(prove_check)

installcheck:
	$(prove_installcheck)
