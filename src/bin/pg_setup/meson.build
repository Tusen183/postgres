# Copyright (c) 2022-2023, PostgreSQL Global Development Group

pg_setup_sources = files(
  'pg_setup.c',
)

if host_system == 'windows'
  pg_setup_sources += rc_bin_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'pg_setup',
    '--FILEDESC', 'pg_setup - simplified PostgreSQL installation tool',])
endif

pg_setup = executable('pg_setup',
  pg_setup_sources,
  dependencies: [frontend_code, libpq],
  kwargs: default_bin_args,
)
bin_targets += pg_setup

tests += {
  'name': 'pg_setup',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'tap': {
    'tests': [
      't/001_validation.pl',
    ],
  },
}

subdir('po', if_found: libintl)
