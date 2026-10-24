# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package ScriptToolFixture;
use v5.44;
use strict;
use warnings;
use Symbol     qw(qualify_to_ref);
use JSON::PP   ();
use Config     qw(%Config);
use File::Path qw(make_path);
use File::Copy ();
use lib 'inc';
use Gnu::Toolchain ();
use Gnu::Command   ();

sub run ( $scenario, $code ) {
    my @calls;
    my $installed;
    my $activate = qualify_to_ref('Gnu::Toolchain::activate');
    local *{$activate} = sub { return 'fixture compiler'; };
    my $logged = qualify_to_ref('Gnu::Command::run_logged');
    local *{$logged} = sub {
        my ( $log, @command ) = @_;
        push @calls, [ $log, @command ];
        die "fixture command failed\n" if $scenario eq 'command-fails' && @calls == 3;
        for my $argument (@command) {
            $installed = $1 if $argument =~ /\AINSTALL_BASE=(.+)/;
        }
        if ( $command[-1] eq 'install' ) {

            my $directory = "$installed/lib/perl5/$Config{archname}/auto/Term/ReadLine/Gnu";
            make_path($directory);
            open my $dll, '>:raw', "$directory/Gnu.dll" or die $!;
            print {$dll} 'fixture binary placeholder' or die $!;
            close $dll                                or die $!;
        }
        if ( $command[-1] eq 'installed-smoke.pl' && $scenario ne 'no-evidence' ) {
            open my $result, '>:raw', 'installed-smoke-result.txt' or die $!;
            print {$result} 'fixture installed smoke evidence' or die $!;
            close $result                                      or die $!;
        }
        return 0;
    };
    my $copy_slot = qualify_to_ref('File::Copy::copy');
    my $copy      = *{$copy_slot}{CODE};
    local *{$copy_slot} = $scenario eq 'copy-fails' ? sub { return 0; } : $copy;
    my $result = eval { $code->() };
    my $error  = $@;
    open my $trace, '>:raw', $ENV{GNU_TOOL_FIXTURE_TRACE} or die $!;
    print {$trace} JSON::PP->new->encode( \@calls ) or die $!;
    close $trace                                    or die $!;
    die $error if length $error;
    return $result;
}
1;
