# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Symbol     qw(qualify_to_ref);
BEGIN { $ENV{PERL_RL} = 'Gnu'; $ENV{TERM} = 'win32'; }    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Select backend before import in this isolated test process.
use Term::ReadLine;
{

    package ConstructorCoverage;
    use parent -norequire, 'Term::ReadLine::Gnu';
    our ( $input, $output );
    sub findConsole { return ( $input, $output ); }
    sub newTTY      { my ( $self, @streams ) = @_; $self->{test_streams} = \@streams; }
    sub initialize  { $_[0]->{readline_version} = 0x800; }
    sub ornaments   { $_[0]->{test_ornaments}   = $_[1]; }
}
my $work = tempdir( CLEANUP => 1 );
$ConstructorCoverage::input  = "$work/input";
$ConstructorCoverage::output = "$work/output";
open my $source, '>:raw', $ConstructorCoverage::input or die $!;
close $source or die $!;
for my $utf8 ( 0, 1 ) {
    local *Term::ReadLine::Gnu::Attribs              = { utf8_mode => $utf8 };
    local $Term::ReadLine::Gnu::has_been_initialized = 0;
    local $Term::ReadLine::Gnu::readline_version;
    local $ENV{PERL_RL} = $utf8 ? 'Gnu o=0' : 'Gnu';
    my $slot = qualify_to_ref('Term::ReadLine::Gnu::XS::rl_add_defun');
    my @defun;
    local *{$slot} = sub { @defun = @_; return 0; };
    my $term = ConstructorCoverage->new('constructor coverage');
    isa_ok( $term, 'ConstructorCoverage' );
    is( $term->{utf8_mode} ? 1 : 0,       $utf8, 'constructor preserves explicit UTF-8 selection' );
    is( scalar $term->{test_streams}->@*, 2,     'console streams forwarded' );
    is( $term->{test_ornaments},          $utf8 ? undef : 1, 'ornament selector honored' );
    is( $defun[0], 'operate-and-get-next', 'legacy Readline installs compatibility callback' );
    my $again = eval { ConstructorCoverage->new('again'); 1 };
    ok( !$again, 'second constructor rejected' );
    like( $@, qr/Only one/, 'singleton diagnostic' );
    close $_ or die $! for $term->{test_streams}->@*;
}
for my $stream ( 'input', 'output' ) {
    local *Term::ReadLine::Gnu::Attribs              = {};
    local $Term::ReadLine::Gnu::has_been_initialized = 0;
    local $ConstructorCoverage::input = $stream eq 'input' ? "$work/missing/input" : "$work/input";
    local $ConstructorCoverage::output =
        $stream eq 'output' ? "$work/missing/output" : "$work/output";
    my $ok = eval { ConstructorCoverage->new('failure'); 1 };
    ok( !$ok, "bad console $stream rejected" );
    like( $@, qr/Cannot open.*for (?:read|write)/, "bad console $stream diagnostic" );
}
for my $arguments ( [], [ 'name', 'extra' ], [ 'name', 1, 2, 3 ] ) {
    my $ok = eval { ConstructorCoverage->new( $arguments->@* ); 1 };
    ok( !$ok, 'constructor rejects wrong arity' );
    like( $@, qr/Wrong number of arguments/, 'arity diagnostic' );
}
for my $case (
    [ 0x500, 0x80000,   0x800000 ],
    [ 0x600, 0x800000,  0x800000 ],
    [ 0x650, 0x1000000, 0x800000 ],
    [ 0x800, 0x2000000, 0x1000000 ]
    )
{
    local $Term::ReadLine::Gnu::readline_version = $case->[0];
    is( Term::ReadLine::Gnu::RL_STATE_DONE(), $case->[1], 'legacy DONE constant value' );
    is( Term::ReadLine::Gnu::RL_STATE_REDISPLAYING(),
        $case->[2], 'legacy redisplay constant value' );
}
{
    local *Term::ReadLine::Gnu::Attribs              = {};
    local $Term::ReadLine::Gnu::has_been_initialized = 0;
    local $Term::ReadLine::Gnu::readline_version;
    local $^O = 'linux';
    my $slot = qualify_to_ref('Term::ReadLine::Gnu::XS::rl_add_defun');
    local *{$slot} = sub { return 0; };
    my $term = ConstructorCoverage->new('legacy branch');
    ok( !exists $term->{terminal_name},
        'legacy non-Windows branch omits terminal-name assignment' );
    close $_ or die $! for $term->{test_streams}->@*;
}
done_testing;
