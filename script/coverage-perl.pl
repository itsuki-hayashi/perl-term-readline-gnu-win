#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/../build/author/lib/perl5";
use lib "$FindBin::Bin/../inc";
use Cwd              qw(abs_path);
use File::Path       qw(make_path);
use File::Temp       qw(tempdir);
use JSON::PP         qw(decode_json);
use Devel::Cover::DB ();
use Gnu::Build       ();
use Gnu::Quality     ();

chdir "$FindBin::Bin/.." or die "Cannot enter checkout: $!";

# A warning while reading/merging coverage can mean an incomplete report.
local $SIG{__WARN__} = sub { die "Coverage tool warning: @_"; };
my $tools = decode_json( Gnu::Build::slurp('config/author-tools.json') );
die "Wrong Devel::Cover version\n"
    unless Devel::Cover::DB->VERSION eq $tools->{coverage}{'Devel::Cover'};
make_path('build/quality');

# Fresh databases prevent stale runs from inflating coverage.
my $directory = tempdir( 'coverage-XXXX', DIR => 'build/quality', CLEANUP => 0 );
my $base      = abs_path($directory);
$base =~ tr{\\}{/};
my $database = "$base/tests-db";
local $ENV{PERL5LIB} = join ';', abs_path('build/author/lib/perl5'), ( $ENV{PERL5LIB} // () );
my $calibration = "$directory/calibration.pl";
open my $probe, '>:raw', $calibration or die $!;
print {$probe} <<'PERL' or die $!;
use v5.44;
use strict;
use warnings;
sub choose ($value) {
    if ($value) {
        return 1;
    } else {
        return 0;
    }
}
print choose(1), choose(0), "\n";
PERL
close $probe or die $!;
my ( $probe_status, $probe_output ) =
    Gnu::Quality::capture( $^X,
    "-MDevel::Cover=-db,$base/calibration-db,-coverage,statement,branch,-silent,1", $calibration, );
die "Coverage calibration failed ($probe_status): $probe_output\n"
    unless !$probe_status && $probe_output =~ /\A10\r?\n\z/;
my $probe_db = Devel::Cover::DB->new( db => "$base/calibration-db" );
$probe_db->merge_runs;
$probe_db->calculate_summary( statement => 1, branch => 1 );
open my $calibration_report, '>:raw', 'build/quality/calibration.json' or die $!;
print {$calibration_report} JSON::PP->new->canonical->pretty->encode( $probe_db->summary('Total') )
    or die $!;
close $calibration_report or die $!;

for my $criterion (qw(statement branch)) {
    my $value = $probe_db->summary( 'Total', $criterion );
    die "Unsupported $criterion instrumentation: calibration did not cover both paths\n"
        unless $value && $value->{total} && $value->{percentage} == 100;
}
local $ENV{HARNESS_PERL_SWITCHES} =
    qq(-Mblib "-MDevel::Cover=-db,$database,-coverage,statement,branch,-silent,1,+ignore,build/author/");
local $ENV{AUTHOR_TESTING} = 1;
local $ENV{TERM}           = 'win32';
my @tests = ( sort glob('t/*.t'), 'xt/perl-quality.t' );
my ( $status, $log ) =
    Gnu::Quality::capture( $^X, '-MTest::Harness', '-e', 'runtests(@ARGV)', @tests, );
open my $output, '>:raw', 'build/quality/coverage-tests.log' or die $!;
print {$output} $log or die $!;
close $output        or die $!;
die "Instrumented tests failed ($status):\n$log" if $status;
my $db = Devel::Cover::DB->new( db => $database );
$db->merge_runs;
$db->calculate_summary( statement => 1, branch => 1 );
my %actual;

for my $file ( sort keys $db->{summary}->%* ) {
    next if $file eq 'Total';
    ( my $name = $file ) =~ s{^blib/lib/}{lib/};
    next unless $name =~ m{^(?:lib/|inc/Gnu/)};
    for my $criterion (qw(statement branch)) {
        my $value = $db->summary( $file, $criterion );
        next unless $value && $value->{total};
        $actual{$name}{$criterion} = {
            covered    => $value->{covered},
            total      => $value->{total},
            percentage => $value->{percentage},
        };
    }
}
die "No project coverage was collected\n" unless keys %actual;
open my $report, '>:raw', 'build/quality/coverage.json' or die $!;
print {$report} JSON::PP->new->canonical->pretty->encode( \%actual ) or die $!;
close $report                                                        or die $!;
my $baseline = decode_json( Gnu::Build::slurp('config/coverage-baseline.json') );
die "Empty coverage baseline\n" unless keys $baseline->{minimum_percent}->%*;
my @errors = Gnu::Quality::coverage_errors( $baseline->{minimum_percent}, \%actual );
die @errors if @errors;
print "Instrumented tests and per-module coverage baselines passed.\n";
