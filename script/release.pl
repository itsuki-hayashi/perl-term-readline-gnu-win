#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use FindBin      ();
use Getopt::Long qw(GetOptions);
use Archive::Tar;
use ExtUtils::Manifest qw(mkmanifest maniread);
use ExtUtils::MakeMaker;
use File::Path  qw(make_path);
use File::Spec  ();
use JSON::PP    qw(decode_json encode_json);
use Digest::SHA qw(sha256_hex);
use Fcntl       qw(:flock);
chdir "$FindBin::Bin/.." or die $!;
make_path('build');
open my $lock, '>>', 'build/release.lock' or die $!;
flock( $lock, LOCK_EX | LOCK_NB ) or die "Another release preparation is running\n";
my $output = 'dist';
GetOptions( 'output=s' => \$output ) or die "Usage: perl script/release.pl [--output DIR]\n";
mkmanifest();
my $version = MM->parse_version('lib/Term/ReadLine/Gnu.pm');
my $name    = "Term-ReadLine-Gnu-$version";
system( 'nmake', '/nologo', 'metafile' ) == 0
    or die "Run perl Makefile.PL in the developer prompt first\n";

# MakeMaker may hard-link the distribution directory to the working tree.
# Read before writing so repeated release preparation also handles that case.
for my $format (qw(json yml)) {
    open my $source, '<:raw', "$name/META.$format" or die $!;
    my $data = do { local $/; <$source> };
    close $source or die $!;
    open my $target, '>:raw', "META.$format" or die $!;
    print {$target} $data or die $!;
    close $target         or die $!;
}
mkmanifest();
local $ENV{RELEASE_TESTING} = 1;
system {$^X} $^X, '-MTest::Harness', '-e', 'runtests(glob q(xt/*.t))';
die "Release checks failed\n" if $?;
my $tar      = Archive::Tar->new;
my $manifest = maniread();
for my $path ( sort keys %$manifest ) {
    die "Unsafe manifest entry: $path\n" if $path =~ m{(?:^|/)\.\.(?:/|$)|^[\\/]|:};
    open my $f, '<:raw', $path or die "$path: $!";
    local $/;
    my $data = <$f>;
    close $f or die "Cannot close file: $!";
    $tar->add_data(
        "$name/$path",
        $data,
        {
            mode  => ( $path =~ m{^script/} ? 0o755 : 0o644 ),
            uid   => 0,
            gid   => 0,
            uname => '',
            gname => '',
            mtime => ( $ENV{SOURCE_DATE_EPOCH} // time )
        }
    );
}
make_path($output);
my $archive = File::Spec->catfile( $output, "$name.tar.gz" );
$tar->write( $archive, Archive::Tar::COMPRESS_GZIP() ) or die "Cannot write $archive\n";
open my $f, '<:raw', $archive or die $!;
local $/;
my $sha = sha256_hex(<$f>);
close $f or die "Cannot close file: $!";
open my $sum, '>', "$archive.sha256" or die $!;
print {$sum} "$sha  $name.tar.gz\n";
close $sum or die "Cannot close file: $!";
print "Prepared $archive (not uploaded)\n";
