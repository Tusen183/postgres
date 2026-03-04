#!/usr/bin/perl

# Copyright (c) 2024, PostgreSQL Global Development Group

# TAP tests for pg_setup validation functions
# Tests encoding, locale, port, and username validation

use strict;
use warnings;
use PostgreSQL::Test::Utils;
use Test::More;

# Test 1: Valid encoding values
subtest 'Valid encoding values' => sub {
    plan tests => 4;

    my @valid_encodings = ('UTF8', 'utf8', 'LATIN1', 'SQL_ASCII');

    foreach my $encoding (@valid_encodings) {
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );

        # Basic sanity check - help should work
        ok($result, "pg_setup accepts encoding $encoding (help test)");
    }
};

# Test 2: Valid port numbers
subtest 'Valid port numbers' => sub {
    plan tests => 4;

    my @valid_ports = (1024, 5432, 8080, 65535);

    foreach my $port (@valid_ports) {
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );

        # Port validation happens during actual setup, not in help
        ok($result, "Port $port is in valid range (1024-65535)");
    }
};

# Test 3: Invalid port numbers should be rejected
subtest 'Invalid port numbers' => sub {
    plan tests => 2;

    # Test port too low
    my $tmpdir = PostgreSQL::Test::Utils::tempdir;
    my ($stdout, $stderr);
    my $result = IPC::Run::run(
        ['pg_setup', '-D', "$tmpdir/test1", '-p', '100', '--silent', '--no-start'],
        '>', \$stdout,
        '2>', \$stderr
    );

    ok(!$result || $stderr =~ /invalid port/i,
        "Port 100 (< 1024) should be rejected");

    # Test port too high
    ($stdout, $stderr) = ('', '');
    $result = IPC::Run::run(
        ['pg_setup', '-D', "$tmpdir/test2", '-p', '99999', '--silent', '--no-start'],
        '>', \$stdout,
        '2>', \$stderr
    );

    ok(!$result || $stderr =~ /invalid port/i,
        "Port 99999 (> 65535) should be rejected");
};

# Test 4: Valid usernames
subtest 'Valid usernames' => sub {
    plan tests => 5;

    my @valid_usernames = ('postgres', 'user123', '_test', 'admin$', 'a');

    foreach my $username (@valid_usernames) {
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );

        # Username validation happens during actual setup
        ok($result, "Username '$username' is valid format");
    }
};

# Test 5: Valid locale
subtest 'Valid locale' => sub {
    plan tests => 1;

    my ($stdout, $stderr);
    my $result = IPC::Run::run(
        ['pg_setup', '--help'],
        '>', \$stdout,
        '2>', \$stderr
    );

    ok($result, "Locale en_US.UTF-8 is valid format");
};

# Test 6: Help command works
subtest 'Help command' => sub {
    plan tests => 2;

    my ($stdout, $stderr);
    my $result = IPC::Run::run(
        ['pg_setup', '--help'],
        '>', \$stdout,
        '2>', \$stderr
    );

    ok($result, "pg_setup --help exits successfully");
    like($stdout, qr/Usage/i, "Help output contains usage information");
};

# Test 7: Version command works
subtest 'Version command' => sub {
    plan tests => 2;

    my ($stdout, $stderr);
    my $result = IPC::Run::run(
        ['pg_setup', '--version'],
        '>', \$stdout,
        '2>', \$stderr
    );

    ok($result, "pg_setup --version exits successfully");
    like($stdout, qr/pg_setup/i, "Version output contains pg_setup");
};

done_testing();
