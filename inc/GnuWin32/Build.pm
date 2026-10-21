# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package GnuWin32::Build;
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Spec;
use File::Find;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use GnuWin32::Patch;
sub slurp { open my $f, '<:raw', $_[0] or die "$_[0]: $!"; local $/; return <$f>; }
sub run { print join(' ', @_), "\n"; system {$_[0]} @_ ; die "Command failed ($?): @_\n" if $?; }
sub manifest { return decode_json(slurp('vendor/manifest.json'))->{readline}; }
sub verify_vendor {
    my $m = manifest();
    for my $file (sort keys %{$m->{files}}) {
        die "Pristine vendor checksum mismatch: $file\n" unless sha256_hex(slurp("vendor/readline/$file")) eq $m->{files}{$file};
    }
    my %known = %{$m->{files}};
    find({ no_chdir=>1, wanted=>sub {
        return unless -f $_;
        (my $rel=$_) =~ s{^vendor/readline/}{};
        die "Unexpected vendor file: $rel\n" unless exists $known{$rel};
    }},'vendor/readline');
    return 1;
}
sub prepare {
    verify_vendor();
    my $m=manifest();
    for my $file (keys %{$m->{files}}) {
        my $out="build/readline/$file"; (my $dir=$out)=~s{/[^/]+$}{};
        make_path($dir); copy("vendor/readline/$file",$out) or die $!;
    }
    GnuWin32::Patch::apply('build/readline', $_) for @{$m->{patches}};
    make_path('build/include/readline');
    for my $h (qw(readline.h chardefs.h keymaps.h history.h tilde.h rlstdc.h rlconf.h rltypedefs.h)) {
        copy("build/readline/$h","build/include/readline/$h") or die $!;
    }
}
sub native {
    prepare(); make_path('build/native');
    my @names=qw(readline vi_mode funmap keymaps parens search rltty complete bind isearch display signals util kill undo macro input callback terminal text nls misc history histexpand histfile histsearch shell mbutil tilde colors parse-colors xmalloc xfree compat gettimeofday);
    my @headers=(glob('win32/*.h'),glob('build/readline/*.h'));
    my @objects;
    for my $pair ((map { ["build/readline/$_.c", "build/native/$_.obj"] } @names),
        (map { ["win32/$_.c", "build/native/win_$_.obj"] } qw(compat termcap console))) {
        my ($src,$obj)=@$pair;
        my $newest = (sort {$b <=> $a} map {(stat($_))[9]} $src, @headers)[0];
        run('cl','/nologo','/c','/std:c11','/MD','/O2','/W3','/DHAVE_CONFIG_H','/Iwin32','/Ibuild/readline',"/Fo$obj",$src)
            unless -f $obj && (stat($obj))[9] >= $newest;
        push @objects,$obj;
    }
    run('lib','/nologo','/OUT:build/native/readline.lib',@objects);
    run('lib','/nologo','/OUT:build/native/history.lib',map {"build/native/$_.obj"} qw(history histexpand histfile histsearch shell mbutil xmalloc xfree win_compat));
    run('cl','/nologo','/std:c11','/MD','/O2','/W3','/Iwin32','/Ibuild/readline','/Fobuild/native/native-tests.obj','/Febuild/native/native-tests.exe','t/native/native.c','build/native/readline.lib','user32.lib');
}
1;
