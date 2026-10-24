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
use JSON::PP    qw(decode_json);
use Digest::SHA qw(sha256_hex);
use lib 'inc';
use Gnu::Quality ();
use Gnu::Build   ();

# Keep staged sources with the coverage evidence until its databases are read.
# Both tools write exclusively into this disposable tree, never real vendor.
make_path('build/quality');
my $stage = abs_path( tempdir( 'script-tests-XXXX', DIR => 'build/quality', CLEANUP => 0 ) );
make_path( "$stage/script", "$stage/inc/Gnu", "$stage/vendor/readline/doc" );
for my $name (qw(Build Patch)) {
    copy( "inc/Gnu/$name.pm", "$stage/inc/Gnu/$name.pm" ) or die $!;
}
for my $name (qw(update-readline audit-licenses)) {
    copy( "script/$name.pl", "$stage/script/$name.pl" ) or die $!;
}

sub write_file ( $path, $text ) {
    open my $file, '>:raw', $path or die $!;
    print {$file} $text or die $!;
    close $file         or die $!;
}
write_file( "$stage/vendor/manifest.json", '{"readline":{"patches":[],"files":{}}}' );

sub update_case ( $expected, $pattern, $label, @arguments ) {
    my ( $status, $text ) =
        Gnu::Quality::capture( $^X, "$stage/script/update-readline.pl", @arguments );
    is( $status == 0 ? 1 : 0, $expected, $label );
    like( $text, $pattern, "$label diagnostic" );
    return $text;
}
update_case( 0, qr/Provide --archive/, 'missing update arguments' );
update_case( 0, qr/Invalid options/, 'unknown update option', '--unknown' );
update_case(
    0,
    qr/Invalid version or checksum/,
    'invalid version',
    '--archive', 'unused', '--version', 'bad', '--sha256', 'f' x 64, '--url',
    'https://example.invalid/source'
);
my %required = (
    archive => 'unused',
    version => '9.0',
    sha256  => 'f' x 64,
    url     => 'https://example.invalid/source'
);
for my $missing ( sort keys %required ) {
    my @arguments = map { ( "--$_", $required{$_} ) } grep { $_ ne $missing } sort keys %required;
    update_case( 0, qr/Provide --archive/, "missing required $missing", @arguments );
}
my $archive = "$stage/source.tar.gz";

sub archive_file ($path) {
    my $tar = Archive::Tar->new;
    $tar->add_data( 'readline-9.0/directory/', '', { type => 5 } );
    $tar->add_data( $path, "fixture\n" );
    $tar->write( $archive, Archive::Tar::COMPRESS_GZIP() ) or die 'Cannot write archive';
    return sha256_hex( Gnu::Build::slurp($archive) );
}
my $sha = archive_file('readline-9.0/source.c');
my @options =
    ( '--archive', $archive, '--version', '9.0', '--url', 'https://example.invalid/source' );
update_case( 0, qr/checksum mismatch/, 'wrong archive checksum', @options, '--sha256', '0' x 64 );
my $text = update_case(
    1,
    qr/Verified candidate:/,
    'valid offline update candidate',
    @options, '--sha256', $sha
);
my ($candidate) = $text =~ /Verified candidate: ([^\r\n]+)/;
my $manifest = decode_json( Gnu::Build::slurp("$stage/$candidate/manifest.json") );
is( $manifest->{readline}{version},           '9.0', 'candidate manifest version' );
is( $manifest->{readline}{files}{'source.c'}, sha256_hex("fixture\n"), 'candidate file checksum' );
is_deeply( $manifest->{readline}{patches}, [], 'existing patch order retained' );
$sha = archive_file('unexpected/source.c');
update_case( 0, qr/Unexpected archive root/, 'unexpected archive root', @options, '--sha256',
    $sha );
$sha = archive_file('readline-9.0/C:outside.c');
update_case( 0, qr/Unsafe archive path/, 'unsafe archive member', @options, '--sha256', $sha );
write_file( $archive, 'not a tar archive' );
$sha = sha256_hex( Gnu::Build::slurp($archive) );
update_case( 0, qr/Cannot read/, 'malformed authenticated archive', @options, '--sha256', $sha );
write_file( "$stage/vendor/readline/plain.c",
    "Copyright example\nno notice\nPermission granted\n" );
write_file( "$stage/vendor/readline/binary",           "a\0b" );
write_file( "$stage/vendor/readline/doc/readline.pdf", 'fixture' );
write_file( "$stage/vendor/readline/doc/history.ps",   'fixture' );
write_file( "$stage/vendor/readline/long.c", join( '', map { "Copyright $_\n" } 1 .. 40 ) );
write_file( "$stage/vendor/manifest.json",
    '{"readline":{"files":{"plain.c":"plain","binary":"binary","doc/readline.pdf":"pdf","doc/history.ps":"ps","long.c":"long"}}}'
);
my ( $status, $output ) = Gnu::Quality::capture( $^X, "$stage/script/audit-licenses.pl" );
is( $status, 0, 'license audit succeeds on isolated fixtures' );
like( $output, qr/5 pristine upstream files/, 'license inventory count' );
my $inventory = decode_json( Gnu::Build::slurp("$stage/docs/licensing/vendor-inventory.json") );
is( scalar $inventory->{'plain.c'}{notice_evidence}->@*, 2, 'text notice evidence captured' );
like( $inventory->{binary}{note}, qr/Binary upstream/, 'binary notice policy retained' );
is(
    $inventory->{'doc/readline.pdf'}{notice_source},
    'vendor/readline/doc/rlman.texi',
    'generated manual references master source'
);

is( scalar $inventory->{'long.c'}{notice_evidence}->@*,
    30, 'notice evidence is capped at 30 lines' );
is(
    $inventory->{'doc/history.ps'}{notice_source},
    'vendor/readline/doc/history.texi',
    'other generated manuals use matching source'
);
for my $name ( 'update-readline', 'audit-licenses' ) {
    $sha = archive_file('readline-9.0/source.c') if $name eq 'update-readline';
    my @arguments = $name eq 'update-readline' ? ( @options, '--sha256', $sha ) : ();
    my $script    = "$stage/script/$name.pl";
    for my $operation ( 'chdir', 'open', 'close', 'write' ) {
        my $count = $name eq 'update-readline' && $operation ne 'chdir' ? 2 : 1;
        for my $number ( 1 .. $count ) {
            my ( $exit, $diagnostic ) = Gnu::Quality::capture( $^X, 't/native/script-faults.pl',
                $script, $operation, $number, @arguments );
            ok( $exit != 0, "$name $operation failure $number is rejected" );
            like( $diagnostic, qr/[.]pl line [0-9]+/, "$name $operation failure has a diagnostic" );
        }
    }
}
done_testing;
