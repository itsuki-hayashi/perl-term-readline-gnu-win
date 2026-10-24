# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd        qw(abs_path);
use Archive::Tar;
use Digest::SHA        qw(sha256_hex);
use ExtUtils::Manifest qw(maniread);
use ExtUtils::MakeMaker;
use Fcntl    qw(:flock);
use JSON::PP qw(decode_json);
use lib 'inc';
use Gnu::Build   ();
use Gnu::Quality ();
make_path('build/quality');

# Keep nested installation fixtures below Win32 path limits in extracted trees.
my $outer        = abs_path( tempdir( 'rXXXX', DIR => 'build', CLEANUP => 0 ) );
my $version      = MM->parse_version('lib/Term/ReadLine/Gnu.pm');
my $distribution = "Term-ReadLine-Gnu-$version";

sub write_file ( $path, $text ) {
    open my $file, '>:raw', $path or die $!;
    print {$file} $text or die $!;
    close $file         or die $!;
}

sub stage ( $name, $script ) {
    my $root = "$outer/$name";
    make_path( "$root/script", "$root/lib/Term/ReadLine", "$root/build/bin", "$root/xt",
        "$root/dist" );
    copy( "script/$script.pl",        "$root/script/$script.pl" )        or die $!;
    copy( 'lib/Term/ReadLine/Gnu.pm', "$root/lib/Term/ReadLine/Gnu.pm" ) or die $!;
    copy( 'MANIFEST.SKIP',            "$root/MANIFEST.SKIP" )            or die $!;
    return $root;
}

sub run_case (
    $root, $script, $scenario, $expected, $pattern,
    $operation = 'none',
    $number    = 0, @arguments
    )
{
    my $native_path = $ENV{PATH} // '';

    # Win32 Perl searches executable suffixes before falling back to .bat.
    # Remove real compiler-tool directories so fixtures select their own batches
    # even when this suite runs inside a Native Tools archive installation.
    local $ENV{PATH} = join ';', "$root/build/bin",
        grep { !-f "$_/nmake.exe" && !-f "$_/dumpbin.exe" } split /;/, $native_path;
    local $ENV{GNU_TOOL_FIXTURE_SCENARIO} = $scenario;
    local $ENV{GNU_TOOL_FIXTURE_TRACE}    = "$outer/trace.json";
    local $ENV{SOURCE_DATE_EPOCH}         = $scenario eq 'epoch' ? 123 : undef;
    my ( $status, $output ) = Gnu::Quality::capture( $^X, 't/native/script-faults.pl',
        "$root/script/$script.pl", $operation, $number, @arguments );
    is( $status == 0 ? 1 : 0, $expected, "$script $scenario $operation $number" );
    like( $output, $pattern, "$script diagnostic" );
    return $output;
}
my $release = stage( 'r', 'release' );
write_file( "$release/build/bin/meta.json", '{"name":"fixture","version":"1"}' );
write_file( "$release/build/bin/meta.yml",  "---\nname: fixture\nversion: 1\n" );
write_file( "$release/xt/fixture.t",
    'use Test::More; ok(($ENV{GNU_TOOL_FIXTURE_SCENARIO}//q()) ne q(tests-fail),q(fixture)); done_testing;'
);
write_file( "$release/build/bin/nmake.bat",
    "\@echo off\nif \"%GNU_TOOL_FIXTURE_SCENARIO%\"==\"metadata-fails\" exit /b 7\nif not exist \"$distribution\" mkdir \"$distribution\"\ncopy /y \"%~dp0meta.json\" \"$distribution\\META.json\" >nul\nif errorlevel 1 exit /b 1\ncopy /y \"%~dp0meta.yml\" \"$distribution\\META.yml\" >nul\nexit /b %errorlevel%\n"
);
run_case( $release, 'release', 'complete', 1, qr/Prepared .*tar[.]gz/ );
my $tar = Archive::Tar->new( "$release/dist/$distribution.tar.gz", 1 );
ok( $tar->contains_file("$distribution/lib/Term/ReadLine/Gnu.pm"),
    'release preserves source member names' );
my $sum             = Gnu::Build::slurp("$release/dist/$distribution.tar.gz.sha256");
my $expected_digest = sha256_hex( Gnu::Build::slurp("$release/dist/$distribution.tar.gz") );
like( $sum, qr/\A\Q$expected_digest\E/, 'release checksum authenticates archive' );
run_case( $release, 'release', 'epoch', 1, qr/Prepared/ );
$tar = Archive::Tar->new( "$release/dist/$distribution.tar.gz", 1 );
is_deeply(
    [ sort { $a <=> $b } map { $_->mtime } $tar->get_files ],
    [ (123) x scalar( $tar->get_files ) ],
    'source epoch applied to every archive member'
);
run_case( $release, 'release', 'metadata-fails', 0, qr/developer prompt/ );
run_case( $release, 'release', 'tests-fail',     0, qr/Release checks failed/ );
run_case( $release, 'release', 'complete',       0, qr/Usage:/, 'none', 0, '--unknown' );
{
    open my $lock, '>>', "$release/build/release.lock" or die $!;
    flock( $lock, LOCK_EX | LOCK_NB ) or die $!;
    run_case( $release, 'release', 'complete', 0, qr/Another release preparation/ );
    close $lock or die $!;
}
my $manifest = Gnu::Build::slurp("$release/MANIFEST");
write_file( "$release/MANIFEST", $manifest . "../outside\n" );
run_case( $release, 'release', 'complete', 0, qr/Unsafe manifest entry/ );
write_file( "$release/MANIFEST", $manifest . "missing-input.txt\n" );
run_case( $release, 'release', 'complete', 0, qr/missing-input[.]txt:/ );
write_file( "$release/MANIFEST", $manifest );
my $count = scalar keys maniread("$release/MANIFEST")->%*;

