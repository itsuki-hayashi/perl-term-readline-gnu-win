# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package GnuWin32::Platform;
use strict;
use warnings;
use Config;
sub validate {
    my (%p) = @_;
    die "OS unsupported: native Windows 11 or Windows Server 2025 or later is required\n"
        unless $p{os} eq 'MSWin32' && $p{major} >= 10
            && $p{build} >= ($p{server} ? 26100 : 22000);
    die "Perl 5.44 or later is required\n" if $p{perl} < 5.044;
    die "An MSVC-built Perl is required (MinGW and Cygwin are unsupported)\n"
        unless $p{cc} =~ /(?:^|[\\\/])cl(?:\.exe)?$/i;
    die "Only native x64 and ARM64 Perl are supported; x86 is unsupported\n"
        unless $p{ptrsize} == 8 && $p{archname} =~ /^MSWin32-(?:x64|arm64)-/;
    die "A release shared Perl using the DLL CRT (/MD) is required\n"
        unless $p{shared} eq 'true' && $p{ccflags} =~ m{[-/]MD\b};
    die "Visual C++ 2026 (v145) or later is required\n" if ($p{msvc} // 0) < 1950;
    return $p{archname} =~ /-arm64-/ ? 'arm64' : 'amd64';
}
sub current {
    require Win32;
    my @os = Win32::GetOSVersion();
    return (os => $^O, major => $os[1], build => $os[3], server => $os[8] != 1,
        perl => $], cc => $Config{cc}, ptrsize => $Config{ptrsize},
        archname => $Config{archname}, shared => $Config{useshrplib},
        ccflags => $Config{ccflags});
}
1;
