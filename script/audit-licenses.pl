#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use FindBin    ();
use JSON::PP   qw(decode_json encode_json);
use File::Path qw(make_path);
use lib "$FindBin::Bin/../inc";
use Gnu::Build ();

sub main {
    chdir "$FindBin::Bin/.." or die $!;
    my $manifest = Gnu::Build::manifest();
    my %inventory;

    for my $path ( sort keys %{ $manifest->{files} } ) {
        my $data = Gnu::Build::slurp("vendor/readline/$path");
        my %entry =
            ( sha256 => $manifest->{files}{$path}, notice_source => "vendor/readline/$path" );
        if ( $path =~ m{^doc/(readline|rluserman|history)(?:_3)?\.(?:pdf|dvi|ps)$} ) {
            $entry{notice_source} =
                "vendor/readline/doc/" . ( $1 eq 'readline' ? 'rlman' : $1 ) . '.texi';
            $entry{note} =
                'Generated documentation: consult retained master source and original embedded notices';
        }
        elsif ( $data =~ /\x00/ ) {
            $entry{note} = 'Binary upstream material retained verbatim; consult component notices';
        }
        else {
            my @lines = split /\n/, $data;
            my @evidence;
            for my ( $i, $line ) ( indexed @lines ) {
                next
                    unless $line =~ /copyright|license|permission|public domain|warranty|authors?/i;
                push @evidence, { line => $i + 1, text => $line };
                last if @evidence >= 30;
            }
            $entry{notice_evidence} = \@evidence;
            $entry{note} =
                'Retained upstream per-file notices and component-level COPYING apply; evidence is not an automatic license classification';
        }
        $inventory{$path} = \%entry;
    }
    make_path('docs/licensing');
    open my $out, '>:raw', 'docs/licensing/vendor-inventory.json' or die $!;

    # Preserve source byte values without guessing the encodings of legacy files.
    # ASCII escapes make the inventory valid UTF-8 JSON, including Latin-1 bytes.
    print {$out} JSON::PP->new->ascii->canonical->pretty->encode( \%inventory ) or die $!;
    close $out or die "Cannot close file: $!";
    print "Indexed licensing evidence for ", scalar( keys %inventory ),
        " pristine upstream files\n";
}

main();
