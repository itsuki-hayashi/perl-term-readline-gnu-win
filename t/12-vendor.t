# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use Test::More;
use lib 'inc';
use GnuWin32::Build;
ok(GnuWin32::Build::verify_vendor(),'complete pristine vendor tree matches recorded checksums');
done_testing;
