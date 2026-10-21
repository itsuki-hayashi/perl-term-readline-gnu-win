# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use lib 'inc';
use Gnu::Patch;
use Gnu::Command;
my $dir=tempdir(CLEANUP=>1);
sub write_file { my ($p,$s)=@_; open my $f,'>:raw',$p or die $!; print {$f} $s; close $f; }
sub read_file { open my $f,'<:raw',$_[0] or die $!; local $/; return <$f>; }
my $source=File::Spec->catfile($dir,'example.c');
my $patch=File::Spec->catfile($dir,'example.patch');
write_file($source,"first\nsecond\n");
write_file($patch,"--- a/example.c\n+++ b/example.c\n@@ -1,2 +1,2 @@\n first\n-second\n+changed\n");
Gnu::Patch::apply($dir,$patch);
is(read_file($source),"first\nchanged\n",'exact patch applies');
ok(!eval {Gnu::Patch::apply($dir,$patch);1},'mismatched baseline is rejected');
like($@,qr/Patch mismatch/,'mismatch diagnostic');
write_file($patch,"--- a/../outside\n+++ b/../outside\n@@ -1 +1 @@\n-a\n+b\n");
ok(!eval {Gnu::Patch::apply($dir,$patch);1},'path traversal rejected');
write_file($patch,"--- /dev/null\n+++ b/new.c\n@@ -0,0 +1 @@\n+new\n");
ok(!eval {Gnu::Patch::apply($dir,$patch);1},'unsupported patch operation fails explicitly');
my $child=File::Spec->catfile($dir,'child with spaces.pl');
my $marker=File::Spec->catfile($dir,'executed.txt');
my $log=File::Spec->catfile($dir,'child.log');
write_file($child,q{open my $f,'>',$ARGV[0] or die $!; print $f 'ran'; close $f; print "stdout\n"; warn "stderr\n"; exit 3;});
ok(!eval {Gnu::Command::run_logged($log,$^X,$child,$marker);1},'logged command propagates failure');
like($@,qr/Command failed/,'child status diagnostic');
is(read_file($marker),'ran','child actually executed with a spaced path');
like(read_file($log),qr/stdout/,'stdout logged');
like(read_file($log),qr/stderr/,'stderr logged');
done_testing;
