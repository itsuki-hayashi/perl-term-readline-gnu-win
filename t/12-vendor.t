# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use lib 'inc';
use Gnu::Build ();
ok( Gnu::Build::verify_vendor(), 'complete pristine vendor tree matches recorded checksums' );
done_testing;
