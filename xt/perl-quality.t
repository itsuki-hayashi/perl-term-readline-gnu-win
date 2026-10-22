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
done_testing;
