# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
BEGIN { delete $ENV{PERL_RL}; $ENV{TERM} = 'win32' }    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional.
use Term::ReadLine;
is( Term::ReadLine->ReadLine, 'Term::ReadLine::Gnu', 'automatic GNU backend discovery' );
like( $INC{'Term/ReadLine/Gnu.pm'}, qr{blib[/\\]lib}, 'loaded the distribution under test' );
my ($in)  = tempfile();
my ($out) = tempfile();
my $term  = Term::ReadLine->new( 'CPAN completion regression', $in, $out );
require CPAN;
require CPAN::Complete;
{
    no warnings qw(redefine once);    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- Only the named category is suppressed for intentional symbol replacement.
    local $CPAN::Config_loaded     = 1;
    local $CPAN::Suppress_readline = 0;
    local $CPAN::Config            = {};
    local $CPAN::term              = $term;

    # Stop after the real shell initializes completion, before locks or I/O.
    local *CPAN::checklock = sub { die "completion initialized\n" };
    eval { CPAN::shell() };           ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval) -- The test or callback checks the resulting exception through $@.
    is( $@, "completion initialized\n", 'actual CPAN shell completed readline initialization' );
    my $complete = $term->Attribs->{attempted_completion_function};
    is( ref($complete), 'CODE', 'CPAN installed its GNU completion callback' );
    my @matches = $complete->( 'ins', 'ins', 0, 3 );
    ok( grep( $_ eq 'install',        @matches ), 'CPAN command completion offers install' );
    ok( grep( $_ eq 'install_tested', @matches ), 'CPAN command completion offers install_tested' );
}
for my $selector ( 'Gnu', 'Stub' ) {
    local $ENV{PERL_RL} = $selector;
    open my $child, '-|', $^X, '-Mblib', '-MTerm::ReadLine', '-e', 'print Term::ReadLine->ReadLine'
        or die $!;
    local $/;
    my $backend = <$child>;
    close $child or die "Cannot close file: $!";
    is( $?,       0,                           "$selector selection subprocess succeeded" );
    is( $backend, "Term::ReadLine::$selector", "explicit $selector selection respected" );
}
done_testing;
