# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
my ( $input, $output, $script ) = @ARGV;
open STDIN,  '<:raw', $input   or die $!;
open STDOUT, '>:raw', $output  or die $!;
open STDERR, '>&',    \*STDOUT or die $!;
system {$^X} $^X, '-Mblib', '-It/lib', '-MPerlshTestBoot', $script;
die "Cannot launch perlsh: $!" if $? == -1;
exit( $? >> 8 );
