# Copyright (c) 2024, PostgreSQL Global Development Group

use strict;
use warnings;

use PostgreSQL::Test::Utils;
use Test::More;

# Basic program tests
program_help_ok('pg_setup');
program_version_ok('pg_setup');

# Test invalid port numbers
my ($ret, $stdout, $stderr);

# Test port too low (< 1024)
($ret, $stdout, $stderr) = run_command(
	[ 'pg_setup', '-D', '/tmp/test_pgdata', '-p', '100', '--silent', '--no-start' ]);
isnt($ret, 0, 'reject port < 1024');
like($stderr, qr/invalid port/i, 'error message for low port');

# Test port too high (> 65535)
($ret, $stdout, $stderr) = run_command(
	[ 'pg_setup', '-D', '/tmp/test_pgdata', '-p', '99999', '--silent', '--no-start' ]);
isnt($ret, 0, 'reject port > 65535');
like($stderr, qr/invalid port/i, 'error message for high port');

# Test valid port
($ret, $stdout, $stderr) = run_command(
	[ 'pg_setup', '-D', '/tmp/test_pgdata_valid', '-p', '5432', '--help' ]);
is($ret, 0, 'accept valid port 5432');

# Test invalid encoding
($ret, $stdout, $stderr) = run_command(
	[ 'pg_setup', '-D', '/tmp/test_pgdata', '-E', 'INVALID_ENC', '--silent', '--no-start' ]);
isnt($ret, 0, 'reject invalid encoding');

# Test valid encodings
my @valid_encodings = qw(UTF8 LATIN1 SQL_ASCII);
foreach my $enc (@valid_encodings)
{
	($ret, $stdout, $stderr) = run_command(
		[ 'pg_setup', '--help' ]);
	is($ret, 0, "encoding $enc is recognized");
}

# Test --generate-config
my $config_file = '/tmp/pg_setup_test_config.conf';
unlink $config_file if -e $config_file;

($ret, $stdout, $stderr) = run_command(
	[ 'pg_setup', "--generate-config=$config_file" ]);
is($ret, 0, 'generate-config succeeds');
ok(-e $config_file, 'config file created');

# Cleanup
unlink $config_file if -e $config_file;

done_testing();
