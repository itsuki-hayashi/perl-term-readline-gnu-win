#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use FindBin;
use Getopt::Long qw(GetOptions);
use Archive::Tar;
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP;
chdir "$FindBin::Bin/.." or die $!;
use lib "$FindBin::Bin/../inc";
use GnuWin32::Build;
my ($archive,$version,$sha,$url);
GetOptions('archive=s'=>\$archive,'version=s'=>\$version,'sha256=s'=>\$sha,'url=s'=>\$url) or die 'Invalid options';
die "Provide --archive --version --sha256 --url; download and authenticate the source first\n"
    unless $archive && $version && $sha && $url;
die "Invalid version or checksum\n" unless $version =~ /^\d+\.\d+(?:\.\d+)?$/ && $sha =~ /^[a-fA-F0-9]{64}$/;
die "Archive checksum mismatch\n" unless sha256_hex(GnuWin32::Build::slurp($archive)) eq lc $sha;
make_path('build');
my $candidate=tempdir('readline-update-XXXX',DIR=>'build');
my $tar=Archive::Tar->new($archive,1); my %files;
for my $f ($tar->get_files) {
    next unless $f->is_file;
    my $path=$f->full_path; $path =~ s{^readline-\Q$version\E/}{} or die 'Unexpected archive root';
    die "Unsafe archive path\n" if $path =~ m{(?:^|/)\.\.(?:/|$)|^[\\/]|:};
    my $out="$candidate/readline/$path"; (my $dir=$out)=~s{/[^/]+$}{}; make_path($dir);
    open my $h,'>:raw',$out or die $!; print {$h} $f->get_content; close $h;
    $files{$path}=sha256_hex($f->get_content);
}
my $manifest=decode_json(GnuWin32::Build::slurp('vendor/manifest.json'));
$manifest->{readline}={version=>$version,url=>$url,sha256=>lc($sha),files=>\%files,patches=>$manifest->{readline}{patches}};
open my $out,'>',"$candidate/manifest.json" or die $!;
print {$out} JSON::PP->new->canonical->pretty->encode($manifest); close $out;
print "Verified candidate: $candidate\nReview the diff, replace vendor/readline and vendor/manifest.json, then refresh patches and test.\n";
