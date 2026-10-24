# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
plan skip_all => 'Set AUTHOR_TESTING=1 for coverage-runner fixtures' unless $ENV{AUTHOR_TESTING};
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd        qw(abs_path);
use JSON::PP   qw(decode_json encode_json);
use lib 'inc';
use Gnu::Build   ();
use Gnu::Quality ();
make_path('build/quality');
my $stage = abs_path( tempdir( 'runner-tests-XXXX', DIR => 'build/quality', CLEANUP => 0 ) );
make_path(
    "$stage/script",                 "$stage/config",
    "$stage/build/author/lib/perl5", "$stage/blib/lib/Term/ReadLine/Gnu",
    "$stage/blib/lib/auto"
);
make_path("$stage/inc");

for my $file (
    qw(script/check-perl.pl script/release.pl script/test-archive.pl inc/build-native.pl Makefile.PL)
    )
{
    copy( $file, "$stage/$file" ) or die $!;
}
copy( 'script/coverage-perl.pl',     "$stage/script/coverage-perl.pl" )          or die $!;
copy( 'lib/Term/ReadLine/Gnu/XS.pm', "$stage/blib/lib/Term/ReadLine/Gnu/XS.pm" ) or die $!;
copy( 'config/author-tools.json',    "$stage/config/author-tools.json" )         or die $!;

sub baseline ( $empty = 0, $no_branches = 0 ) {
    open my $file, '>:raw', "$stage/config/coverage-baseline.json" or die $!;
    print {$file} encode_json(
        {
            expected_total =>
                { 'script/coverage-perl.pl' => { statement => 1, branch => $no_branches ? 0 : 2 } },
            minimum_percent => $empty
            ? {}
            : {
                'script/coverage-perl.pl' => { statement => 100, branch => 100 }
            }
        }
    ) or die $!;
    close $file or die $!;
}

sub run_case ( $scenario, $expected, $pattern, @flags ) {
    local $ENV{GNU_COVER_FIXTURE_SCENARIO} = $scenario;
    local $ENV{GNU_COVER_FIXTURE_TRACE}    = "$stage/trace.json";
    my ( $status, $output ) =
        Gnu::Quality::capture( $^X, 't/native/script-faults.pl', "$stage/script/coverage-perl.pl",
        'none', 0, @flags );
    is( $status == 0 ? 1 : 0, $expected, $scenario );
    like( $output, $pattern, "$scenario diagnostic" );
    return $output;
}
baseline();
run_case( 'complete', 0, qr/Usage:/,               '--unknown-option' );
run_case( 'complete', 0, qr/Unexpected arguments/, 'extra' );
run_case( 'warning',  0, qr/Coverage tool warning: fixture warning/ );
run_case( 'complete', 1, qr/baselines passed/ );
my $report = decode_json( Gnu::Build::slurp("$stage/build/quality/coverage-target.json") );
ok( $report->{complete}, 'complete fixture has explicit success' );
is( $report->{tests_exit_status}, 0, 'successful subprocess status retained' );
run_case( 'complete', 1, qr/baselines passed/, '--require-full' );
my $calls = decode_json( Gnu::Build::slurp("$stage/trace.json") );
is( scalar $calls->@*, 7,
    'full target requests calibration, tests, quality and four integrations' );
baseline( 0, 1 );
run_case( 'no-branches', 1, qr/baselines passed/, '--require-full' );
baseline();
run_case( 'partial-statement', 0, qr/below 100%/,                 '--require-full' );
run_case( 'excluded-site',     0, qr/Invalid branch measurement/, '--require-full' );
run_case( 'wrong-denominator', 0, qr/Unexpected branch total/,    '--require-full' );
run_case( 'partial',           0, qr/below 100%/,                 '--require-full' );
$report = decode_json( Gnu::Build::slurp("$stage/build/quality/coverage-target.json") );
ok( !$report->{complete}, 'partial target is explicitly incomplete' );
is( scalar $report->{uncovered}{'script/coverage-perl.pl'}{branch}->@*,
    1, 'uncovered branch is reported' );
run_case( 'partial',         0, qr/below 100/ );
run_case( 'missing-metric',  0, qr/Missing statement/, '--require-full' );
run_case( 'no-project',      0, qr/No project coverage/ );
run_case( 'bad-calibration', 0, qr/Unsupported branch instrumentation/ );
run_case( 'probe-fails',     0, qr/Coverage calibration failed/ );
run_case( 'probe-output',    0, qr/Coverage calibration failed/ );
run_case( 'tests-fail',      0, qr/Instrumented tests failed/ );
$report = decode_json( Gnu::Build::slurp("$stage/build/quality/coverage-target.json") );
ok( !$report->{complete}, 'failed tests cannot yield a complete target' );
run_case( 'command-fails', 0, qr/Instrumented tests failed/ );
baseline(1);
run_case( 'complete', 0, qr/Empty coverage baseline/ );
baseline();

for my $operation ( 'open', 'close', 'write' ) {
    for my $number ( 1 .. 5 ) {
        local $ENV{GNU_COVER_FIXTURE_SCENARIO} = 'complete';
        local $ENV{GNU_COVER_FIXTURE_TRACE}    = "$stage/trace.json";
        my ( $status, $output ) =
            Gnu::Quality::capture( $^X, 't/native/script-faults.pl',
            "$stage/script/coverage-perl.pl",
            $operation, $number );
        ok( $status != 0, "$operation failure $number rejects incomplete evidence" );
        like(
            $output,
            qr/(?:Coverage tool warning|[.]pl line [0-9]+)/,
            "$operation failure $number diagnostic"
        );
    }
}
{
    local $ENV{GNU_COVER_FIXTURE_SCENARIO} = 'complete';
    local $ENV{GNU_COVER_FIXTURE_TRACE}    = "$stage/trace.json";
    my ( $status, $output ) =
        Gnu::Quality::capture( $^X, 't/native/script-faults.pl', "$stage/script/coverage-perl.pl",
        'chdir', 1 );
    ok( $status != 0, 'root directory failure is rejected' );
    like( $output, qr/Cannot enter checkout/, 'root directory failure diagnostic' );

    # Leave an existing report so the next run must remove it.
    open my $stale, '>:raw', "$stage/build/quality/coverage.json" or die $!;
    print {$stale} '{}' or die $!;
    close $stale        or die $!;
    ( $status, $output ) =
        Gnu::Quality::capture( $^X, 't/native/script-faults.pl', "$stage/script/coverage-perl.pl",
        'unlink', 1 );
    ok( $status != 0, 'undeletable stale evidence is rejected' );
    like( $output, qr/Cannot remove stale report/, 'stale evidence diagnostic' );
}
my $missing_shape = decode_json( Gnu::Build::slurp("$stage/config/coverage-baseline.json") );
delete $missing_shape->{expected_total};
open my $missing_file, '>:raw', "$stage/config/coverage-baseline.json" or die $!;
print {$missing_file} encode_json($missing_shape) or die $!;
close $missing_file                               or die $!;
run_case( 'complete', 0, qr/Missing expected coverage totals/, '--require-full' );
baseline();
my $tools = decode_json( Gnu::Build::slurp('config/author-tools.json') );
$tools->{coverage}{'Devel::Cover'} = '0.01';
open my $tools_file, '>:raw', "$stage/config/author-tools.json" or die $!;
print {$tools_file} encode_json($tools) or die $!;
close $tools_file                       or die $!;
run_case( 'complete', 0, qr/Wrong Devel::Cover version/ );
done_testing;
