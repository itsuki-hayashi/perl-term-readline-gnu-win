# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use lib 'inc';
use Gnu::Toolchain ();
use Config         qw(%Config);

is( Gnu::Toolchain::unique_path('A;B;a;;b;'),
    'A;B;', 'compiler PATH deduplication preserves first entries and current directory' );

# Environment activation is process-local; never change the caller's shell.
{
    local %ENV = %ENV;
    my $vs = Gnu::Toolchain::activate();
    ok( -d $vs, 'default discovery locates installed Visual Studio' );
    cmp_ok( Gnu::Toolchain::compiler_version(), '>=', 1950, 'activated compiler meets baseline' );
    my ($major)   = $ENV{VisualStudioVersion} =~ /\A([0-9]+)/;
    my ($toolset) = $ENV{VCToolsVersion}      =~ /\A([0-9]+[.][0-9]+)/;
    my $explicit  = eval { Gnu::Toolchain::activate( vs_major => $major, toolset => $toolset ) };
    die "Explicit MSVC selection failed (VS $major, toolset $toolset): $@" unless defined $explicit;
    ok( -d $explicit, 'explicit Visual Studio and toolset selection works' );
    my $ok = eval { Gnu::Toolchain::activate( toolset => '14.5 & invalid' ); 1 };
    ok( !$ok, 'unsafe toolset rejected before launching batch' );
    like( $@, qr/Invalid toolset/, 'toolset diagnostic' );
}
{
    local %ENV = %ENV;
    delete @ENV{ 'ProgramFiles(x86)', 'ProgramFiles' };
    my $ok = eval { Gnu::Toolchain::activate(); 1 };
    ok( !$ok, 'absent discovery program rejected' );
    like( $@, qr/vswhere.exe was not found/, 'discovery installation hint' );
}
{
    local *Gnu::Toolchain::Config = { %Config, archname => 'MSWin32-x86-multi-thread' };
    my $ok = eval { Gnu::Toolchain::activate(); 1 };
    ok( !$ok, 'unsupported Perl architecture rejected before discovery' );
    like( $@, qr/Only x64 and ARM64/, 'unsupported architecture diagnostic' );
}
{
    local %ENV = %ENV;
    Gnu::Toolchain::activate();
    my $other =
        $Config{archname} =~ /-arm64-/ ? 'MSWin32-x64-multi-thread' : 'MSWin32-arm64-multi-thread';
    local *Gnu::Toolchain::Config = { %Config, archname => $other };
    my $ok = eval { Gnu::Toolchain::compiler_version(); 1 };
    ok( !$ok, 'compiler for another architecture rejected' );
    like( $@, qr/Compiler target does not match/, 'compiler mismatch diagnostic' );
}
{
    local %ENV = %ENV;
    my $ok = eval { Gnu::Toolchain::activate( vs_major => 9999 ); 1 };
    ok( !$ok, 'missing requested Visual Studio rejected' );
    like( $@, qr/Visual Studio 2026 or later was not found/, 'missing version diagnostic' );
}
{
    local %ENV = %ENV;
    local $ENV{COMSPEC} = $^X;
    my $ok = eval { Gnu::Toolchain::activate(); 1 };
    ok( !$ok, 'failed environment batch rejected' );
    like( $@, qr/Cannot initialize/, 'batch failure diagnostic' );
}
my $fake = tempdir( CLEANUP => 1 );
for my $case (
    [
        "\@echo off\n\@echo not a compiler\n",
        qr/Could not identify/,
        'unrecognized compiler output'
    ],
    [
        "\@echo off\n\@echo GNU_MSC_VER 1950\n",
        qr/Compiler target does not match/,
        'missing target marker'
    ],
    [ "\@echo off\n\@exit /b 1\n", qr/Cannot run/, 'unsuccessful compiler' ],
    )
{
    open my $batch, '>:raw', "$fake/cl.bat" or die $!;
    print {$batch} $case->[0] or die $!;
    close $batch              or die $!;
    local $ENV{PATH} = $fake;
    my $ok = eval { Gnu::Toolchain::compiler_version(); 1 };
    ok( !$ok, $case->[2] );
    like( $@, $case->[1], "$case->[2] diagnostic" );
}
done_testing;
