#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use FindBin      ();
use Getopt::Long qw(GetOptions);
use lib "$FindBin::Bin/../build/author/lib/perl5";
use lib "$FindBin::Bin/../inc";
use Cwd              qw(abs_path);
use File::Path       qw(make_path);
use File::Temp       qw(tempdir);
use JSON::PP         qw(decode_json);
use Devel::Cover::DB ();
use Gnu::Build       ();
use Gnu::Quality     ();

# Named phases keep subprocess ownership, calibration and report validation
# independently testable, including failures that unwind the script entrypoint.
sub main {
    my ( $require_full, $integration );
    GetOptions( 'require-full' => \$require_full, 'integration' => \$integration )
        or die "Usage: perl script/coverage-perl.pl [--require-full] [--integration]\n";
    die "Unexpected arguments: @ARGV\n" if @ARGV;
    $integration = 1                    if $require_full;
    chdir "$FindBin::Bin/.." or die "Cannot enter checkout: $!";

    # A warning while reading/merging coverage can mean an incomplete report.
    local $SIG{__WARN__} = sub { die "Coverage tool warning: @_"; };

    # AutoLoader's generated #line directives otherwise retain blib-relative
    # filenames. They must remain resolvable when instrumented console children
    # run from build/native or when Devel::Cover changes directory to report.
    require AutoSplit;
    AutoSplit::autosplit(
        abs_path('blib/lib/Term/ReadLine/Gnu/XS.pm'),
        abs_path('blib/lib/auto'),
        1, 1, 0
    );
    my $tools = decode_json( Gnu::Build::slurp('config/author-tools.json') );
    die "Wrong Devel::Cover version\n"
        unless Devel::Cover::DB->VERSION eq $tools->{coverage}{'Devel::Cover'};
    make_path('build/quality');
    for my $report (qw(coverage.json coverage-target.json calibration.json)) {
        my $path = "build/quality/$report";
        unlink($path) or die "Cannot remove stale report $path: $!" if -e $path;
    }

    # Fresh databases prevent stale runs from inflating coverage.
    my $directory = tempdir( 'coverage-XXXX', DIR => 'build/quality', CLEANUP => 0 );
    my $base      = abs_path($directory);
    $base =~ tr{\\}{/};
    my $database = "$base/tests-db";
    local $ENV{PERL5LIB} = join ';', abs_path('build/author/lib/perl5'), ( $ENV{PERL5LIB} // () );
    calibrate( $base, $directory );
    my @targets = Gnu::Quality::coverage_sources( abs_path('.') );
    my ( $status, $log )       = run_tests( $base, $database, $integration, \@targets );
    my ( $actual, $uncovered ) = collect( $database, \@targets );
    finish( \@targets, $actual, $uncovered, $status, $log, $require_full );
}

sub calibrate ( $base, $directory ) {
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
sub guard ($value) {
    die "expected\n" if $value;
    return 1;
}
sub callback ($callback, $value) { return $callback->($value); }
for my $value (0, 1) {
    eval { guard($value) };
    callback(\&choose, $value);
    my $short = $value && choose($value);
    my $fallback = $value || choose($value);
}
print choose(1), choose(0), "\n";
PERL
    close $probe or die $!;
    my ( $probe_status, $probe_output ) =
        Gnu::Quality::capture( $^X,
        "-MDevel::Cover=-db,$base/calibration-db,-coverage,statement,branch,condition,-silent,1",
        $calibration, );
    die "Coverage calibration failed ($probe_status): $probe_output\n"
        unless !$probe_status && $probe_output =~ /\A10\r?\n\z/;
    my $probe_db = Devel::Cover::DB->new( db => "$base/calibration-db" );
    $probe_db->merge_runs;
    $probe_db->calculate_summary( statement => 1, branch => 1 );
    write_json( 'build/quality/calibration.json', $probe_db->summary('Total') );

    for my $criterion (qw(statement branch)) {
        my $value = $probe_db->summary( 'Total', $criterion );
        die "Unsupported $criterion instrumentation: calibration did not cover both paths\n"
            unless $value && $value->{total} && $value->{percentage} == 100;
    }

}

sub run_tests ( $base, $database, $integration, $targets ) {

    # PERL5OPT also instruments Perl children started by integration tests.
    # Keep blib in the harness only: injecting it into installation smoke tests
    # would conceal accidental loading from the checkout instead of the install.
    make_path("$base/filename-root");
    my @targets   = $targets->@*;
    my $selection = '(?:\\A|/)(?:' . join( '|', map { quotemeta } @targets ) . ')\\z';
    local $ENV{HARNESS_PERL_SWITCHES} = '-Mblib';
    local $ENV{PERL5OPT}              = '-MDevel::Cover';
    local $ENV{DEVEL_COVER_OPTIONS} =

        # A shared digest cache must never canonicalize a source to a path relative
        # to one child's cwd: console children run from build/native. An unrelated
        # naming root keeps all recorded filenames absolute across processes.
        qq(-db,$database,-dir,$base/filename-root,-coverage,statement,branch,condition,-silent,1,-ignore,.,-select,$selection);
    local $ENV{AUTHOR_TESTING} = 1;
    local $ENV{TERM}           = 'win32';
    my @tests =
        ( sort glob('t/*.t'), 'xt/perl-quality.t', 'xt/coverage-runner.t', 'xt/check-runner.t' );
    my ( $status, $log ) =
        Gnu::Quality::capture( $^X, '-MTest::Harness', '-e', 'runtests(@ARGV)', @tests, );
    my @commands = ( [ $^X, 'script/check-perl.pl' ] );
    if ( $integration && !$status ) {
        require Gnu::Toolchain;
        Gnu::Toolchain::activate();
        push @commands,
            map { [ $^X, $_ ] }
            qw(Makefile.PL inc/build-native.pl script/release.pl script/test-archive.pl);
    }
    for my $command (@commands) {
        last if $status;

        # Main-program filenames also need to survive Devel::Cover's report cwd.
        $command->[1] = abs_path( $command->[1] );
        my ( $child_status, $child_log ) = Gnu::Quality::capture( $command->@* );
        $log .= "\nCommand: " . join( ' ', $command->@* ) . "\n$child_log";
        $status = $child_status;
    }
    open my $output, '>:raw', 'build/quality/coverage-tests.log' or die $!;
    print {$output} $log or die $!;
    close $output        or die $!;
    return ( $status, $log );
}

sub collect ( $database, $targets ) {
    my $db = Devel::Cover::DB->new( db => $database );
    $db->merge_runs;
    $db->calculate_summary( statement => 1, branch => 1 );
    my %actual;
    my %uncovered;
    my $cover = $db->cover;

    for my $file ( sort keys $db->{summary}->%* ) {
        next if $file eq 'Total';
        my $name = Gnu::Quality::coverage_source_name( abs_path('.'), $file, $targets );
        next unless defined $name;
        for my $criterion (qw(statement branch)) {
            my $value = $db->summary( $file, $criterion );

            # A loaded file with no branch sites has an explicit zero denominator.
            $value //= { covered => 0, total => 0, percentage => 100 }
                if $criterion eq 'branch' && !keys %{ $cover->{$file}{branch} // {} };
            next unless $value;
            $actual{$name}{$criterion} = {
                covered     => $value->{covered},
                total       => $value->{total},
                percentage  => $value->{percentage},
                error       => $value->{error}       // 0,
                uncoverable => $value->{uncoverable} // 0,
            };
            for my $line ( sort { $a <=> $b } keys %{ $cover->{$file}{$criterion} // {} } ) {
                for my $site ( $cover->{$file}{$criterion}{$line}->@* ) {
                    my $covered =
                        $criterion eq 'statement' ? ( $site->covered ? 1 : 0 ) : $site->covered;
                    next if $covered == $site->total && !$site->error && !$site->uncoverable;
                    push $uncovered{$name}{$criterion}->@*,
                        {
                        line    => 0 + $line,
                        covered => 0 + $covered,
                        total   => 0 + $site->total,
                        ( $criterion eq 'branch' ? ( text => $site->text ) : () ),
                        };
                }
            }
        }
    }
    return ( \%actual, \%uncovered );
}

sub write_json ( $path, $value ) {
    open my $file, '>:raw', $path or die $!;
    print {$file} JSON::PP->new->canonical->pretty->encode($value) or die $!;
    close $file                                                    or die $!;
}

sub finish ( $targets, $actual, $uncovered, $status, $log, $require_full ) {
    die "No project coverage was collected\n" unless keys $actual->%*;
    write_json( 'build/quality/coverage.json', $actual );
    my $baseline = decode_json( Gnu::Build::slurp('config/coverage-baseline.json') );
    my @full_errors =
        Gnu::Quality::full_coverage_errors( $targets, $actual, $baseline->{expected_total} );
    push @full_errors, "Missing expected coverage totals\n"
        unless exists $baseline->{expected_total};
    push @full_errors, "Empty coverage baseline\n" unless keys $baseline->{minimum_percent}->%*;
    unshift @full_errors, "Instrumented tests failed ($status)\n" if $status;
    write_json(
        'build/quality/coverage-target.json',
        {
            tests_exit_status => $status,
            targets           => $targets,
            measurements      => $actual,
            uncovered         => $uncovered,
            failures          => \@full_errors,
            complete          => @full_errors ? JSON::PP::false : JSON::PP::true,
        }
    );
    die "Instrumented tests failed ($status):\n$log" if $status;
    die @full_errors                                 if $require_full && @full_errors;
    die "Empty coverage baseline\n" unless keys $baseline->{minimum_percent}->%*;
    my @errors = Gnu::Quality::coverage_errors( $baseline->{minimum_percent}, $actual );
    die @errors if @errors;
    print "Instrumented tests and per-module coverage baselines passed.\n";
}

main();
