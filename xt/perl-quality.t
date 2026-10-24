# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use lib 'inc';
use Gnu::Quality ();
use Gnu::Build   ();
use File::Temp   qw(tempdir);
use Cwd          qw(abs_path);

plan skip_all => 'Set AUTHOR_TESTING=1 to test author-check tooling'
    unless $ENV{AUTHOR_TESTING};
require Perl::Critic;
my $critic  = Perl::Critic->new( -profile => '.perlcriticrc', '-profile-strictness' => 'fatal' );
my @sources = Gnu::Quality::sources( abs_path('.') );
ok( grep( { $_ eq 'script/perlsh' } @sources ), 'extensionless REPL is checked' );
ok( !grep( { m{^(?:vendor|examples|build|blib)/} } @sources ),
    'excluded trees stay outside inventory' );
my $profile = abs_path('.perltidyrc');
my $valid   = "use v5.44;\nuse strict;\nuse warnings;\nprint qq(hello\\n);\n";
my @good    = Gnu::Quality::inspect( 'fixture.pl', $valid, $critic, $profile );
is_deeply( \@good, [], 'valid fixture passes' );
my @commented = Gnu::Quality::inspect(
    'fixture.pl',
    $valid
        . "\n# ordinary comment\n## no critic (Subroutines::ProhibitReturnSort) -- Fixture exercises accepted annotation syntax.\n",
    $critic,
    $profile
);
ok(
    !grep( { /blanket Critic suppression/ } @commented ),
    'ordinary comments and named annotations accepted'
);
my @untidy = Gnu::Quality::inspect( 'fixture.pl', "use v5.44; print(  1 );\n", $critic, $profile );
ok( grep( { /formatting/ } @untidy ), 'formatting drift fails' );
my @lint = Gnu::Quality::inspect( 'fixture.pl', "$valid\nmy \$unused;\n", $critic, $profile );
ok( grep( { /ProhibitUnusedVariables/ } @lint ), 'lint violation fails' );
my @suppression =
    Gnu::Quality::inspect( 'fixture.pl', $valid . "\n" . '## no critic' . "\n", $critic, $profile );
ok( grep( { /blanket Critic suppression/ } @suppression ), 'blanket suppressions fail' );
my @pod = Gnu::Quality::inspect( 'fixture.pl', "$valid\n=head1 NAME\n\nB<unclosed\n\n=cut\n",
    $critic, $profile );
ok( grep( { /POD/ } @pod ), 'malformed POD fails' );
my $autoload = Gnu::Quality::analysis_source( 'lib/Term/ReadLine/Gnu/XS.pm',
    "use strict;\n__END__\nmy \$unused;\n" );
like( $autoload, qr/my \$unused/, 'AutoLoader body is included' );
ok( !( $autoload =~ /^__END__$/m ), 'AutoLoader body is executable to the analyzer' );
my $dir = tempdir( CLEANUP => 1 );
open my $bad, '>:raw', "$dir/bad.pl" or die $!;
print {$bad} "use strict;\nmy = ;\n" or die $!;
close $bad                           or die $!;
my ( $status, $diagnostic ) = Gnu::Quality::capture( $^X, '-c', "$dir/bad.pl" );
ok( $status != 0, 'syntax failure propagates from subprocess' );
like( $diagnostic, qr/syntax error/, 'syntax diagnostics are retained' );
my $minimum = { 'example.pm' => { statement => 80, branch => 50 } };
my $passing =
    { 'example.pm' => { statement => { percentage => 80 }, branch => { percentage => 50 } } };
is_deeply( [ Gnu::Quality::coverage_errors( $minimum, $passing ) ],
    [], 'coverage at the baseline passes' );
$passing->{'example.pm'}{branch}{percentage} = 49;
like( join( '', Gnu::Quality::coverage_errors( $minimum, $passing ) ),
    qr/below 50/, 'coverage regression fails' );
like( join( '', Gnu::Quality::coverage_errors( $minimum, {} ) ),
    qr/Missing/, 'missing coverage fails' );
