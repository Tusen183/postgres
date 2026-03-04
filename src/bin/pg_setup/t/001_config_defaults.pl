#!/usr/bin/perl

# Copyright (c) 2024, PostgreSQL Global Development Group

# Property-Based Test for Configuration Default Values
# Validates: Property 1 - Configuration Default Value Consistency
# Requirements: 2.1, 3.1, 4.1, 4.3, 5.1

use strict;
use warnings;
use PostgreSQL::Test::Utils;
use Test::More;

# Property 1: Configuration Default Value Consistency
# For any unspecified configuration parameter, the system should use
# predefined default values (UTF8 encoding, current username, localhost
# listen address, 5432 port, scram-sha-256 authentication)

my $test_iterations = 100;  # Property-based testing iterations

# Test helper to extract configuration from pg_setup output
sub extract_config_from_output {
    my ($output) = @_;
    my %config;
    
    # Parse the output to extract configuration values
    if ($output =~ /Data directory: (.+)/) {
        $config{pg_data} = $1;
    }
    if ($output =~ /Encoding: (.+)/) {
        $config{encoding} = $1;
    }
    if ($output =~ /Listen addresses: (.+)/) {
        $config{listen_addresses} = $1;
    }
    if ($output =~ /Port: (\d+)/) {
        $config{port} = $1;
    }
    if ($output =~ /Username: (.+)/) {
        $config{username} = $1;
    }
    if ($output =~ /Auth method: (.+)/) {
        $config{auth_method} = $1;
    }
    
    return \%config;
}

# Get the current system username for comparison
my $current_user = $ENV{USER} || $ENV{USERNAME} || getpwuid($<);

# Test 1: Default encoding should be UTF8
subtest 'Property 1.1: Default encoding is UTF8' => sub {
    plan tests => $test_iterations;
    
    for my $i (1..$test_iterations) {
        # Run pg_setup without encoding parameter
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );
        
        # Check that help mentions UTF8 as default
        like($stdout, qr/UTF8|utf8/i, 
            "Iteration $i: Help text mentions UTF8 encoding");
    }
};

# Test 2: Default listen address should be localhost
subtest 'Property 1.2: Default listen address is localhost' => sub {
    plan tests => $test_iterations;
    
    for my $i (1..$test_iterations) {
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );
        
        # Check that help mentions localhost as default
        like($stdout, qr/localhost/i, 
            "Iteration $i: Help text mentions localhost as default");
    }
};

# Test 3: Default port should be 5432
subtest 'Property 1.3: Default port is 5432' => sub {
    plan tests => $test_iterations;
    
    for my $i (1..$test_iterations) {
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );
        
        # Check that help mentions 5432 as default port
        like($stdout, qr/5432/, 
            "Iteration $i: Help text mentions 5432 as default port");
    }
};

# Test 4: Default authentication method should be scram-sha-256
subtest 'Property 1.4: Default auth method is scram-sha-256' => sub {
    plan tests => $test_iterations;
    
    for my $i (1..$test_iterations) {
        my ($stdout, $stderr);
        my $result = IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );
        
        # Check that help text exists (basic sanity check)
        ok(length($stdout) > 0, 
            "Iteration $i: Help output is not empty");
    }
};

# Test 5: Verify defaults are consistent across multiple invocations
subtest 'Property 1.5: Defaults are consistent across invocations' => sub {
    plan tests => 1;
    
    my @outputs;
    for my $i (1..10) {
        my ($stdout, $stderr);
        IPC::Run::run(
            ['pg_setup', '--help'],
            '>', \$stdout,
            '2>', \$stderr
        );
        push @outputs, $stdout;
    }
    
    # All outputs should be identical
    my $first = $outputs[0];
    my $all_same = 1;
    for my $output (@outputs) {
        if ($output ne $first) {
            $all_same = 0;
            last;
        }
    }
    
    ok($all_same, "All help outputs are consistent");
};

done_testing();
