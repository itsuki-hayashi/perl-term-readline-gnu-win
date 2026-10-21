# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use Config;
use ExtUtils::MakeMaker 7.78;
use lib 'inc';
use GnuWin32::Platform;
use GnuWin32::Toolchain;
use GnuWin32::Build;
die "OS unsupported: this distribution targets native Windows only\n" unless $^O eq 'MSWin32';
GnuWin32::Platform::validate(GnuWin32::Platform::current(), msvc => GnuWin32::Toolchain::compiler_version());
my $version=MM->parse_version('lib/Term/ReadLine/Gnu.pm');
WriteMakefile(
    NAME => 'Term::ReadLine::Gnu',
    DISTNAME => 'Term-ReadLine-GnuWin32',
    DIR => [],
    VERSION_FROM => 'lib/Term/ReadLine/Gnu.pm',
    ABSTRACT => 'Native GNU Readline for Windows 11 and MSVC Perl',
    AUTHOR => ['Itsuki Hayashi <2121340+itsuki-hayashi@users.noreply.github.com>'],
    LICENSE => 'gpl_3', MIN_PERL_VERSION => '5.044', PERL => $^X,
    CONFIGURE_REQUIRES => {'ExtUtils::MakeMaker'=>7.78, 'Win32'=>0},
    BUILD_REQUIRES => {'ExtUtils::MakeMaker'=>7.78, 'Digest::SHA'=>0, 'JSON::PP'=>0},
    TEST_REQUIRES => {'Test::More'=>1.302, 'File::Temp'=>0},
    PREREQ_PM => {'Term::ReadLine'=>1.17, 'Win32'=>0},
    XS => {'xs/GnuWin32.xs'=>'xs/GnuWin32.c'},
    OBJECT => 'xs/GnuWin32$(OBJ_EXT)',
    TYPEMAPS => ['xs/typemap'],
    PM => {'lib/Term/ReadLine/Gnu.pm'=>'$(INST_LIB)/Term/ReadLine/Gnu.pm',
           'lib/Term/ReadLine/Gnu/XS.pm'=>'$(INST_LIB)/Term/ReadLine/Gnu/XS.pm'},
    EXE_FILES => ['script/perlsh-gnu-win32'],
    INC => '-I"xs" -I"build/include"', DEFINE => '-DHAVE_STRING_H -DTRG_READLINE_VERSION=0x0803',
    MYEXTLIB => 'build/native/readline.lib', LIBS => ['-luser32'],
    clean => {FILES=>'build xs/*.xsc xs/*.obj xs/*.pdb GnuWin32.c GnuWin32.obj GnuWin32.def GnuWin32.exp GnuWin32.lib GnuWin32_def.old Gnu.def Gnu.exp Gnu.lib Gnu_def.old'},
    META_MERGE => {
        'meta-spec'=>{version=>2},
        provides=>{
            'Term::ReadLine::Gnu'=>{file=>'lib/Term/ReadLine/Gnu.pm',version=>$version},
            'Term::ReadLine::Gnu::XS'=>{file=>'lib/Term/ReadLine/Gnu/XS.pm',version=>$version},
            'Term::ReadLine::Gnu::Var'=>{file=>'lib/Term/ReadLine/Gnu.pm',version=>$version},
            'Term::ReadLine::Gnu::AU'=>{file=>'lib/Term/ReadLine/Gnu.pm',version=>$version},
        },
        resources=>{
            homepage=>'https://github.com/itsuki-hayashi/perl-term-readline-gnu-win',
            repository=>{type=>'git',url=>'https://github.com/itsuki-hayashi/perl-term-readline-gnu-win.git',web=>'https://github.com/itsuki-hayashi/perl-term-readline-gnu-win'},
            bugtracker=>{web=>'https://github.com/itsuki-hayashi/perl-term-readline-gnu-win/issues'},
        },
        no_index=>{directory=>[qw(vendor inc t xt examples script win32 patches docs xs)],namespace=>['Term::ReadLine::Gnu::Pointer']},
        x_distribution_channel=>'GitHub only; not for PAUSE upload',
        x_spdx_expression=>'GPL-3.0-or-later',
        x_support=>{os=>'MSWin32',client=>'Windows 11+',server=>'Windows Server 2025+ (CI)',
            architectures=>[qw(x64 arm64)],compiler=>'Visual C++ 2026 / v145+',crt=>'release shared /MD'},
        x_bundled=>{readline=>'8.3',upstream_perl_module=>'Term::ReadLine::Gnu 1.47'},
    },
);
sub MY::postamble {
    my $vendor=GnuWin32::Build::manifest();
    my @inputs=(qw(inc/build-native.pl inc/GnuWin32/Build.pm inc/GnuWin32/Patch.pm vendor/manifest.json),
        @{$vendor->{patches}}, map {"vendor/readline/$_"} sort keys %{$vendor->{files}});
    push @inputs, glob('win32/*.h'), glob('win32/*.c'), 't/native/native.c';
    my $dependencies="\nNATIVE_INPUTS = " . join(" \\\n    ", @inputs) . "\n";
    return $dependencies . <<'MAKE';


$(MYEXTLIB): $(NATIVE_INPUTS)
	$(FULLPERLRUN) "inc/build-native.pl"

xs/GnuWin32.c: xs/GnuWin32.xs
	$(XSUBPPRUN) $(XSPROTOARG) $(XSUBPPARGS) $(XSUBPP_EXTRA_ARGS) xs/GnuWin32.xs > xs/GnuWin32.xsc
	$(MV) xs/GnuWin32.xsc xs/GnuWin32.c

xs/GnuWin32$(OBJ_EXT): xs/GnuWin32.c $(MYEXTLIB) xs/ppport.h
	$(CCCMD) $(CCCDLFLAGS) "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) -Fo"xs/GnuWin32$(OBJ_EXT)" -Fd"xs/GnuWin32.pdb" xs/GnuWin32.c

MAKE
}
sub MY::dist_core {
    return <<'MAKE';
dist : tardist

tardist : FORCE
	$(FULLPERLRUN) "script/release.pl" --output .
MAKE
}