my @targets = Gnu::Quality::coverage_sources( abs_path('.') );
ok( grep( { $_ eq 'script/perlsh' } @targets ),        'REPL has a coverage target' );
ok( grep( { $_ eq 'Makefile.PL' } @targets ),          'configuration has a coverage target' );
ok( grep( { $_ eq 'inc/Gnu/Toolchain.pm' } @targets ), 'toolchain has a coverage target' );
ok( !grep( { m{^(?:t|xt)/} } @targets ),               'test code is outside denominator' );
is( Gnu::Quality::coverage_source_name( abs_path('.'), abs_path('script/perlsh'), \@targets ),
    'script/perlsh', 'absolute source name resolves against inventory' );
is( Gnu::Quality::coverage_source_name( abs_path('.'), "$dir/missing.pl", \@targets ),
    undef, 'unknown source is not credited' );
mkdir("$dir/script") or die $!;
my $staged = "$dir/script/perlsh";
open my $copy, '>:raw', $staged or die $!;
print {$copy} Gnu::Build::slurp('script/perlsh') or die $!;
close $copy                                      or die $!;
is( Gnu::Quality::coverage_source_name( abs_path('.'), $staged, \@targets ),
    'script/perlsh', 'identical staged script resolves' );
is( Gnu::Quality::coverage_source_name( "$dir/missing", $staged, \@targets ),
    undef, 'absent original source cannot be credited' );
open $copy, '>>:raw', $staged or die $!;
print {$copy} "\n# modified copy\n" or die $!;
close $copy                         or die $!;
is( Gnu::Quality::coverage_source_name( abs_path('.'), $staged, \@targets ),
    undef, 'modified staged script cannot be credited' );
my $complete = {
    'fixture.pl' => {
        statement => { covered => 3, total => 3 },
        branch    => { covered => 0, total => 0 },
    }
};
is_deeply( [ Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete ) ],
    [], 'full statements and explicit branch-free measurement pass' );
like( join( '', Gnu::Quality::full_coverage_errors( [], $complete ) ),
    qr/Empty/, 'empty target inventory fails' );
like( join( '', Gnu::Quality::full_coverage_errors( ['missing.pl'], $complete ) ),
    qr/Missing/, 'unloaded target fails' );
$complete->{'fixture.pl'}{statement} = { covered => 999999, total => 1000000, percentage => 100 };
like( join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete ) ),
    qr/below 100%/, 'rounded percentage cannot hide a missed statement' );

for my $invalid (
    {},
    { covered => -1, total => 2 },
    { covered =>  3, total => 2 },
    { covered =>  0, total => 0 },
    { covered =>  1, total => 1, error       => 1 },
    { covered =>  1, total => 1, uncoverable => 1 },
    )
{
    $complete->{'fixture.pl'}{statement} = $invalid;
    like( join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete ) ),
        qr/Invalid/, 'invalid or excluded measurement fails' );
}
my $totals = { 'fixture.pl' => { statement => 3, branch => 0 } };
$complete->{'fixture.pl'}{statement} = { covered => 3, total => 3 };
is_deeply( [ Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete, $totals ) ],
    [], 'exact expected totals accept a branch-free file' );
$totals->{'fixture.pl'}{statement} = 4;
like(
    join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete, $totals ) ),
    qr/Unexpected statement total/,
    'lost instrumentation sites are rejected'
);
$totals->{'fixture.pl'}{statement} = -1;
like(
    join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete, $totals ) ),
    qr/invalid expected/,
    'invalid expected total rejected'
);
$totals->{'stale.pl'} = {};
like(
    join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], {}, $totals ) ),
    qr/Unexpected coverage target/,
    'stale target is rejected'
);
like(
    join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete, [] ) ),
    qr/Invalid expected coverage totals/,
    'malformed totals table rejected'
);
like(
    join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete, {} ) ),
    qr/invalid expected totals/,
    'missing expected row rejected'
);
my $missing_total = { 'fixture.pl' => { statement => 3 } };
like(
    join( '', Gnu::Quality::full_coverage_errors( ['fixture.pl'], $complete, $missing_total ) ),
    qr/invalid expected branch/,
    'missing criterion total rejected'
);
done_testing;
