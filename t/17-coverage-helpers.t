# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp  qw(tempdir);
use File::Path  qw(make_path);
use Cwd         qw(getcwd);
use File::Copy  ();
use Digest::SHA qw(sha256_hex);
use lib 'inc';
use Gnu::Build    ();
use Gnu::Platform ();
use Gnu::Patch    ();
use Gnu::Quality  ();

sub write_file ( $path, $text ) {
    open my $file, '>:raw', $path or die $!;
    print {$file} $text or die $!;
    close $file         or die $!;
}

sub fails ( $code, $pattern, $description ) {
    my $ok = eval { $code->(); 1 };
    ok( !$ok, $description );
    like( $@, $pattern, "$description diagnostic" );
}
my $root = getcwd();
my $work = tempdir( CLEANUP => 1 );
fails( sub { Gnu::Build::slurp("$work/missing") }, qr/missing:/, 'missing input fails' );
Gnu::Build::run( $^X, '-e', 'exit 0' );
fails( sub { Gnu::Build::run( $^X, '-e', 'exit 7' ) }, qr/Command failed/, 'build child failure' );
my %current = Gnu::Platform::current();
is( $current{os},      'MSWin32', 'current OS is native Windows' );
is( $current{ptrsize}, 8,         'current pointer width is supported' );
my $child = "$work/child with spaces.pl";
write_file( $child, 'print "out"; warn "err\n"; exit 9' );
my ( $status, $output ) = Gnu::Quality::capture( $^X, $child );
ok( $status != 0, 'capture preserves unsuccessful exit' );
like( $output, qr/out/, 'capture keeps stdout' );
like( $output, qr/err/, 'capture keeps stderr' );
my ( $missing_status, $missing_output ) = Gnu::Quality::capture( $^X, "$work/missing.pl" );
ok( $missing_status != 0, 'missing child source fails' );
like( $missing_output, qr/missing.pl/, 'missing child diagnostic retained' );
fails(
    sub { Gnu::Quality::analysis_source( 'lib/Term/ReadLine/Gnu/XS.pm', '1;' ) },
    qr/Missing AutoLoader/,
    'missing AutoLoader boundary'
);
is( Gnu::Quality::analysis_source( 'normal.pl', '__END__' ),
    '__END__', 'ordinary data boundary remains' );

my $patch = "$work/input.patch";
fails( sub { Gnu::Patch::apply( $work, "$work/missing.patch" ) },
    qr/missing.patch/, 'missing patch fails' );
for my $case (
    [ '',                      qr/No supported hunks/,                           'empty patch' ],
    [ "@@ -1 +1 @@\n-a\n+b\n", qr/Hunk without file/,                            'orphan hunk' ],
    [ "--- a/missing.c\n+++ b/missing.c\n@@ -1 +1 @@\n-a\n+b\n", qr/missing.c:/, 'missing source' ],
    [
        "--- a/input.c\n+++ b/input.c\n@@ -1 +1 @@\n?bad\n", qr/Invalid hunk/,
        'invalid hunk marker'
    ],
    [
        "--- a/input.c\n+++ b/input.c\n@@ -1 +1 @@\n-a\n+b\n@@ -1 +1 @@\n-a\n+c\n",
        qr/Out-of-order/, 'overlapping hunks'
    ],
    )
{
    write_file( "$work/input.c", "a\n" );
    write_file( $patch,          $case->[0] );
    fails( sub { Gnu::Patch::apply( $work, $patch ) }, $case->[1], $case->[2] );
}

# Build copies and cache decisions are tested in an isolated miniature vendor
# tree. Commands are recorded here; the native suite exercises real MSVC output.
chdir $work or die $!;
make_path( 'vendor/readline', 'win32' );
my @headers = qw(readline.h chardefs.h keymaps.h history.h tilde.h rlstdc.h rlconf.h rltypedefs.h);
my @names =
    qw(readline vi_mode funmap keymaps parens search rltty complete bind isearch display signals util kill undo macro input callback terminal text nls misc history histexpand histfile histsearch shell mbutil tilde colors parse-colors xmalloc xfree compat gettimeofday);
my %files = map { $_ => sha256_hex("fixture\n") } ( @headers, map { "$_.c" } @names );
write_file( "vendor/readline/$_", "fixture\n" ) for keys %files;
write_file( "win32/$_.c",         "fixture\n" ) for qw(compat termcap console);
my @commands;
{
    local *Gnu::Build::manifest = sub { return { files => \%files, patches => [] }; };
    local *Gnu::Build::run      = sub {
        push @commands, [@_];
        for my $arg (@_) {
            write_file( $1, 'object' ) if $arg =~ m{^/Fo(.+)};
        }
    };
    ok( Gnu::Build::verify_vendor(), 'miniature pristine vendor verifies' );
    Gnu::Build::native();
    is( scalar( grep { $_->[0] eq 'lib' } @commands ), 2, 'both static libraries requested' );
    ok( -f 'build/include/readline/readline.h', 'public headers staged' );
    my $first = scalar @commands;
    @commands = ();
    Gnu::Build::native();
    is( scalar @commands,
        3, 'fresh objects skip compilation while libraries and native test relink' );
    ok( $first > @commands, 'first build compiled missing objects' );

    for my $prefix ( 'vendor/readline/', 'build/readline/' ) {
        local *Gnu::Build::copy = sub {
            return 0 if index( $_[0], $prefix ) == 0;
            return File::Copy::copy(@_);
        };
        fails( sub { Gnu::Build::prepare() }, qr/./, "copy failure from $prefix" );
    }
    write_file( 'vendor/readline/readline.h', 'changed' );
    fails( sub { Gnu::Build::verify_vendor() }, qr/checksum mismatch/, 'modified vendor rejected' );
    write_file( 'vendor/readline/readline.h', "fixture\n" );
    write_file( 'vendor/readline/unexpected', 'extra' );
    fails(
        sub { Gnu::Build::verify_vendor() },
        qr/Unexpected vendor file/,
        'unknown vendor rejected'
    );
}
chdir $root or die $!;
done_testing;
