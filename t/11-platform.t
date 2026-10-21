# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use Test::More;
use lib 'inc';
use GnuWin32::Platform;
my %valid=(os=>'MSWin32',major=>10,build=>22000,server=>0,perl=>5.044,
    cc=>'cl',ptrsize=>8,archname=>'MSWin32-x64-multi-thread',shared=>'true',ccflags=>'-MD',msvc=>1950);
is(GnuWin32::Platform::validate(%valid),'amd64','minimum client supported');
is(GnuWin32::Platform::validate(%valid,archname=>'MSWin32-arm64-multi-thread'),'arm64','ARM64 target');
is(GnuWin32::Platform::validate(%valid,server=>1,build=>26100),'amd64','Server 2025 CI target');
for my $case ([os=>'linux'],[build=>19045],[perl=>5.042],[cc=>'gcc'],[msvc=>1944],
    [archname=>'MSWin32-x86-multi-thread',ptrsize=>4],[ccflags=>'-MT'],[shared=>'false'],[server=>1,build=>20348]) {
    my $ok=eval { GnuWin32::Platform::validate(%valid,@$case); 1 };
    ok(!$ok,"unsupported configuration rejected: @$case");
    like($@,qr/required|unsupported|supported/, 'actionable failure');
}
done_testing;
