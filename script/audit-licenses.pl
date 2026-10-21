#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use FindBin;
use JSON::PP;
use File::Path qw(make_path);
chdir "$FindBin::Bin/.." or die $!;
use lib "$FindBin::Bin/../inc";
use GnuWin32::Build;
my $manifest=GnuWin32::Build::manifest();
my %inventory;
for my $path (sort keys %{$manifest->{files}}) {
    my $data=GnuWin32::Build::slurp("vendor/readline/$path");
    my %entry=(sha256=>$manifest->{files}{$path},notice_source=>"vendor/readline/$path");
    if ($path =~ m{^doc/(readline|rluserman|history)(?:_3)?\.(?:pdf|dvi|ps)$}) {
        $entry{notice_source}="vendor/readline/doc/" . ($1 eq 'readline' ? 'rlman' : $1) . '.texi';
        $entry{note}='Generated documentation: consult retained master source and original embedded notices';
    } elsif ($data =~ /\x00/) {
        $entry{note}='Binary upstream material retained verbatim; consult component notices';
    } else {
        my @lines=split /\n/,$data;
        my @evidence;
        for my $i (0..$#lines) {
            next unless $lines[$i] =~ /copyright|license|permission|public domain|warranty|authors?/i;
            push @evidence,{line=>$i+1,text=>$lines[$i]};
            last if @evidence>=30;
        }
        $entry{notice_evidence}=\@evidence;
        $entry{note}='Retained upstream per-file notices and component-level COPYING apply; evidence is not an automatic license classification';
    }
    $inventory{$path}=\%entry;
}
make_path('docs/licensing');
open my $out,'>','docs/licensing/vendor-inventory.json' or die $!;
print {$out} JSON::PP->new->canonical->pretty->encode(\%inventory); close $out;
print "Indexed licensing evidence for ",scalar(keys %inventory)," pristine upstream files\n";
