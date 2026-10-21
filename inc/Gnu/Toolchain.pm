# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package Gnu::Toolchain;
use strict;
use warnings;
use Config;
use File::Spec;
use File::Temp qw(tempfile);
sub activate {
    my (%options) = @_;
    my $target = $Config{archname} =~ /-arm64-/ ? 'arm64' : 'amd64';
    die "Only x64 and ARM64 Perl are supported\n" unless $Config{archname} =~ /^MSWin32-(?:x64|arm64)-/;
    my @vswhere = grep { -f $_ } map { File::Spec->catfile($_, 'Microsoft Visual Studio', 'Installer', 'vswhere.exe') }
        grep { defined && length } @ENV{'ProgramFiles(x86)', 'ProgramFiles'};
    die "vswhere.exe was not found; install Visual Studio 2026 C++ tools\n" unless @vswhere;
    my @range = $options{vs_major} ? ('-version', "[$options{vs_major}.0," . ($options{vs_major}+1) . '.0)') : ('-version', '[18.0,)');
    open my $p, '-|', $vswhere[0], '-latest', '-products', '*', @range, '-property', 'installationPath' or die $!;
    chomp(my $vs = <$p> // ''); close $p or die "Visual Studio discovery failed\n";
    die "Visual Studio 2026 or later was not found\n" unless length $vs;
    my $dev = File::Spec->catfile($vs, 'Common7', 'Tools', 'VsDevCmd.bat');
    my $host = ($ENV{PROCESSOR_ARCHITECTURE} // '') =~ /ARM64/i ? 'arm64' : 'amd64';
    my $command = qq{"$dev" -no_logo -arch=$target -host_arch=$host};
    if ($options{toolset}) {
        die "Invalid toolset\n" unless $options{toolset} =~ /^\d+\.\d+(?:\.\d+)?$/;
        $command .= " -vcvars_ver=$options{toolset}";
    }
    my ($batch,$path)=tempfile('gnu-msvc-XXXX', SUFFIX=>'.cmd', TMPDIR=>1, UNLINK=>1);
    print {$batch} "\@echo off\ncall $command >nul\nif errorlevel 1 exit /b 1\nset\n";
    close $batch or die $!;
    open $p, '-|', $ENV{COMSPEC} || 'cmd.exe', '/d', '/c', 'call', $path or die $!;
    while (<$p>) { chomp; $ENV{$1} = $2 if /^([^=]+)=(.*)$/; }
    close $p or die "Cannot initialize the $target MSVC environment\n";
    require File::Basename;
    $ENV{PATH} = File::Basename::dirname($^X) . ';' . $ENV{PATH};
    return $vs;
}
sub compiler_version {
    open my $p, '-|', 'cl', '/nologo', '/EP', 'inc/compiler-version.c' or die "Cannot run cl; use a Visual Studio 2026 Native Tools command prompt\n";
    local $/; my $out = <$p>; close $p or die "Cannot run the MSVC compiler\n";
    my ($v) = $out =~ /GNU_MSC_VER\s+(\d+)/;
    die "Could not identify the compiler\n" unless $v;
    my ($arch)=$out =~ /GNU_MSC_ARCH\s+(\w+)/;
    my $expected=$Config{archname} =~ /-arm64-/ ? 'arm64' : 'amd64';
    die "Compiler target does not match $Config{archname}; use the $expected Native Tools prompt\n"
        unless defined $arch && $arch eq $expected;
    return $v;
}
1;
