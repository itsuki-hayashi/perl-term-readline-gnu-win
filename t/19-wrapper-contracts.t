# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use Symbol     qw(qualify_to_ref);
use AutoLoader ();
BEGIN { $ENV{PERL_RL} = 'Gnu'; $ENV{TERM} = 'win32'; }    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Select backend before frontend import; fixture owns its process environment.
use Term::ReadLine;
my ($input)  = tempfile();
my ($output) = tempfile();
my $term     = Term::ReadLine->new( 'wrapper contracts', $input, $output );
my $map      = $term->get_keymap();
my $function = $term->named_function('self-insert');

# Replace only the native operation under test: wrappers still perform real
# name conversion. Assertions protect argument order and default omission.
sub wrapper_case ( $name, $native, $arguments, $expected ) {
    my $full = "Term::ReadLine::Gnu::XS::$name";
    AutoLoader::autoload_sub($full) unless defined(&$full);
    my $wrapper = *{ qualify_to_ref($full) }{CODE};
    my @received;
    my $slot = qualify_to_ref("Term::ReadLine::Gnu::XS::$native");
    local *{$slot} = sub { @received = @_; return 123; };
    my $result = $wrapper->( $arguments->@* );
    is( $result, 123, "$name forwards native return" );
    is_deeply( \@received, $expected, "$name preserves arguments and omissions" );
}
for my $case (
    [ 'rl_bind_key', '_rl_bind_key', [ 65, 'self-insert' ], [ 65, $function ] ],
    [ 'rl_bind_key', '_rl_bind_key', [ 65, $function, $map ], [ 65, $function, $map ] ],
    [
        'rl_bind_key_if_unbound', '_rl_bind_key_if_unbound',
        [ 65, 'self-insert' ],    [ 65, $function ]
    ],
    [
        'rl_bind_key_if_unbound', '_rl_bind_key_if_unbound',
        [ 65, $function, $map ],  [ 65, $function, $map ]
    ],
    [ 'unbind_key',      '_rl_unbind_key',      [65],                    [65] ],
    [ 'unbind_key',      '_rl_unbind_key',      [ 65, $map ],            [ 65, $map ] ],
    [ 'unbind_function', '_rl_unbind_function', ['self-insert'],         ['self-insert'] ],
    [ 'unbind_function', '_rl_unbind_function', [ $function, $map ],     [ $function, $map ] ],
    [ 'unbind_command',  '_rl_unbind_command',  ['self-insert'],         ['self-insert'] ],
    [ 'unbind_command',  '_rl_unbind_command',  [ 'self-insert', $map ], [ 'self-insert', $map ] ],
    [ 'rl_bind_keyseq',  '_rl_bind_keyseq',     [ 'a', 'self-insert' ],  [ 'a', $function ] ],
    [ 'rl_bind_keyseq',  '_rl_bind_keyseq', [ 'a', $function, $map ],    [ 'a', $function, $map ] ],
    [ 'rl_set_key',      '_rl_set_key',     [ 'a', 'self-insert' ],      [ 'a', $function ] ],
    [ 'rl_set_key',      '_rl_set_key',     [ 'a', $function, $map ],    [ 'a', $function, $map ] ],
    [
        'rl_bind_keyseq_if_unbound', '_rl_bind_keyseq_if_unbound',
        [ 'a', 'self-insert' ],      [ 'a', $function ]
    ],
    [
        'rl_bind_keyseq_if_unbound', '_rl_bind_keyseq_if_unbound',
        [ 'a', $function, $map ],    [ 'a', $function, $map ]
    ],
    [ 'rl_macro_bind',    '_rl_macro_bind',    [ 'a', 'macro' ],       [ 'a', 'macro' ] ],
    [ 'rl_macro_bind',    '_rl_macro_bind',    [ 'a', 'macro', $map ], [ 'a', 'macro', $map ] ],
    [ 'rl_call_function', '_rl_call_function', ['self-insert'],        [$function] ],
    [ 'rl_call_function', '_rl_call_function', [ $function, 2 ],       [ $function, 2 ] ],
    [ 'rl_call_function', '_rl_call_function', [ $function, 2, 65 ],   [ $function, 2, 65 ] ],
    [ 'rl_trim_arg_from_keyseq', '_rl_trim_arg_from_keyseq', ['a'],            ['a'] ],
    [ 'rl_trim_arg_from_keyseq', '_rl_trim_arg_from_keyseq', [ 'a', $map ],    [ 'a', $map ] ],
    [ 'rl_print_keybinding',     '_rl_print_keybinding',     ['a'],            ['a'] ],
    [ 'rl_print_keybinding',     '_rl_print_keybinding',     [ 'a', $map ],    [ 'a', $map ] ],
    [ 'rl_print_keybinding',     '_rl_print_keybinding',     [ 'a', $map, 1 ], [ 'a', $map, 1 ] ],
    [ 'rl_completion_mode',      '_rl_completion_mode',      ['self-insert'],  [$function] ],
    )
{
    wrapper_case( $case->@* );
}
for my $name (
    qw(rl_bind_key_if_unbound unbind_function unbind_command rl_bind_keyseq rl_set_key rl_bind_keyseq_if_unbound rl_add_funmap_entry rl_tty_set_default_bindings rl_tty_unset_default_bindings rl_completion_mode)
    )
{
    my $full = "Term::ReadLine::Gnu::XS::$name";
    AutoLoader::autoload_sub($full) unless defined(&$full);
    my $wrapper = *{ qualify_to_ref($full) }{CODE};
    local *Term::ReadLine::Gnu::XS::Attribs = { library_version => '1.0' };
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my @result = $wrapper->( 'self-insert', $function );
    is_deeply( \@result, [], "$name unsupported version returns empty list" );
    like( join( '', @warnings ), qr/not supported.*Ignored/, "$name unsupported version warns" );
}

