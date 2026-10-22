# Modernized 2026-10-23: Perl 5.44 author checks; retain interface contracts.
# Modified 2026-10-21 by Itsuki Hayashi: Windows-only Gnu fork.
# Fork modifications copyright (c) 2026 Itsuki Hayashi.
# SPDX-License-Identifier: GPL-3.0-or-later
# Original upstream copyright and license notices below are retained.
# -*- perl -*-
#       02test_use.t - give up on a dumb terminal
#
#       $Id: 00checkver.t 518 2016-05-18 16:33:37Z hayashi $
#
#       Copyright (c) 2023 Hiroo Hayashi.  All rights reserved.
#
#       This program is free software; you can redistribute it and/or
#       modify it under the same terms as Perl itself.

use v5.44;
use strict;
use warnings;
use Test::More tests => 3;
our ($loaded);

BEGIN {
    $ENV{PERL_RL} = 'Gnu';     ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional. /  force to use Term::ReadLine::Gnu
    $ENV{TERM}    = 'dumb';    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional.
}

END {
    unless ($loaded) {
        ok( 0, 'fail before loading' );
        diag "\nPlease report the output of \'perl Makefile.PL\'\n";
    }
}

use Term::ReadLine;
ok( 1, 'load done' );
$loaded = 1;

my $t = Term::ReadLine->new('ReadLineTest');
isa_ok( $t, 'Term::ReadLine::Stub' );

print "# \$TERM=$ENV{TERM}\n";

my $e = eval "Term::ReadLine->new('The 2nd new'); 1";    ## no critic (BuiltinFunctions::ProhibitStringyEval) -- Evaluate user REPL input or test compile-time backend loading.
{
    ok( !defined($e) || $e != 1, 'reject the 2nd "new Term::ReadLine"' );
}

exit 0;