for my $number ( 1, 2, 3, 6, $count + 6, $count + 7 ) {
    run_case( $release, 'release', 'complete', 0, qr/[.]pl line [0-9]+/, 'open', $number );
}
for my $number ( 1, 2, 5, $count + 5, $count + 6 ) {
    run_case( $release, 'release', 'complete', 0, qr/[.]pl line [0-9]+/, 'close', $number );
}
for my $number ( 3, $count + 7 ) {
    run_case( $release, 'release', 'complete', 0, qr/[.]pl line [0-9]+/, 'write', $number );
}
run_case( $release, 'release', 'complete', 0, qr/[.]pl line [0-9]+/, 'chdir', 1 );
unlink("$release/dist/$distribution.tar.gz") or die $!;
mkdir("$release/dist/$distribution.tar.gz")  or die $!;
run_case( $release, 'release', 'complete', 0, qr/Cannot write .*tar[.]gz/ );
rmdir("$release/dist/$distribution.tar.gz") or die $!;

my $archive = stage( 'a', 'test-archive' );
write_file( "$archive/build/bin/dumpbin.bat",
    "\@echo off\nif \"%GNU_TOOL_FIXTURE_SCENARIO%\"==\"dumpbin-fails\" exit /b 7\nif not exist \"%~3\" exit /b 9\nif \"%GNU_TOOL_FIXTURE_SCENARIO%\"==\"forbidden-runtime\" (echo libgcc.dll) else (echo KERNEL32.dll)\nexit /b 0\n"
);

sub archive_fixture ($kind) {
    my $fixture = Archive::Tar->new;
    if ( $kind eq 'two-roots' ) {
        $fixture->add_data( 'one/file', 'fixture' );
        $fixture->add_data( 'two/file', 'fixture' );
    }
    elsif ( $kind eq 'empty' ) {

        # An empty archive must not be accepted as a distribution.
    }
    elsif ( $kind eq 'unsafe' ) {
        $fixture->add_data( 'pkg/C:unsafe', 'fixture' );
    }
    elsif ( $kind eq 'symlink' || $kind eq 'hardlink' ) {
        $fixture->add_data( 'pkg/link', '',
            { type => $kind eq 'symlink' ? 2 : 1, linkname => 'outside' } );
    }
    elsif ( $kind eq 'root-file' ) {
        $fixture->add_data( 'pkg', 'fixture' );
    }
    elsif ( $kind eq 'extract-fails' ) {
        $fixture->add_data( 'pkg',          'fixture' );
        $fixture->add_data( 'pkg/sub/file', 'fixture' );
    }
    else {
        $fixture->add_data( 'pkg/Makefile.PL', 'fixture' );
    }
    $fixture->write( "$archive/dist/$distribution.tar.gz", Archive::Tar::COMPRESS_GZIP() )
        or die 'Cannot stage archive';
}
archive_fixture('valid');
run_case( $archive, 'test-archive', 'complete', 1, qr/DLL imports verified/ );
my $calls = decode_json( Gnu::Build::slurp("$outer/trace.json") );
is( scalar $calls->@*, 5, 'archive performs configure, build, test, install and installed smoke' );
like(
    $calls->[0][-1],
    qr/INSTALL_BASE=.*installed with spaces/,
    'installation prefix includes spaces'
);
for my $case (
    [ 'empty',         qr/Cannot read/ ],
    [ 'two-roots',     qr/Expected one distribution directory/ ],
    [ 'unsafe',        qr/Unsafe archive member/ ],
    [ 'symlink',       qr/Unsafe archive member/ ],
    [ 'hardlink',      qr/Unsafe archive member/ ],
    [ 'root-file',     qr/[.]pl line [0-9]+/ ],
    [ 'extract-fails', qr/Cannot extract archive/ ],
    )
{
    archive_fixture( $case->[0] );
    run_case( $archive, 'test-archive', 'complete', 0, $case->[1] );
}
archive_fixture('valid');
for my $case (
    [ 'command-fails',     qr/fixture command failed/ ],
    [ 'dumpbin-fails',     qr/Cannot inspect installed extension/ ],
    [ 'forbidden-runtime', qr/Forbidden runtime dependency/ ],
    [ 'no-evidence',       qr/Installed smoke test did not produce evidence/ ],
    )
{
    run_case( $archive, 'test-archive', $case->[0], 0, $case->[1] );
}
for my $operation ( 'open', 'close' ) {
    for my $number ( 1 .. 3 ) {
        run_case( $archive, 'test-archive', 'complete', 0, qr/[.]pl line [0-9]+/,
            $operation, $number );
    }
}
for my $number ( 2, 3 ) {
    run_case( $archive, 'test-archive', 'complete', 0, qr/[.]pl line [0-9]+/, 'write', $number );
}
for my $number ( 1, 2, 3, 4 ) {
    run_case( $archive, 'test-archive', 'complete', 0, qr/[.]pl line [0-9]+/, 'chdir', $number );
}
unlink("$archive/dist/$distribution.tar.gz") or die $!;
rmdir("$archive/dist")                       or die $!;
run_case( $archive, 'test-archive', 'complete', 0, qr/Run script\/release[.]pl first/ );
done_testing;
