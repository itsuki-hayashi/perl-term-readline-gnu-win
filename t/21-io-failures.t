# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Config qw(%Config);
use Test::More;
use File::Temp qw(tempdir);
use Symbol     qw(qualify_to_ref);
our %fault;

# Install overrides before helper compilation. They perform the real close /
# wait first, then inject a scoped failure only for the named helper package.
# This exercises diagnostics without leaking native handles or child processes.
BEGIN {
    *CORE::GLOBAL::open = sub : prototype(*;$@) {
        my $package = caller;
        if ( $package eq 'Gnu::Toolchain' && $fault{pipe_output} ) {
            my $text = $fault{pipe_output}->[ $fault{pipe_index}++ ];
            return CORE::open( $_[0], '<', \$text );
        }
        if ( $fault{open_package} && $package eq $fault{open_package} ) {
            return 0 if --$fault{open_count} == 0;
        }
        return CORE::open( $_[0], $_[1], $_[2], @_[ 3 .. $#_ ] ) if @_ > 3;
        return CORE::open( $_[0], $_[1], $_[2] ) if @_ == 3;
        return CORE::open( $_[0], $_[1] );
    };
    *CORE::GLOBAL::close = sub : prototype(*) ($handle) {
        my $package = caller;
        my $result  = CORE::close($handle);
        if ( $fault{close_package} && $package eq $fault{close_package} ) {
            if ( --$fault{close_count} == 0 ) { return 0; }
        }
        return $result;
    };
    *CORE::GLOBAL::sysread =
        sub : prototype(*\$$;$) ( $handle, $buffer, $length, $offset = undef ) {
        my $package = caller;
        if ( $fault{read_package} && $package eq $fault{read_package} ) {

            return undef;
        }
        return defined $offset
            ? CORE::sysread( $handle, $$buffer, $length, $offset )
            : CORE::sysread( $handle, $$buffer, $length );
        };
    *CORE::GLOBAL::waitpid = sub : prototype($$) ( $pid, $flags ) {
        my $package = caller;
        my $result  = CORE::waitpid( $pid, $flags );
        return -1 if $fault{wait_package} && $package eq $fault{wait_package};
        return $result;
    };
}
use lib 'inc';
use Gnu::Build   ();
use Gnu::Patch   ();
use Gnu::Command ();
use Gnu::Quality ();
my $work = tempdir( CLEANUP => 1 );

sub write_file ( $path, $text ) {
    open my $file, '>:raw', $path or die $!;
    print {$file} $text or die $!;
    close $file         or die $!;
}

sub fails ( $code, $pattern, $description ) {
    my $ok = eval { $code->(); 1 };
    %fault = ();
    ok( !$ok, $description );
    like( $@, $pattern, "$description diagnostic" );
}
write_file( "$work/data", "data\n" );
for my $list_context ( 0, 1 ) {
    %fault = ( close_package => 'Gnu::Build', close_count => 1 );
    fails(
        sub {
            if ($list_context) { my @data = Gnu::Build::slurp("$work/data"); return \@data; }
            return scalar Gnu::Build::slurp("$work/data");
        },
        qr/data:/,
        "slurp close failure context $list_context"
    );
}
write_file( "$work/source.c",     "old\n" );
write_file( "$work/change.patch", "--- a/source.c\n+++ b/source.c\n@@ -1 +1 @@\n-old\n+new\n" );
for my $number ( 1 .. 3 ) {
    write_file( "$work/source.c", "old\n" );
    %fault = ( close_package => 'Gnu::Patch', close_count => $number );
    fails( sub { Gnu::Patch::apply( $work, "$work/change.patch" ) },
        qr/./, "patch close failure $number" );
}
write_file( "$work/child.pl", 'print "child output\n";' );
for my $package ( 'Gnu::Command', 'Gnu::Quality' ) {
    my $run =
        $package eq 'Gnu::Command'
        ? sub { Gnu::Command::run_logged( "$work/child.log", $^X, "$work/child.pl" ) }
        : sub { Gnu::Quality::capture( $^X, "$work/child.pl" ) };
    for my $number ( 1 .. ( $package eq 'Gnu::Command' ? 3 : 2 ) ) {
        %fault = ( close_package => $package, close_count => $number );
        fails( $run, qr/Cannot close/, "$package close failure $number" );
    }
    {
        %fault = ( read_package => $package );
        fails( $run, qr/Cannot read/, "$package read failure" );
    }
}
{
    %fault = ( wait_package => 'Gnu::Quality' );
    fails(
        sub { Gnu::Quality::capture( $^X, "$work/child.pl" ) },
        qr/Cannot wait/,
        'capture wait failure'
    );
}
fails( sub { Gnu::Command::run_logged( "$work/missing/path.log", $^X, "$work/child.pl" ) },
    qr/path.log:/, 'log open failure' );
write_file( "$work/source.c", "old\n" );
%fault = ( open_package => 'Gnu::Patch', open_count => 3 );
fails( sub { Gnu::Patch::apply( $work, "$work/change.patch" ) },
    qr/./, 'patch output open failure' );
if ( $ENV{AUTHOR_TESTING} ) {
    require Gnu::Toolchain;
    {
        local %ENV = %ENV;
        Gnu::Toolchain::activate();
        for my $operation ( 'open', 'close' ) {
            for my $number ( 1 .. ( $operation eq 'close' ? 3 : 2 ) ) {
                %fault = (
                    "${operation}_package" => 'Gnu::Toolchain',
                    "${operation}_count"   => $number
                );
                fails(
                    sub { Gnu::Toolchain::activate() },
                    qr/failed|initialize|Died|directory|operation/,
                    "toolchain activation $operation failure $number"
                );
            }
        }
        %fault = ( open_package => 'Gnu::Toolchain', open_count => 1 );
        fails(
            sub { Gnu::Toolchain::compiler_version() },
            qr/Cannot run cl/,
            'compiler pipe open failure'
        );
        for my $arch ( 'x64', 'arm64' ) {
            my $config_slot = qualify_to_ref('Gnu::Toolchain::Config');
            local *{$config_slot} = { %Config, archname => "MSWin32-$arch-multi-thread" };
            local $ENV{PROCESSOR_ARCHITECTURE} = $arch eq 'arm64' ? 'ARM64' : 'AMD64';
            %fault = (
                pipe_output => [ "C:/VS fixture\n", "not an assignment\nGNU_SIMULATED=covered\n" ],
                pipe_index  => 0
            );
            is(
                Gnu::Toolchain::activate(),
                'C:/VS fixture',
                "$arch environment adapter simulation"
            );
            is( $ENV{GNU_SIMULATED}, 'covered', 'only environment assignments imported' );
            %fault = ();
        }
    }
    require Perl::Critic;
    require PPI;
    my $critic = Perl::Critic->new( -profile => '.perlcriticrc', '-profile-strictness' => 'fatal' );
    my $source = "use v5.44;\nuse strict;\nuse warnings;\n";
    for my $operation ( 'open', 'close' ) {
        for my $number ( 1, 2 ) {
            %fault = ( "${operation}_package" => 'Gnu::Quality', "${operation}_count" => $number );
            fails( sub { Gnu::Quality::inspect( 'fixture.pl', $source, $critic, '.perltidyrc' ) },
                qr/Cannot/, "POD $operation failure $number" );
        }
    }
    {
        my $constructor = qualify_to_ref('PPI::Document::new');
        local *{$constructor} = sub { return undef; };
        fails(
            sub { Gnu::Quality::inspect( 'fixture.pl', $source, $critic, '.perltidyrc' ) },
            qr/Cannot parse/,
            'PPI constructor failure'
        );
    }
}
done_testing;
