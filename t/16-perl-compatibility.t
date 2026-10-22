# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp   qw(tempfile);
use JSON::PP     qw(decode_json);
use Scalar::Util qw(refaddr);
BEGIN { $ENV{PERL_RL} = 'Gnu'; $ENV{TERM} = 'win32'; }    ## no critic (Variables::RequireLocalizedPunctuationVars, Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional.
use Term::ReadLine;
use AutoLoader ();
is_deeply(
    \@Term::ReadLine::Gnu::ISA,
    [qw(Term::ReadLine::Gnu::AU Term::ReadLine::Stub Exporter DynaLoader)],
    'backend parent lookup order is unchanged'
);

open my $fixture, '<:raw', 't/data/perl-api.json' or die $!;
my $contracts = do { local $/; decode_json(<$fixture>) };
close $fixture or die $!;
for my $name ( sort keys $contracts->%* ) {
    AutoLoader::autoload_sub($name) if $name =~ /::XS::/;
    ok( defined(&$name), "$name remains callable" );
    is( prototype($name), $contracts->{$name}, "$name preserves its prototype" );
}

my ($input)  = tempfile();
my ($output) = tempfile();
my $term     = Term::ReadLine->new( 'Perl compatibility', $input, $output );
is( refaddr($term), refaddr( $term->Attribs ),
    'singleton object still exposes the attribute hash' );
is( $term->ReadLine('ignored'),
    'Term::ReadLine::Gnu', 'identity method still accepts extra arguments' );
is_deeply( [ $term->ReadLine ], ['Term::ReadLine::Gnu'], 'identity method preserves list context' );
is(
    refaddr( $term->Features ),
    refaddr( $term->Features('ignored') ),
    'feature hash identity is stable'
);
ok( tied( $term->Attribs->{line_buffer} ), 'line_buffer remains a tied scalar' );
$term->Attribs->{line_buffer} = "abc";
is( $term->Attribs->{line_buffer}, 'abc', 'tied STORE/FETCH still reaches Readline' );
$term->SetHistory(qw(first second));
is_deeply( [ $term->GetHistory ], [qw(first second)], 'history preserves list results' );
is( scalar( $term->GetHistory ), 2, 'history preserves scalar result' );
{

    package CompatibilitySubclass;
    use parent -norequire, 'Term::ReadLine::Gnu';
}
bless $term, 'CompatibilitySubclass';
isa_ok( $term, 'Term::ReadLine::Gnu', 'existing hash objects remain subclassable' );

my @warnings;
{
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    # An XS callback fixture verifies argument aliasing and caller context
    # across the inherited lazy method adapter without touching native memory.
    no warnings 'once';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- Only the named category is suppressed for intentional symbol replacement.
    local *Term::ReadLine::Gnu::XS::rl_compatibility_probe = sub {
        $_[0] = 'changed';
        return !defined(wantarray) ? () : wantarray ? ( 'list', @_ ) : 'scalar';
    };
    my $argument = 'original';
    is_deeply(
        [ $term->compatibility_probe($argument) ],
        [ 'list', 'changed' ],
        'lazy wrapper keeps list context'
    );
    is( $argument, 'changed', 'lazy wrapper preserves argument aliases' );
    is( $term->compatibility_probe($argument), 'scalar', 'cached wrapper keeps scalar context' );
    $term->compatibility_probe($argument);
    pass('cached wrapper accepts void context');
}
is_deeply( \@warnings, [], 'lazy and cached method dispatch emit no unexpected warnings' );
my $ok = eval { $term->method_that_does_not_exist; 1 };
ok( !$ok, 'unknown methods still fail' );
like( $@, qr/Cannot do/, 'unknown method retains its diagnostic' );
done_testing;
