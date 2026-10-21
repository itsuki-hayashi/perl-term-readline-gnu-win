#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path getcwd);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Archive::Tar;
use Config;
chdir "$FindBin::Bin/.." or die $!;
use lib "$FindBin::Bin/../inc";
use GnuWin32::Toolchain;
use GnuWin32::Command;
GnuWin32::Toolchain::activate();
local $ENV{LC_ALL}='C';
local $ENV{PERL5LIB}; delete $ENV{PERL5LIB};
my @archives=sort glob('dist/Term-ReadLine-GnuWin32-*.tar.gz');
die "Expected exactly one candidate archive in dist/\n" unless @archives==1;
my $archive=abs_path($archives[0]);
my $log=abs_path('build').'/archive-tests.log';
my $work=abs_path(tempdir('archive with spaces XXXX',DIR=>'build'));
my $tar=Archive::Tar->new($archive,1);
my %top;
for my $entry ($tar->get_files) {
    my $path=$entry->full_path;
    die "Unsafe archive member: $path\n" if $path =~ m{(?:^|/)\.\.(?:/|$)|^[\\/]|:} || $entry->is_symlink || $entry->is_hardlink;
    $top{(split m{/},$path)[0]}=1;
}
die "Expected one distribution directory\n" unless keys(%top)==1;
chdir $work or die $!; $tar->extract() or die 'Cannot extract archive';
my ($name)=keys %top; chdir $name or die $!;
my $installed="$work/installed with spaces";
sub run { GnuWin32::Command::run_logged($log,@_); }
run($^X,'Makefile.PL',"INSTALL_BASE=$installed");
run('nmake','/nologo'); run('nmake','/nologo','test'); run('nmake','/nologo','install');
my $dll="$installed/lib/perl5/$Config{archname}/auto/Term/ReadLine/GnuWin32/GnuWin32.dll";
open my $imports,'-|','dumpbin','/nologo','/dependents',$dll or die $!;
local $/; my $dependencies=<$imports>; close $imports or die 'Cannot inspect installed extension';
open my $report,'>','../dependencies.txt' or die $!; print {$report} $dependencies; close $report;
die 'Forbidden runtime dependency' if $dependencies =~ /cygwin|msys-2|libgcc|libstdc\+\+|libwinpthread/i;
$ENV{PERL5LIB}="$installed/lib/perl5/$Config{archname};$installed/lib/perl5";
$ENV{PERL_RL}='GnuWin32';
make_path("$work/outside-source"); chdir "$work/outside-source" or die $!;
open my $smoke,'>','installed-smoke.pl' or die $!;
print {$smoke} <<'SMOKE';
    use strict;
    use warnings;
    use Term::ReadLine;
    use File::Temp qw(tempfile);
    die 'Wrong backend' unless Term::ReadLine->ReadLine eq 'Term::ReadLine::GnuWin32';
    die 'Loaded from source tree' unless $INC{'Term/ReadLine/GnuWin32.pm'} =~ /installed with spaces/;
    my ($in)=tempfile(); my ($out)=tempfile(); print $in "installed\n"; seek($in,0,0);
    my $t=Term::ReadLine->new('installed archive',$in,$out);
    die 'Installed readline failed' unless $t->readline('') eq 'installed';
    my $before=$t->Attribs->{history_length};
    $t->add_history('autoload'); die 'Installed history failed' unless $t->Attribs->{history_length} == $before + 1;
    open my $result,'>','installed-smoke-result.txt' or die $!;
    print {$result} "PASS: $INC{'Term/ReadLine/GnuWin32.pm'}\n";
    close $result or die $!;
    print "Installed CPAN archive smoke test passed\n";
SMOKE
close $smoke or die $!;
run($^X,'installed-smoke.pl');
die 'Installed smoke test did not produce evidence' unless -s 'installed-smoke-result.txt';
print "Archive build, tests, staged installation and DLL imports verified in $work\n";