# Constants are callable public APIs, including legacy compatibility values.
is( Term::ReadLine::Gnu::READERR(), -2, 'read error constant' );
is( Term::ReadLine::Gnu::RL_STATE_REDISPLAYING(),
    0x1000000, 'redisplaying state for bundled Readline' );
is( Term::ReadLine::Gnu::RL_STATE_DONE(), 0x2000000, 'done state for bundled Readline' );
for my $name (
    qw(NO_MATCH SINGLE_MATCH MULT_MATCH UNDO_DELETE UNDO_INSERT UNDO_BEGIN UNDO_END RL_STATE_NONE RL_STATE_INITIALIZING RL_STATE_INITIALIZED RL_STATE_TERMPREPPED RL_STATE_READCMD RL_STATE_METANEXT RL_STATE_DISPATCHING RL_STATE_MOREINPUT RL_STATE_ISEARCH RL_STATE_NSEARCH RL_STATE_SEARCH RL_STATE_NUMERICARG RL_STATE_MACROINPUT RL_STATE_MACRODEF RL_STATE_OVERWRITE RL_STATE_COMPLETING RL_STATE_SIGHANDLER RL_STATE_UNDOING RL_STATE_INPUTPENDING RL_STATE_TTYCSAVED RL_STATE_CALLBACK RL_STATE_VIMOTION RL_STATE_MULTIKEY RL_STATE_VICMDONCE RL_STATE_CHARSEARCH RL_STATE_TIMEOUT RL_STATE_EOF RL_STATE_READSTR)
    )
{
    my $constant = *{ qualify_to_ref("Term::ReadLine::Gnu::$name") }{CODE};
    like( $constant->(), qr/\A[0-9]+\z/, "$name is a nonnegative integer constant" );
}
wrapper_case( 'rl_free_keymap', '_rl_free_keymap', [$map], [$map] );
wrapper_case(
    'rl_set_keymap_name',     '_rl_set_keymap_name',
    [ 'contract-map', $map ], [ 'contract-map', $map ]
);
wrapper_case(
    'rl_add_funmap_entry', '_rl_add_funmap_entry',
    [ 'contract-function', 'self-insert' ],
    [ 'contract-function', $function ]
);
wrapper_case(
    'rl_generic_bind', '_rl_generic_bind_macro',
    [ Term::ReadLine::Gnu::ISMACR(), 'x', 'macro', $map ],
    [ 'x', 'macro', $map ]
);
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_; };
    Term::ReadLine::Gnu::XS::rl_generic_bind( 999, 'x', 'ignored' );
    like( join( '', @warnings ), qr/invalid.*type/, 'invalid generic binding type warns' );
}
{
    local *Term::ReadLine::Gnu::XS::Attribs = { readline_state => 0 };
    is( Term::ReadLine::Gnu::XS::SETSTATE(8),   8, 'SETSTATE returns updated mask' );
    is( Term::ReadLine::Gnu::XS::ISSTATE(8),    8, 'ISSTATE returns matching bits' );
    is( Term::ReadLine::Gnu::XS::UNSETSTATE(8), 0, 'UNSETSTATE clears requested bits' );
    is( Term::ReadLine::Gnu::XS::ISSTATE(8),    0, 'cleared state is absent' );
}
{
    my $slot = qualify_to_ref('Term::ReadLine::Gnu::XS::rl_completion_matches');
    local *{$slot} = sub { return ('only'); };
    is_deeply( [ Term::ReadLine::Gnu::XS::rl_filename_list('o') ],
        ['only'], 'single filename uses LCD' );
}
is( Term::ReadLine::Gnu::XS::hist_arg_extract( 'one two three', '$' ),
    'three', 'dollar first selector extracts last history argument' );
{
    my $slot = qualify_to_ref('Term::ReadLine::Gnu::XS::rl_term_set');
    local *{$slot} = \'legacy scalar';
    is(
        Term::ReadLine::Gnu::XS::ornaments(),
        'legacy scalar',
        'getter retains legacy scalar source'
    );
    local $ENV{TERM} = 'kterm';
    is( Term::ReadLine::Gnu::XS::ornaments(1),
        'us,me,md,me', 'terminal without ue uses reset capability' );
}

# Upstream's two legacy tty-default adapters call misspelled native names.
# Preserve their existing failure rather than silently changing public behavior
# during coverage work. Real console initialization uses the native backend.
for my $name ( 'rl_tty_set_default_bindings', 'rl_tty_unset_default_bindings' ) {
    my $wrapper = *{ qualify_to_ref("Term::ReadLine::Gnu::XS::$name") }{CODE};
    for my $arguments ( [], [ $map, $map ] ) {
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_; };
        my $ok = eval { $wrapper->( $arguments->@* ); 1 };
        ok( !$ok, "$name legacy failure is retained" );
        like(
            $@,
            qr/Can't locate auto\/Term\/ReadLine\/Gnu\/XS\//,
            "$name loader diagnostic retained"
        );
        is_deeply( \@warnings, [], "$name emits no additional warnings" );
    }
}
done_testing;
