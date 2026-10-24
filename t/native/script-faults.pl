# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use lib 't/lib';
use POSIX      ();
use IO::Handle ();
our ( $target, $operation, $remaining, $report_handle );

sub inject ($name) {
    my ( undef, $file ) = caller(1);
    $file =~ tr{\\}{/};
    return 0 unless defined $target && $file eq $target && $operation eq $name;
    return --$remaining == 0;
}

sub unwritable ($handle) {
    IO::Handle::autoflush( $handle, 1 );
    CORE::open( my $readonly, '<:raw', $target )                       or die $!;
    POSIX::dup2( CORE::fileno($readonly), CORE::fileno($handle) ) >= 0 or die $!;
    CORE::close($readonly)                                             or die $!;
}

BEGIN {
    *CORE::GLOBAL::unlink = sub : prototype(@) (@files) {
        return 0 if inject('unlink');
        return CORE::unlink(@files);
    };
    *CORE::GLOBAL::open = sub : prototype(*;$@) {
        return 0 if inject('open');
        my $write = inject('write');
        my $opened;
        if ( @_ > 3 ) { $opened = CORE::open( $_[0], $_[1], $_[2], @_[ 3 .. $#_ ] ); }
        elsif ( @_ == 3 ) { $opened = CORE::open( $_[0], $_[1], $_[2] ); }
        else              { $opened = CORE::open( $_[0], $_[1] ); }
        my ( undef, $file ) = caller;
        $file =~ tr{\\}{/};
        $report_handle = $_[0]
            if defined $target
            && $file eq $target
            && $operation =~ /\Aafter-/
            && !defined $report_handle;
        unwritable( $_[0] ) if $opened && $write;
        return $opened;
    };
    *CORE::GLOBAL::close = sub : prototype(*) ($handle) {
        my $result = CORE::close($handle);
        unwritable($report_handle) if inject('after-close');
        return 0                   if inject('close');
        return $result;
    };
    *CORE::GLOBAL::chdir = sub : prototype(;$) ( $directory = undef ) {
        return 0 if inject('chdir');
        my $result = defined $directory ? CORE::chdir($directory) : CORE::chdir();
        unwritable($report_handle) if inject('after-chdir');
        return $result;
    };
}
( $target, $operation, $remaining ) = splice @ARGV, 0, 3;
$target =~ tr{\\}{/};
local $0 = $target;
require FindBin;
FindBin::again();
my $result;
if ( $ENV{GNU_COVER_FIXTURE_SCENARIO} ) {
    require CoverageFixture;
    $result = CoverageFixture::run( $ENV{GNU_COVER_FIXTURE_SCENARIO},
        sub { my $value = do $target; die $@ if $@; return $value; } );
}
elsif ( $ENV{GNU_TOOL_FIXTURE_SCENARIO} ) {
    require ScriptToolFixture;
    $result = ScriptToolFixture::run(
        $ENV{GNU_TOOL_FIXTURE_SCENARIO},
        sub {
            my $value = do $target;
            die $@ if $@;
            return $value;
        }
    );
}
else {
    $result = do $target;
}
die $@ if $@;
die "Cannot execute $target: $!" unless defined $result;
