# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd        qw(abs_path);
my $home   = tempdir( CLEANUP => 1 );
my $script = abs_path('script/perlsh');
my $perl   = $^X;

sub run_repl ( $commands, $startup = '', $options = {} ) {
    open my $rc, '>:raw', "$home/.perlshrc" or die $!;
    print {$rc} $startup, <<'STARTUP' or die $!;
sub afterinit {
    $PerlSh::term->newTTY(\*STDIN, \*STDOUT);
    repl_probe() if defined &repl_probe;
}
STARTUP
    close $rc                 or die $!;
    unlink("$home/.perlshrc") or die $! if $options->{no_startup};
    local $ENV{HOME}        = $options->{fallback}                        ? undef : $home;
    local $ENV{USERPROFILE} = ( $options->{fallback} // '' ) eq 'profile' ? $home : undef;
    local $ENV{HOMEDRIVE} =
        ( $options->{fallback} // '' ) eq 'drive' ? substr( $home, 0, 2 ) : undef;
    local $ENV{HOMEPATH} = ( $options->{fallback} // '' ) eq 'drive' ? substr( $home, 2 ) : undef;
    local $ENV{GNU_PERLSH_TEST_MODE} = $options->{mode} // '';
    local $ENV{GNU_PERLSH_TEST_HOME} = $home;
    local $ENV{TERM}                 = 'win32';
    my $input_path  = "$home/input.txt";
    my $output_path = "$home/output.txt";
    open my $commands_file, '>:raw', $input_path or die $!;
    print {$commands_file} $commands or die $!;
    close $commands_file             or die $!;
    system {$perl} $perl, 't/native/perlsh-launch.pl', $input_path, $output_path, $script;
    my $status = $?;
    open my $result, '<:raw', $output_path or die $!;
    my $text = do { local $/; <$result> };
    close $result or die $!;
    return ( $status, $text );
}
my ( $status, $text ) = run_repl("1+2\n(4,5)\n1+\\\n2\ndie q(expected)\n6+1\n");
is( $status, 0, 'redirected REPL exits successfully at EOF' );
like( $text, qr/3\r?\n/,          'scalar evaluation result' );
like( $text, qr/4\r?\n5\r?\n/,    'list evaluation prints one value per line' );
like( $text, qr/Error: expected/, 'exception reported without terminating REPL' );
like( $text, qr/7\r?\n/,          'evaluation resumes after exception' );
ok( -f "$home/.perlsh_history", 'history saved in isolated home' );
( $status, $text ) = run_repl("\$unrestricted_value=42\n\$unrestricted_value\n");
is( $status, 0, 'default strictness accepts package variables' );
like( $text, qr/42/, 'default namespace retains assigned value' );
( $status, $text ) = run_repl( "\$undeclared_value=42\n", '$PerlSh::STRICT=1;' );
is( $status, 0, 'strict evaluation error does not terminate REPL' );
like(
    $text,
    qr/Global symbol.*undeclared_value/,
    'configured strictness rejects undeclared variables'
);
( $status, $text ) = run_repl("package ReplCoverage\nour \$value=9\n\$value\n");
is( $status, 0, 'package switching works' );
like( $text, qr/9/, 'evaluation uses switched package' );

# Completion routines are already compiled when the startup hook runs.
# Inspect results through the real completion adapter and report markers.
my $startup = <<'PERL';
our %coverage_hash = (apple => 1, apricot => 2, banana => 3);
our $coverage_ref = { %coverage_hash };
our @coverage_array = (1,2);
our $coverage_object = bless {}, 'ReplObject';
sub ReplObject::own_method { return 1; }
sub ReplParent::parent_method { return 2; }
@ReplObject::ISA = ('ReplParent');
sub repl_probe {
    my $a = $PerlSh::attribs;
    $a->{line_buffer} = '$coverage_hash{ap';
    $a->{point} = length($a->{line_buffer});
    my @keys = PerlSh::attempt_perl_completion('ap', '$coverage_hash{ap', 15, 17);
    print "KEYS:", join(',', sort @keys), "\n";
    $a->{line_buffer} = 'pri';
    $a->{point} = 3;
    my @symbols = PerlSh::attempt_perl_completion('pri', 'pri', 0, 3);
    print "SYMBOLS:", join(',', sort @symbols), "\n";
    print 'PROMPT:', PerlSh::prompt(sub { 'custom' }), "\n";
    for my $line ('$coverage_ref->{ap', '$main::coverage_ref->{ba', '$coverage_object->pa', '$main::coverage_object->ow') {
        my ($prefix) = $line =~ /(\w+)\z/;
        $a->{line_buffer} = $line;
        $a->{point} = length($line);
        my @matches = PerlSh::attempt_perl_completion($prefix, $line, length($line)-length($prefix), length($line));
        print 'COMPLETE:', $line, ':', join(',',sort @matches), "\n";
    }
    for my $prefix ('$coverage', '@coverage', '$#coverage', '%coverage', '&ReplObject::ow', 'ReplObject::ow') {
        $a->{line_buffer} = $prefix;
        $a->{point} = length($prefix);
        my @matches = PerlSh::attempt_perl_completion($prefix, $prefix, 0, length($prefix));
        print 'TYPED:', $prefix, ':', join(',',sort @matches), "\n";
    }
    my @display = ('main::first', '$main::second');
    PerlSh::perl_symbol_display_match_list(\@display,2,12);
    print 'DISPLAY:',join(',',@display),"\n";
    $PerlSh::HOSTNAME='host'; $PerlSh::LOGNAME='user';
    print 'ESCAPES:',PerlSh::prompt('\h/\u/\w'),"\n";
    $PerlSh::CWP='ReplObject';
    $a->{line_buffer}='ow'; $a->{point}=2;
    print 'PACKAGE:',join(',',PerlSh::attempt_perl_completion('ow','ow',0,2)),"\n";
    $PerlSh::CWP='main';
    PerlSh::sigint();
    print 'INTERRUPTED:',length($a->{line_buffer}),"\n";
}
PERL
( $status, $text ) = run_repl( '', $startup );
is( $status, 0, 'completion startup hook exits normally' );
like( $text, qr/KEYS:.*apple.*apricot/, 'hash completion enumerates matching keys' );
like( $text, qr/SYMBOLS:.*print/,       'symbol completion includes Perl keywords' );
like( $text, qr/PROMPT:custom/,         'callback prompt preserves return value' );
like( $text, qr/COMPLETE:.*coverage_ref.*apple.*apricot/,   'reference hash completion' );
like( $text, qr/COMPLETE:.*main::coverage_ref.*banana/,     'qualified reference hash completion' );
like( $text, qr/COMPLETE:.*coverage_object.*parent_method/, 'inherited method completion' );
like( $text, qr/TYPED:\@coverage:.*coverage_array/,         'array symbol completion' );
like( $text, qr/TYPED:.*coverage:.*coverage_hash/,          'hash symbol completion' );
like( $text, qr/TYPED:.*ReplObject::ow:.*own_method/,       'qualified function completion' );
like( $text, qr/DISPLAY:first,second/,                      'display strips package prefixes' );
like( $text, qr/ESCAPES:host\/user\/main/, 'prompt interpolates supported escapes' );
like( $text, qr/INTERRUPTED:0/,            'interrupt clears editing buffer' );
like(
    $text,
    qr/COMPLETE:.*main::coverage_object.*own_method/,
    'qualified object method completion'
);
like( $text, qr/PACKAGE:.*own_method/, 'unqualified symbols use current package' );

for my $fallback ( 'profile', 'drive' ) {
    ( $status, $text ) = run_repl( "2+3\n", '', { fallback => $fallback, no_startup => 1 } );
    is( $status, 0, "$fallback home fallback works without startup file" );
    like( $text, qr/5\r?\n/, "$fallback fallback evaluates input" );
}
( $status, $text ) = run_repl( '', '', { fallback => 'none' } );
ok( $status != 0, 'absent home is rejected' );
like( $text, qr/cannot determine home directory/, 'absent home diagnostic' );
( $status, $text ) = run_repl("1+\\\n2+\\\n3\n\n");
is( $status, 0, 'multiple continuation lines and blank input accepted' );
like( $text, qr/6\r?\n/, 'continuation lines concatenate in order' );
for my $mode ( 'history-read-fail', 'history-write-fail' ) {
    ( $status, $text ) = run_repl( '', '', { mode => $mode } );
    is( $status, 0, "$mode retains successful EOF exit" );
    like( $text, qr/cannot (?:read|write) history file/, "$mode reports expected warning" );
}
( $status, $text ) = run_repl( "2+3\n", '', { mode => 'unix-ok', fallback => 'unix' } );
is( $status, 0, 'legacy Unix adapter simulation accepts signal setup' );
like( $text, qr/5\r?\n/, 'legacy account lookup feeds startup and evaluation' );
( $status, $text ) = run_repl( '', '', { mode => 'unix-signal-fail', fallback => 'unix' } );
ok( $status != 0, 'legacy signal adapter failure is rejected' );
like( $text, qr/Error setting SIGINT handler/, 'legacy signal failure diagnostic' );
( $status, $text ) = run_repl(
    'join q{,}, $PerlSh::term->completion_matches(q{pri}, \&PerlSh::perl_symbol_completion_function)'
        . "\n" );
is( $status, 0, 'completion tables remain initialized after entering REPL' );
like( $text, qr/(?:\A|,)print(?:,|\r?\n)/, 'runtime completion retains keyword table' );
done_testing;
