# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use lib 'inc';
use Gnu::Quality ();

for my $case (
    [ 'nonwindows',   qr/requires native Windows/ ],
    [ 'old-major',    qr/Windows 11 or Windows Server/ ],
    [ 'old-client',   qr/Windows 11 or Windows Server/ ],
    [ 'old-server',   qr/Windows 11 or Windows Server/ ],
    [ 'emacs',        qr/Use Term::ReadLine::Stub/ ],
    [ 'inside-emacs', qr/Use Term::ReadLine::Stub/ ],
    [ 'emacs-env',    qr/Use Term::ReadLine::Stub/ ],
    )
{
    my ( $status, $output ) =
        Gnu::Quality::capture( $^X, '-Mblib', 't/native/load-contract.pl', $case->[0] );
    ok( $status != 0, "$case->[0] refuses backend loading" );
    like( $output, $case->[1], "$case->[0] loading diagnostic" );
}
for my $case ( 'new-server', 'no-term' ) {
    my ( $status, $output ) =
        Gnu::Quality::capture( $^X, '-Mblib', 't/native/load-contract.pl', $case );
    is( $status, 0, "$case permits backend loading" );
    like( $output, qr/loaded win32/, "$case selects native terminal" );
}
my ( $configure_status, $configure_output );
{
    local $ENV{GNU_PERLSH_TEST_MODE} = 'configure';
    ( $configure_status, $configure_output ) = Gnu::Quality::capture( $^X, '-Iinc', '-It/lib',
        '-MPerlshTestBoot', abs_path('Makefile.PL') );
}
ok( $configure_status != 0, 'configuration rejects a non-Windows platform' );
like( $configure_output, qr/targets native Windows only/, 'configuration platform diagnostic' );
done_testing;
