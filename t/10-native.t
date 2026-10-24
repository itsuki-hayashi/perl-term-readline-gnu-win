# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use Cwd        qw(abs_path getcwd);
use File::Spec ();
my $root = getcwd();
my $exe  = abs_path('build/native/native-tests.exe');
BAIL_OUT('Native test executable was not built') unless $exe;
my @libraries = qw(blib/arch blib/lib);

# Native console children replace PERL5LIB to select this build. Preserve only
# the pinned author library when the coverage runner instruments those children.
push @libraries, 'build/author/lib/perl5'
    if ( $ENV{PERL5OPT} // '' ) =~ /Devel::Cover/;
local $ENV{PERL5LIB}       = join ';', map { abs_path($_) } @libraries;
local $ENV{RL_TEST_PERL}   = $^X;
local $ENV{RL_TEST_SCRIPT} = abs_path('t/native/perl-console.pl');
local $ENV{RL_TEST_PERLSH} = abs_path('blib/script/perlsh.bat');
local $ENV{INPUTRC}        = 'NUL';
local $ENV{TERM}           = 'win32';
chdir 'build/native' or die $!;

for my $case (
    ['C and console'],
    [ 'Perl console',  '--perl' ],
    [ 'debugger',      '--debugger' ],
    [ 'REPL launcher', '--perlsh' ]
    )
{
    my ( $name, @args ) = @$case;
    system {$exe} $exe, @args;
    is( $?, 0, $name );
}
chdir $root or die $!;
done_testing;
