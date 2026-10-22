# Modernized 2026-10-23: Perl 5.44 author checks; retain interface contracts.
# Modified 2026-10-21 by Itsuki Hayashi: Windows-only Gnu fork.
# Fork modifications copyright (c) 2026 Itsuki Hayashi.
# SPDX-License-Identifier: GPL-3.0-or-later
# Original upstream copyright and license notices below are retained.
# -*- perl -*-
#       callback.t - Test script for Term::ReadLine:GNU callback function
#
#       Copyright (c) 1999-2016 Hiroo Hayashi.  All rights reserved.
#
#       This program is free software; you can redistribute it and/or
#       modify it under the same terms as Perl itself.

use v5.44;
use strict;
use warnings;
use Test::More tests => 8;

BEGIN {
    $ENV{PERL_RL} = 'Gnu';    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional. /  force to use Term::ReadLine::Gnu
}

# 'define @ARGV' is deprecated
my $verbose = scalar @ARGV && ( $ARGV[0] eq 'verbose' );

use Term::ReadLine;
ok( 1, 'load done' );

########################################################################
# test new method

my $term = Term::ReadLine->new('ReadLineTest');
isa_ok( $term, 'Term::ReadLine' );
my $attribs = $term->Attribs;
isa_ok( $attribs, 'Term::ReadLine', 'Attribs' );

my ($version) = $attribs->{library_version} =~ /(\d+\.\d+)/;

########################################################################
# check Tk is installed and X Window is available
{
    if ( eval { require Tk; Tk->import(); 1 } && $ENV{DISPLAY} && $ENV{DISPLAY} ne '' ) {
        ok( 1, 'use Tk' );
    }
    else {
        diag 'skipped since Tk is not available.';
        ok( 1, 'skipped since Tk is not available' ) for 1 .. 5;
        exit 0;
    }
}

########################################################################
# setup IO stream
my ( $IN, $OUT );
if ($verbose) {

    # wait for Perl Tk script from tty
    $IN  = $attribs->{instream};
    $OUT = $attribs->{outstream};
}
else {
    # non-interactive test
    # to surpress warning on GRL 4.2a (and above?).
    $attribs->{prep_term_function} = sub { }
        if ( $version > 4.1 );

    $attribs->{instream} = $IN = \*DATA;
    open( my $null, '>', 'NUL' ) or die "cannot open \`/dev/null\': $!\n";
    $attribs->{outstream} = $OUT = $null;
}

########################################################################
my $mw;
$mw = eval { MainWindow->new(); };
isa_ok( $mw, 'MainWindow' ) or die "Cannot continue...\n";

# create file event handler
$mw->fileevent( $IN, 'readable', $attribs->{callback_read_char} );
ok( 1, 'callback_read_char' );

$term->callback_handler_install(
    "> ",
    sub {
        my $line = shift;
        quit() unless defined $line;

        note $line unless $verbose;
        eval $line;    ## no critic (BuiltinFunctions::ProhibitStringyEval, ErrorHandling::RequireCheckingReturnValueOfEval) -- Evaluate user REPL input or test compile-time backend loading. The test or callback checks the resulting exception through $@.
        print {$OUT} "$@\n" if $@;
    }
);

# skip not to overwrite command prompt in the verbose mode
ok( 1, 'callback_handler_install' ) unless $verbose;

# create Window Manager Delete Window ClientMessage event handler
$mw->protocol( 'WM_DELETE_WINDOW' => \&quit );

&MainLoop;    ## no critic (Subroutines::ProhibitAmpersandSigils) -- Preserve upstream argument forwarding and prototype bypass.

sub quit {
    note 'quitting...';

    # delayed.  See above.
    ok( 1, 'callback_handler_install' ) if $verbose;

    # delete event handler
    $mw->fileevent( $IN, 'readable', '' );
    $term->callback_handler_remove();
    $mw->destroy;
    ok( 1, 'callback_handler_remove and destroy' );

    unless ($verbose) {

        # Be quiet during CPAN Testers testing.
        diag "Try \`$^X -Mblib t/callback.t verbose\', if you will.\n"
            if ( !$ENV{AUTOMATED_TESTING} );
    }
    exit 0;
}

__END__
$b=$mw->Button(-text=>'hello',-command=>sub{print {$OUT} 'hello'})
$b->pack;
