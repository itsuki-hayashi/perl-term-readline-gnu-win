# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
BEGIN { local $ENV{PERL_RL} = 'Stub'; require Term::ReadLine; }
use Term::ReadLine;
use Win32 ();
my $case = shift @ARGV;

my @os = Win32::GetOSVersion();
$os[1] = 9     if $case eq 'old-major';
$os[3] = 19045 if $case eq 'old-client';

if ( $case eq 'old-server' || $case eq 'new-server' ) {
    $os[8] = 3;
    $os[3] = $case eq 'old-server' ? 20348 : 26100;
}
local *Win32::GetOSVersion = sub { return @os; };
my $actual_os = $^O;
local $^O = $case eq 'nonwindows' ? 'linux' : $actual_os;
local $ENV{TERM} =
      $case eq 'emacs'                                    ? 'emacs'
    : ( $case eq 'inside-emacs' || $case eq 'emacs-env' ) ? 'dumb'
    :                                                       'win32';
local $ENV{INSIDE_EMACS} = $case eq 'inside-emacs' ? 'yes' : undef;
local $ENV{EMACS}        = $case eq 'emacs-env'    ? 't'   : undef;
delete $ENV{TERM} if $case eq 'no-term';
require Term::ReadLine::Gnu;
print "loaded $ENV{TERM}\n";
