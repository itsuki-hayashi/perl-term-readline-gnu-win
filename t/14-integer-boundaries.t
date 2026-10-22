# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
BEGIN { $ENV{PERL_RL} = 'Gnu' }    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional.
use Term::ReadLine;
my ($input)  = tempfile();
my ($output) = tempfile();
my $term     = Term::ReadLine->new( 'integer boundaries', $input, $output );

for my $value ( 2147483648, -2147483649, 9223372036854775807, 18446744073709551615,
    '18446744073709551615' )
{
    my $range_ok = eval { $term->stifle_history($value); 1 };
    ok( !$range_ok, "reject out-of-range history limit $value" );
    like( $@, qr/Readline integer argument/, 'reports range rather than truncating' );
}
{

    package BoundaryValue;
    sub TIESCALAR { bless {}, shift }
    sub FETCH     { 18446744073709551615 }
}
tie my $magic, 'BoundaryValue';    ## no critic (Miscellanea::ProhibitTies) -- Tied scalars are the public Readline attribute interface.
my $range_ok = eval { $term->stifle_history($magic); 1 };
ok( !$range_ok, 'magical unsigned argument cannot bypass range check' );
like( $@, qr/Readline integer argument/, 'magical argument reports range error' );
$term->stifle_history(2147483647);
is( $term->unstifle_history, 2147483647, 'INT_MAX survives Perl/Readline round trip' );
$term->stifle_history(3);
$term->add_history('one');
is( $term->Attribs->{history_length}, 1, 'history still works after range errors' );

for my $value ( 2147483648, -2147483649 ) {
    my $delete_ok = eval { $term->delete_text( $value, 0 ); 1 };
    ok( !$delete_ok, 'typemap rejects out-of-range int arguments' );
    like( $@, qr/Readline integer argument/, 'typemap reports range error' );
}
done_testing;
