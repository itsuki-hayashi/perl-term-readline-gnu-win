# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use Symbol     qw(qualify_to_ref);
BEGIN { $ENV{PERL_RL} = 'Gnu'; $ENV{TERM} = 'win32'; }    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Select backend before frontend import in an isolated process.
use Term::ReadLine;
my ($input)  = tempfile();
my ($output) = tempfile();
my $term     = Term::ReadLine->new( 'tied contracts', $input, $output );
my $class    = 'Term::ReadLine::Gnu::Var';

for my $method ( 'FETCH', 'STORE' ) {
    my $ok = eval { $class->$method('ignored'); 1 };
    ok( !$ok, "$method rejects a plain class string" );
    like( $@, qr/wrong type/, "$method type diagnostic" );
    my $unknown = $class->TIESCALAR('coverage_unknown');
    $ok = eval { $unknown->$method('ignored'); 1 };
    ok( !$ok, "$method rejects an unknown variable" );
    like( $@, qr/Unknown variable name/, "$method unknown-variable diagnostic" );
}
my $last_function = $class->TIESCALAR('rl_last_func');
my $value         = $last_function->FETCH();
ok( !defined($value) || ref($value), 'last-function fetch is an optional function pointer' );
for my $name ( 'rl_binding_keymap', 'rl_last_func' ) {
    my $attribute = $class->TIESCALAR($name);
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_; };
    is( $attribute->STORE(undef), undef, "$name cannot be stored" );
    like( join( '', @warnings ), qr/read only variable/, "$name warns on attempted store" );
}
{
    my $slot = qualify_to_ref('Term::ReadLine::Gnu::Var::_rl_vars');
    local *{$slot} = { coverage_illegal => [ 'INVALID', 0 ] };
    my $attribute = $class->TIESCALAR('coverage_illegal');
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_; };
    is( $attribute->FETCH(),          undef, 'illegal type fetch returns undef' );
    is( $attribute->STORE('ignored'), undef, 'illegal type store returns undef' );
    is( scalar @warnings,             2,     'illegal type operations both warn' );
    like( join( '', @warnings ), qr/Illegal type/, 'illegal type diagnostic' );
}
my $a = $term->Attribs;
{
    local $a->{completion_append_character} = ';';
    is( $a->{completion_append_character}, ';', 'character store and fetch roundtrip' );
}
{
    local $a->{readline_name} = 'coverage-name';
    is( $a->{readline_name}, 'coverage-name', 'string store and fetch roundtrip' );
}
{
    local $] = 5.008;
    my $stream = $class->TIESCALAR('rl_instream');
    is( $stream->STORE($input), $input, 'legacy IO branch preserves handle identity' );
}
done_testing;
