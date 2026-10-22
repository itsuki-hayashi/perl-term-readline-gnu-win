# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec ();
use lib 'inc';
use Gnu::Patch   ();
use Gnu::Command ();
use Gnu::Build   ();
my $dir = tempdir( CLEANUP => 1 );

sub write_file {
    my ( $p, $s ) = @_;
    open my $f, '>:raw', $p or die $!;
    print {$f} $s;
    close $f or die "Cannot close file: $!";
}
sub read_file { open my $f, '<:raw', $_[0] or die $!; local $/; return <$f>; }
my $source = File::Spec->catfile( $dir, 'example.c' );
my $patch  = File::Spec->catfile( $dir, 'example.patch' );
write_file( $source, "first\nsecond\n" );
write_file( $patch,
    "--- a/example.c\n+++ b/example.c\n@@ -1,2 +1,2 @@\n first\n-second\n+changed\n" );
Gnu::Patch::apply( $dir, $patch );
is( read_file($source), "first\nchanged\n", 'exact patch applies' );
ok( !eval { Gnu::Patch::apply( $dir, $patch ); 1 }, 'mismatched baseline is rejected' );    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval) -- The test or callback checks the resulting exception through $@.
like( $@, qr/Patch mismatch/, 'mismatch diagnostic' );
write_file( $patch, "--- a/../outside\n+++ b/../outside\n@@ -1 +1 @@\n-a\n+b\n" );
ok( !eval { Gnu::Patch::apply( $dir, $patch ); 1 }, 'path traversal rejected' );            ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval) -- The test or callback checks the resulting exception through $@.
write_file( $patch, "--- /dev/null\n+++ b/new.c\n@@ -0,0 +1 @@\n+new\n" );
ok(
    !eval { Gnu::Patch::apply( $dir, $patch ); 1 },                                         ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval) -- The test or callback checks the resulting exception through $@.
    'unsupported patch operation fails explicitly'
);
my $child  = File::Spec->catfile( $dir, 'child with spaces.pl' );
my $marker = File::Spec->catfile( $dir, 'executed.txt' );
my $log    = File::Spec->catfile( $dir, 'child.log' );
write_file( $child,
    q{open my $f,'>',$ARGV[0] or die $!; print {$f} 'ran'; close $f or die "Cannot close file: $!"; print "stdout\n"; warn "stderr\n"; exit 3;}
);
ok(
    !eval { Gnu::Command::run_logged( $log, $^X, $child, $marker ); 1 },                    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval) -- The test or callback checks the resulting exception through $@.
    'logged command propagates failure'
);
like( $@, qr/Command failed/, 'child status diagnostic' );
is( read_file($marker), 'ran', 'child actually executed with a spaced path' );
like( read_file($log), qr/stdout/, 'stdout logged' );
like( read_file($log), qr/stderr/, 'stderr logged' );

# Exercise context, insertion, deletion, multiple hunks and multiple files
# through the public parser after extracting its private hunk helper.
my $other = File::Spec->catfile( $dir, 'other.c' );
write_file( $source, "one\ntwo\nthree\nfour\nfive\n" );
write_file( $other,  "old\n" );
write_file( $patch,
    "--- a/example.c\n+++ b/example.c\n@@ -1,2 +1,3 @@\n one\n-two\n+TWO\n+inserted\n@@ -4,1 +5,0 @@\n-four\n--- a/other.c\n+++ b/other.c\n@@ -1 +1 @@\n-old\n+new\n"
);
Gnu::Patch::apply( $dir, $patch );
is( read_file($source), "one\nTWO\ninserted\nthree\nfive\n", 'multiple hunks preserve context' );
is( read_file($other),  "new\n", 'switching files saves the previous result' );
write_file( $patch, "--- a/example.c\n+++ b/example.c\n@@ -1 +1 @@\n" );
my $truncated = eval { Gnu::Patch::apply( $dir, $patch ); 1 };
ok( !$truncated, 'truncated hunk fails' );
like( $@, qr/Truncated patch/, 'truncated hunk diagnostic is preserved' );
write_file( $child, q{print "success\n"; exit 0;} );
Gnu::Command::run_logged( $log, $^X, $child );
like( read_file($log), qr/success/, 'successful commands append output' );
my $empty = File::Spec->catfile( $dir, 'empty.txt' );
write_file( $empty, '' );
is( scalar Gnu::Build::slurp($empty), '', 'empty slurp preserves the scalar empty string' );
is_deeply( [ Gnu::Build::slurp($empty) ], [], 'empty slurp preserves an empty list' );
write_file( $empty, "one\ntwo\n" );
is_deeply( [ Gnu::Build::slurp($empty) ], ["one\ntwo\n"],
    'slurp still returns the whole raw file' );
done_testing;
