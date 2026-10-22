#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/../build/author/lib/perl5";
use lib "$FindBin::Bin/../inc";
use Cwd            qw(abs_path getcwd);
use File::Temp     qw(tempdir);
use File::Path     qw(make_path);
use File::Copy     qw(copy);
use File::Basename qw(dirname);
use JSON::PP       qw(decode_json);
use version        ();
use Perl::Critic   ();
use Gnu::Build     ();
use Gnu::Quality   ();

my $root = abs_path("$FindBin::Bin/..");
chdir $root or die "Cannot enter checkout: $!";
my $tools = decode_json( Gnu::Build::slurp('config/author-tools.json') );
for my ( $module, $version ) ( $tools->{required}->%* ) {

    # Names come from the reviewed, committed author-tool inventory.
    ( my $file = "$module.pm" ) =~ s{::}{/}g;
    require $file;
    my $installed = $module->VERSION;
    die "$module $version required, found $installed\n"
        unless version->parse($installed) == version->parse($version);
}
my $critic = Perl::Critic->new(
    -profile              => "$root/.perlcriticrc",
    '-profile-strictness' => 'fatal',
);
my @files = Gnu::Quality::sources($root);
make_path('build/quality');
open my $report, '>:raw', 'build/quality/perl.txt' or die "Cannot write report: $!";
print {$report} "Perl $^V\nPolicies:\n", map { ref($_) . "\n" } $critic->policies
    or die "Cannot write policy report: $!";
my @errors;
my $stage = tempdir( 'perl-quality-XXXX', TMPDIR => 1, CLEANUP => 1 );
my @autoload;

for my $path (@files) {
    my $text = Gnu::Build::slurp($path);
    push @errors, Gnu::Quality::inspect( $path, $text, $critic, "$root/.perltidyrc" );
    my $target = "$stage/$path";
    make_path( dirname($target) );
    copy( $path, $target ) or die "Cannot stage $path: $!";
    if ( $path eq 'lib/Term/ReadLine/Gnu/XS.pm' ) {

        # Compile routines in the actual AutoSplit scope, rather than changing
        # their lexical scope by concatenating them into the module preamble.
        my ( undef, $body ) = split /^__END__\r?$/m, $text, 2;
        @autoload = $body =~ /^sub\s+(\w+)/mg;
        require AutoSplit;
        make_path("$stage/lib/auto");
        AutoSplit::autosplit( $target, "$stage/lib/auto", 0, 1, 0 );
    }
}
local $ENV{PERL_RL} = 'Gnu';
local $ENV{TERM}    = 'win32';
local $ENV{INPUTRC} = 'NUL';

# A script file avoids Windows command-line re-parsing of quoted -e source.
open my $loader, '>:raw', "$stage/compile-backend.pl" or die $!;
print {$loader} <<'PERL' or die $!;
use strict;
use warnings;
use Term::ReadLine;
use AutoLoader ();
die "Wrong backend\n" unless Term::ReadLine->ReadLine eq 'Term::ReadLine::Gnu';
AutoLoader::autoload_sub("Term::ReadLine::Gnu::XS::$_") for @ARGV;
PERL
close $loader or die $!;
chdir $stage  or die "Cannot enter staging directory: $!";
for my $path (@files) {

    # Loading the staged backend through its real entry point compiles both
    # modules without compiling a second copy over already-loaded symbols.
    my @action =
        $path =~ m{^lib/Term/ReadLine/Gnu(?:/XS)?\.pm\z}
        ? ( "$stage/compile-backend.pl", @autoload )
        : ( '-c', "$stage/$path" );

    # Compile-time actions execute only in this disposable staging tree.
    my ( $status, $output ) =
        Gnu::Quality::capture( $^X, "-I$stage/lib", "-I$root/blib/lib", "-I$root/blib/arch",
        "-I$stage/inc", "-I$root/build/author/lib/perl5", @action, );
    print {$report} "$path: compile status $status\n$output"
        or die "Cannot write compile report: $!";
    push @errors, "$path: compilation failed ($status)\n$output" if $status;
    ( my $diagnostics = $output ) =~ s/^\Q$stage\/$path\E syntax OK\r?\n//mg;
    push @errors, "$path: unexpected compilation diagnostics\n$diagnostics"
        if !$status && length $diagnostics;
}
chdir $root or die "Cannot return to checkout: $!";
print {$report} @errors, @errors ? "FAIL\n" : "PASS\n" or die "Cannot write quality result: $!";
close $report or die "Cannot close quality report: $!";
die @errors if @errors;
print scalar(@files), " Perl sources passed formatting, Critic, POD and compilation.\n";
