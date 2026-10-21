# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package GnuWin32::Patch;
use strict;
use warnings;
use File::Spec;
sub apply {
    my ($root, $patch) = @_;
    open my $p, '<:raw', $patch or die "$patch: $!";
    my @lines = <$p>; close $p;
    my ($name, @source, @result, $pos);
    my $hunks=0;
    my $save = sub {
        return unless defined $name;
        push @result, @source[$pos .. $#source] if $pos < @source;
        open my $out, '>:raw', File::Spec->catfile($root, $name) or die $!;
        print {$out} @result; close $out or die $!;
    };
    for (my $i = 0; $i < @lines; ++$i) {
        my $line = $lines[$i];
        die "Only modifications to existing files are supported in $patch; keep new port files in win32/\n"
            if $line =~ /^(?:--- (?!a\/)|\+\+\+ (?!b\/))/;
        if ($line =~ /^--- a\/(.+)\r?\n$/) {
            $save->(); $name = $1; $name =~ s/\r$//;
            die "Unsafe patch path $name\n" if $name =~ m{(?:^|[\\/])\.\.(?:[\\/]|$)|^[\\/]|:};
            open my $in, '<:raw', File::Spec->catfile($root, $name) or die "$name: $!";
            @source = <$in>; close $in; @result = (); $pos = 0;
        } elsif ($line =~ /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/) {
            ++$hunks;
            die "Hunk without file\n" unless defined $name;
            my ($start,$old,$new)=($1-1,defined($2)?$2:1,defined($4)?$4:1);
            die "Out-of-order hunk in $patch\n" if $start < $pos;
            push @result, @source[$pos .. $start-1] if $pos < $start;
            $pos = $start;
            while ($old || $new) {
                my $part = $lines[++$i] // die "Truncated patch $patch\n";
                my $kind = substr($part,0,1,'');
                if ($kind eq ' ' || $kind eq '-') {
                    die "Patch mismatch: $name line " . ($pos+1) . " in $patch\n"
                        unless defined($source[$pos]) && $source[$pos] eq $part;
                    ++$pos; --$old;
                }
                if ($kind eq ' ' || $kind eq '+') { push @result,$part; --$new; }
                die "Invalid hunk in $patch\n" if $old < 0 || $new < 0 || $kind !~ /^[ +\-]$/;
            }
        }
    }
    die "No supported hunks in $patch\n" unless $hunks;
    $save->();
}
1;
