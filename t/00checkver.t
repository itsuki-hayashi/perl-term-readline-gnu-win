# Modernized 2026-10-23: Perl 5.44 author checks; retain interface contracts.
# Modified 2026-10-21 by Itsuki Hayashi: Windows-only Gnu fork.
# Fork modifications copyright (c) 2026 Itsuki Hayashi.
# SPDX-License-Identifier: GPL-3.0-or-later
# Original upstream copyright and license notices below are retained.
# -*- perl -*-
#       00check.t - check versions
#
#       Copyright (c) 2008-2022 Hiroo Hayashi.  All rights reserved.
#
#       This program is free software; you can redistribute it and/or
#       modify it under the same terms as Perl itself.

use v5.44;
use strict;
use warnings;
use Test::More tests => 5;
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

use Term::ReadLine;
ok( 1, 'load done' );
$loaded = 1;

# The GNU Readline library requires $TERM to be set properly.
# https://github.com/hirooih/perl-trg/issues/11
if ( $ENV{TERM} eq "emacs" || defined( $ENV{EMACS} ) || defined( $ENV{INSIDE_EMACS} ) ) {
    warn "Wrong env setting: \$TERM is set to 'emacs', or \$EMACS or \$INSIDE_EMACS is defined.\n";
    exit 1;
}
ok( 1, '$TERM value' );

print "# I'm testing Term::ReadLine::Gnu version $Term::ReadLine::Gnu::VERSION\n";

my $t = Term::ReadLine->new('ReadLineTest');
isa_ok( $t, 'Term::ReadLine' );
my $a = $t->Attribs;
isa_ok( $a, 'Term::ReadLine', 'Attribs' );

print "# OS: $^O\n";
print "# Perl version: $]\n";
printf "# GNU Readline Library version: $a->{library_version}, 0x%X\n", $a->{readline_version};
print "# \$TERM=$ENV{TERM}\n";

ok( 1, 'library_version and readline_version' );

exit 0;

