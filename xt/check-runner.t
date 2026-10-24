# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
plan skip_all => 'Set AUTHOR_TESTING=1 for checker integration fixtures'
    unless $ENV{AUTHOR_TESTING};
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd        qw(abs_path);
use JSON::PP   qw(decode_json encode_json);
use lib 'inc';
use Gnu::Build   ();
use Gnu::Quality ();
make_path('build/quality');
my $root = abs_path( tempdir( 'checker-tests-XXXX', DIR => 'build/quality', CLEANUP => 0 ) );
make_path( map { "$root/$_" } qw(lib inc/Gnu script t xt config build/author/lib/perl5) );

for my $file (
    qw(.perlcriticrc .perltidyrc config/author-tools.json Makefile.PL script/perlsh script/check-perl.pl)
    )
{
    copy( $file, "$root/$file" ) or die $!;
}
for my $file ( glob('inc/Gnu/*.pm') ) { copy( $file, "$root/$file" ) or die $!; }

sub write_file ( $path, $text ) {
    open my $file, '>:raw', $path or die $!;
    print {$file} $text or die $!;
    close $file         or die $!;
}
write_file( "$root/t/missing-module.t",
    "use v5.44;\nuse strict;\nuse warnings;\nuse Fixture::Intentionally::Missing ();\n" );
write_file( "$root/t/compiler-warning.t",
    "use v5.44;\nuse strict;\nuse warnings;\nBEGIN { warn qq(fixture compiler warning\\n); }\n" );

sub run_case ( $scenario, $operation, $number, $pattern ) {
    local $ENV{GNU_TOOL_FIXTURE_SCENARIO} = $scenario;
    local $ENV{GNU_TOOL_FIXTURE_TRACE}    = "$root/trace.json";
    my ( $status, $output ) = Gnu::Quality::capture( $^X, 't/native/script-faults.pl',
        "$root/script/check-perl.pl", $operation, $number );
    ok( $status != 0, "checker rejects $scenario $operation $number" );
    like( $output, $pattern, 'checker failure is explained' );
}
run_case( 'complete', 'none', 0, qr/compilation failed/ );
my $report = Gnu::Build::slurp("$root/build/quality/perl.txt");
like(
    $report,
    qr/unexpected compilation diagnostics/,
    'successful compile with warnings is rejected'
);
like( $report, qr/fixture compiler warning/, 'compiler warning retained' );
run_case( 'copy-fails', 'none', 0, qr/Cannot stage/ );
for my $operation ( 'open', 'close', 'write' ) {
    for my $number ( 1, 2 ) {
        run_case( 'complete', $operation, $number, qr/[.]pl line [0-9]+/ );
    }
}
for my $number ( 1, 2, 3 ) {
    run_case( 'complete', 'chdir', $number, qr/Cannot (?:enter|return)/ );
}
run_case( 'complete', 'after-close', 1, qr/Cannot write compile report/ );
run_case( 'complete', 'after-chdir', 3, qr/Cannot write quality result/ );
my $tools = decode_json( Gnu::Build::slurp('config/author-tools.json') );
$tools->{required} = { 'JSON::PP' => '999.0' };
write_file( "$root/config/author-tools.json", encode_json($tools) );
run_case( 'complete', 'none', 0, qr/JSON::PP 999[.]0 required/ );
copy( 'config/author-tools.json', "$root/config/author-tools.json" ) or die $!;
write_file( "$root/.perlcriticrc", "[Fixture::UnknownPolicy]\n" );
run_case( 'complete', 'none', 0, qr/(?:UnknownPolicy|not installed)/ );
done_testing;
