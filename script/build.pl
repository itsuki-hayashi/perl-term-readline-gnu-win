#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use FindBin;
use File::Spec;
use Getopt::Long qw(GetOptions);
use Config;
use File::Path qw(make_path);
chdir "$FindBin::Bin/.." or die $!;
use lib "$FindBin::Bin/../inc";
use GnuWin32::Toolchain;
use GnuWin32::Command;
use JSON::PP;
my ($install,$stage,$vs,$toolset)=(0,'stage',undef,undef);
GetOptions('install'=>\$install,'stage=s'=>\$stage,'vs-major=i'=>\$vs,'toolset=s'=>\$toolset) or die "Invalid build options\n";
my $visual_studio=GnuWin32::Toolchain::activate(vs_major=>$vs,toolset=>$toolset);
$stage=File::Spec->rel2abs($stage);
local $ENV{LC_ALL}='C';
make_path('build');
open my $log,'>','build/build.log' or die $!; close $log;
open my $config,'>','build/configuration.json' or die $!;
print {$config} JSON::PP->new->pretty->canonical->encode({perl=>$^X,version=>$Config{version},architecture=>$Config{archname},
    ccflags=>$Config{ccflags},visual_studio=>$visual_studio,toolset=>$ENV{VCToolsVersion},sdk=>$ENV{WindowsSDKVersion}});
close $config;
sub run { GnuWin32::Command::run_logged('build/build.log',@_); }
run($^X,'Makefile.PL',"INSTALL_BASE=$stage",@ARGV);
run('nmake','/nologo');
run('nmake','/nologo','test');
run('nmake','/nologo','install');
if ($install) { run($^X,'Makefile.PL',@ARGV); run('nmake','/nologo','install'); }
print "Built with $visual_studio; staged in $stage\n";
