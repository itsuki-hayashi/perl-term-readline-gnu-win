# Modernized 2026-10-23: Perl 5.44 author checks; retain interface contracts.
# Modified 2026-10-21 by Itsuki Hayashi: Windows-only Gnu fork.
# Fork modifications copyright (c) 2026 Itsuki Hayashi.
# SPDX-License-Identifier: GPL-3.0-or-later
# Original upstream copyright and license notices below are retained.
# -*- perl -*-
#       01test_use.t - reject 'use Term::ReadLine::Gnu'
#
#       $Id: 00checkver.t 518 2016-05-18 16:33:37Z hayashi $
#
#       Copyright (c) 2017 Hiroo Hayashi.  All rights reserved.
#
#       This program is free software; you can redistribute it and/or
#       modify it under the same terms as Perl itself.

use v5.44;
use strict;
use warnings;
use Test::More tests => 2;
our ($loaded);

BEGIN {
    $ENV{PERL_RL} = 'Gnu';    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional. /  force to use Term::ReadLine::Gnu
}

END {
    unless ($loaded) {
        ok( 0, 'fail before loading' );
        diag "\nPlease report the output of \'perl Makefile.PL\'\n";
    }
}

my $e;
$e = eval "use Term::ReadLine::Gnu; 1";    ## no critic (BuiltinFunctions::ProhibitStringyEval) -- Evaluate user REPL input or test compile-time backend loading.
{
    ok( !defined($e) || $e != 1, 'reject "use Term::ReadLine::Gnu"' );
}

$e = eval "use Term::ReadLine; 1";         ## no critic (BuiltinFunctions::ProhibitStringyEval) -- Evaluate user REPL input or test compile-time backend loading.
ok( $e == 1, '"use Term::ReadLine"' );
$loaded = 1;

exit 0;

