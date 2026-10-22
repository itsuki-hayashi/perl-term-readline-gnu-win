# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package Gnu::Patch;
use v5.44;
use strict;
use warnings;
use File::Spec ();

# Apply one hunk to the current file. Positions and counters are shared with
# the file parser; every consumed context/deletion line must match exactly.
sub _hunk ( $lines, $index, $source, $result, $position, $name, $patch, $start, $old, $new ) {
    die "Out-of-order hunk in $patch\n" if $start < $$position;
    push $result->@*, $source->@[ $$position .. $start - 1 ] if $$position < $start;
    $$position = $start;
    while ( $old || $new ) {
        my $part = $lines->[ ++$$index ] // die "Truncated patch $patch\n";
        my $kind = substr( $part, 0, 1, '' );
        if ( $kind eq ' ' || $kind eq '-' ) {
            die "Patch mismatch: $name line " . ( $$position + 1 ) . " in $patch\n"
                unless defined( $source->[$$position] ) && $source->[$$position] eq $part;
            ++$$position;
            --$old;
        }
        if ( $kind eq ' ' || $kind eq '+' ) {
            push $result->@*, $part;
            --$new;
        }
        die "Invalid hunk in $patch\n" if $old < 0 || $new < 0 || $kind !~ /^[ +\-]$/;
    }
    return;
}

sub apply {
    my ( $root, $patch ) = @_;
    open my $p, '<:raw', $patch or die "$patch: $!";
    my @lines = <$p>;
    close $p or die "Cannot close file: $!";
    my ( $name, @source, @result, $pos );
    my $hunks = 0;
    my $save  = sub {
        return unless defined $name;
        push @result, @source[ $pos .. $#source ] if $pos < @source;
        open my $out, '>:raw', File::Spec->catfile( $root, $name ) or die $!;
        print {$out} @result;
        close $out or die $!;
    };
    for ( my $i = 0 ; $i < @lines ; ++$i ) {
        my $line = $lines[$i];
        die
            "Only modifications to existing files are supported in $patch; keep new port files in win32/\n"
            if $line =~ /^(?:--- (?!a\/)|\+\+\+ (?!b\/))/;
        if ( $line =~ /^--- a\/(.+)\r?\n$/ ) {
            $save->();
            $name = $1;
            $name =~ s/\r$//;
            die "Unsafe patch path $name\n" if $name =~ m{(?:^|[\\/])\.\.(?:[\\/]|$)|^[\\/]|:};
            open my $in, '<:raw', File::Spec->catfile( $root, $name ) or die "$name: $!";
            @source = <$in>;
            close $in or die "Cannot close file: $!";
            @result = ();
            $pos    = 0;
        }
        elsif ( $line =~ /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/ ) {
            ++$hunks;
            die "Hunk without file\n" unless defined $name;
            my ( $start, $old, $new ) = ( $1 - 1, defined($2) ? $2 : 1, defined($4) ? $4 : 1 );
            _hunk( \@lines, \$i, \@source, \@result, \$pos, $name, $patch, $start, $old, $new );
        }
    }
    die "No supported hunks in $patch\n" unless $hunks;
    $save->();
}
1;
