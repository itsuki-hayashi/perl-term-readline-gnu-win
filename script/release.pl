#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use FindBin;
use Getopt::Long qw(GetOptions);
use Archive::Tar;
use ExtUtils::Manifest qw(mkmanifest maniread);
use ExtUtils::MakeMaker;
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Spec;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:flock);
chdir "$FindBin::Bin/.." or die $!;
make_path('build');
open my $lock,'>>','build/release.lock' or die $!;
flock($lock,LOCK_EX|LOCK_NB) or die "Another release preparation is running\n";
my $output='dist';
GetOptions('output=s'=>\$output) or die "Usage: perl script/release.pl [--output DIR]\n";
mkmanifest();
my $version=MM->parse_version('lib/Term/ReadLine/GnuWin32.pm');
my $name="Term-ReadLine-GnuWin32-$version";
system('nmake','/nologo','metafile') == 0 or die "Run perl Makefile.PL in the developer prompt first\n";
copy("$name/META.$_", "META.$_") or die "Cannot copy generated META.$_: $!" for qw(json yml);
mkmanifest();
local $ENV{RELEASE_TESTING}=1;
system {$^X} $^X,'-MTest::Harness','-e','runtests(glob q(xt/*.t))' ;
die "Release checks failed\n" if $?;
my $tar=Archive::Tar->new;
my $manifest=maniread();
for my $path (sort keys %$manifest) {
    die "Unsafe manifest entry: $path\n" if $path =~ m{(?:^|/)\.\.(?:/|$)|^[\\/]|:};
    open my $f,'<:raw',$path or die "$path: $!"; local $/; my $data=<$f>; close $f;
    $tar->add_data("$name/$path",$data,{mode=>($path =~ m{^script/} ? 0755 : 0644),
        uid=>0,gid=>0,uname=>'',gname=>'',mtime=>($ENV{SOURCE_DATE_EPOCH}//time)});
}
make_path($output);
my $archive=File::Spec->catfile($output,"$name.tar.gz");
$tar->write($archive,Archive::Tar::COMPRESS_GZIP()) or die "Cannot write $archive\n";
open my $f,'<:raw',$archive or die $!; local $/; my $sha=sha256_hex(<$f>); close $f;
open my $sum,'>',"$archive.sha256" or die $!; print {$sum} "$sha  $name.tar.gz\n"; close $sum;
print "Prepared $archive (not uploaded)\n";
