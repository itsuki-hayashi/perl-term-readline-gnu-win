# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package PerlshTestBoot;
use v5.44;
use strict;
use warnings;
use Symbol qw(qualify_to_ref);
use POSIX  ();

# Preload the real native backend before modelling legacy Unix-only adapters.
# These are adapter simulations, never claims of native Unix or Tk support.
sub import ( $class, @ignored ) {
    my $mode = $ENV{GNU_PERLSH_TEST_MODE} // '';
    if ( $mode eq 'configure' ) {
        require ExtUtils::MakeMaker;
        model_os('linux');
        return;
    }
    local $ENV{PERL_RL} = 'Gnu';
    require Term::ReadLine;
    if ( $mode =~ /\Aunix-/ ) {
        delete $POSIX::{sigaction};
        my $signal = qualify_to_ref('POSIX::sigaction');
        *{$signal} = \&fake_sigaction;
        delete $POSIX::SigAction::{new};
        my $action = qualify_to_ref('POSIX::SigAction::new');
        *{$action} = \&fake_action;
        model_os('linux');
    }
    for my $method ( 'ReadHistory', 'WriteHistory' ) {
        next
            unless $mode eq
            ( $method eq 'ReadHistory' ? 'history-read-fail' : 'history-write-fail' );
        delete $Term::ReadLine::Gnu::{$method};
        my $slot = qualify_to_ref("Term::ReadLine::Gnu::$method");
        *{$slot} = sub { return 0; };
    }
}

sub model_os ($os) {
    $^O = $os;    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Compatibility: platform emulation must survive bootstrap import to exercise legacy guards; regressions: t/20-perlsh.t and t/26-loading-contracts.t.
}

sub fake_sigaction : prototype($$) ( $signal, $action ) {
    die 'Wrong signal callback' unless $signal == 2 && ref( $action->{handler} ) eq 'CODE';
    return ( $ENV{GNU_PERLSH_TEST_MODE} // '' ) ne 'unix-signal-fail';
}
sub fake_action ( $class, $handler ) { return bless { handler => $handler }, $class; }
sub Term::ReadLine::Gnu::findConsole { return ( '&STDIN', '&STDOUT' ); }

BEGIN {
    *CORE::GLOBAL::getpwuid = sub : prototype($) ($uid) {
        return CORE::getpwuid($uid) unless ( $ENV{GNU_PERLSH_TEST_MODE} // '' ) =~ /\Aunix-/;
        return ( ('fixture') x 7, $ENV{GNU_PERLSH_TEST_HOME} );
    };
}
1;
