#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use FindBin    ();
use Cwd        qw(abs_path getcwd);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Archive::Tar;
use Config qw(%Config);
use ExtUtils::MakeMaker;
chdir "$FindBin::Bin/.." or die $!;
use lib "$FindBin::Bin/../inc";
use Gnu::Toolchain ();
use Gnu::Command   ();
Gnu::Toolchain::activate();
local $ENV{LC_ALL} = 'C';
local $ENV{PERL5LIB};
delete $ENV{PERL5LIB};
my $version = MM->parse_version('lib/Term/ReadLine/Gnu.pm');
my $archive = abs_path("dist/Term-ReadLine-Gnu-$version.tar.gz")
    or die 'Run script/release.pl first';
my $log  = abs_path('build') . '/archive-tests.log';
my $work = abs_path( tempdir( 'archive with spaces XXXX', DIR => 'build' ) );
my $tar  = Archive::Tar->new( $archive, 1 );
my %top;

for my $entry ( $tar->get_files ) {
    my $path = $entry->full_path;
    die "Unsafe archive member: $path\n"
        if $path =~ m{(?:^|/)\.\.(?:/|$)|^[\\/]|:} || $entry->is_symlink || $entry->is_hardlink;
    $top{ ( split m{/}, $path )[0] } = 1;
}
die "Expected one distribution directory\n" unless keys(%top) == 1;
chdir $work     or die $!;
$tar->extract() or die 'Cannot extract archive';
my ($name) = keys %top;
chdir $name or die $!;
my $installed = "$work/installed with spaces";
sub run { Gnu::Command::run_logged( $log, @_ ); }
run( $^X,     'Makefile.PL', "INSTALL_BASE=$installed" );
run( 'nmake', '/nologo' );
run( 'nmake', '/nologo', 'test' );
run( 'nmake', '/nologo', 'install' );
my $dll = "$installed/lib/perl5/$Config{archname}/auto/Term/ReadLine/Gnu/Gnu.dll";
open my $imports, '-|', 'dumpbin', '/nologo', '/dependents', $dll or die $!;
local $/;
my $dependencies = <$imports>;
close $imports or die 'Cannot inspect installed extension';
open my $report, '>', '../dependencies.txt' or die $!;
print {$report} $dependencies;
close $report or die "Cannot close file: $!";
die 'Forbidden runtime dependency'
    if $dependencies =~ /cygwin|msys-2|libgcc|libstdc\+\+|libwinpthread/i;
$ENV{PERL5LIB} = "$installed/lib/perl5/$Config{archname};$installed/lib/perl5";    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional.
delete $ENV{PERL_RL};
make_path("$work/outside-source");
chdir "$work/outside-source" or die $!;
open my $smoke, '>', 'installed-smoke.pl' or die $!;
print {$smoke} <<'SMOKE';
    use strict;
    use warnings;
    use Term::ReadLine;
    use File::Temp qw(tempfile);
    die 'Wrong backend' unless Term::ReadLine->ReadLine eq 'Term::ReadLine::Gnu';
    die 'Loaded from source tree' unless $INC{'Term/ReadLine/Gnu.pm'} =~ /installed with spaces/;
    my ($in)=tempfile(); my ($out)=tempfile(); print {$in} "installed\n"; seek($in,0,0);
    my $t=Term::ReadLine->new('installed archive',$in,$out);
    die 'Installed readline failed' unless $t->readline('') eq 'installed';
    my $before=$t->Attribs->{history_length};
    $t->add_history('autoload'); die 'Installed history failed' unless $t->Attribs->{history_length} == $before + 1;
    open my $result,'>','installed-smoke-result.txt' or die $!;
    print {$result} "PASS: $INC{'Term/ReadLine/Gnu.pm'}\n";
    close $result or die $!;
    print "Installed GitHub archive smoke test passed\n";
SMOKE
close $smoke or die $!;
run( $^X, 'installed-smoke.pl' );
die 'Installed smoke test did not produce evidence' unless -s 'installed-smoke-result.txt';
print "Archive build, tests, temporary installation and DLL imports verified in $work\n";
