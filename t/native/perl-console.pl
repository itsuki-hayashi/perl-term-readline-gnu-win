use v5.44;
use strict;
use warnings;
use utf8;
use Encode qw(encode);
use IO::Handle;
BEGIN { delete $ENV{PERL_RL}; $ENV{TERM} = 'win32'; $ENV{INPUTRC} = 'NUL'; }    ## no critic (Variables::RequireLocalizedPunctuationVars, Variables::RequireLocalizedPunctuationVars) -- Process-wide initialization or persistent stream state is intentional.
use Term::ReadLine;
open my $log, '>', $ARGV[0] or die $!;
$log->autoflush(1);
my $t = Term::ReadLine->new('MSVC integration');
die 'Wrong backend' unless $t->ReadLine eq 'Term::ReadLine::Gnu';
die 'Wrong library' unless $t->Attribs->{library_version} eq '8.3';
$t->enableUTF8();
my $s = $t->readline('Perl Unicode> ');
die 'Unicode editing failed: ' . encode( 'UTF-8', $s // 'undef' ) unless defined($s) && $s eq "x日🐪";
print {$log} "Perl Unicode editing passed\n";
$t->add_history('previous');
$s = $t->readline('Perl history> ');
die 'History editing failed' unless defined($s) && $s eq 'revious';
print {$log} "Perl history editing passed\n";
my $callback;
$t->callback_handler_install( 'Perl callback> ', sub { $callback = shift; } );
$t->callback_read_char() until defined $callback;
$t->callback_handler_remove();
die 'Callback failed' unless $callback eq 'ok';
print {$log} "Perl callback passed\n";
require CPAN;
require CPAN::Complete;
{
    no warnings qw(redefine once);    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- Only the named category is suppressed for intentional symbol replacement.
    local $CPAN::Config_loaded     = 1;
    local $CPAN::Suppress_readline = 0;
    local $CPAN::Config            = {};
    local $CPAN::term              = $t;
    local *CPAN::checklock         = sub { die "completion initialized\n" };
    eval { CPAN::shell() };           ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval) -- The test or callback checks the resulting exception through $@.
    die "CPAN initialization failed: $@" unless $@ eq "completion initialized\n";
    $s = $t->readline('CPAN completion> ');
    die 'CPAN TAB completion failed: ' . ( $s // 'undef' )
        unless defined($s) && $s =~ /^install_tested\s*$/;
    print {$log} "CPAN command TAB completion passed\n";
}
close $log or die $!;
