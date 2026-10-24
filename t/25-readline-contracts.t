# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
BEGIN { $ENV{PERL_RL} = 'Gnu'; $ENV{TERM} = 'win32'; }    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Backend selection precedes import in this isolated fixture.
use Term::ReadLine;
{

    package ReadlineCoverage;
    use parent -norequire, 'Term::ReadLine::Gnu';

    sub rl_readline {
        my ( $self, $prompt ) = @_;
        $self->{test_prompt} = $prompt;
        $self->{startup_hook}->() if defined $self->{startup_hook};
        return $self->{test_line};
    }
    sub rl_insert_text              { $_[0]->{test_insert} = $_[1]; }
    sub history_expand              { return $_[0]->{test_expansion}->@*; }
    sub add_history                 { push $_[0]->{test_history}->@*, $_[1]; }
    sub register_Tk                 { $_[0]->{test_tk}++; }
    sub rl_callback_handler_install { $_[0]->{test_callback} = [ @_[ 1, 2 ] ]; }
}
my ($output) = tempfile();
for my $result ( -1, 0, 1, 2 ) {
    local *Term::ReadLine::Gnu::Attribs = {
        term_set                 => [ '<', '>' ],
        outstream                => $output,
        test_line                => 'original',
        test_expansion           => [ $result, 'expanded' ],
        do_expand                => 1,
        MinLength                => 3,
        completion_function      => sub { return 'legacy'; },
        _trp_completion_function => sub { return 'adapter'; },
    };
    my $term = bless \%Term::ReadLine::Gnu::Attribs, 'ReadlineCoverage';
    my $line = $term->readline('prompt');
    is(
        $line,
        $result < 0 || $result == 2 ? '' : 'expanded',
        "expansion status $result controls result"
    );
    is( $term->{test_prompt},                      '<prompt>', 'prompt ornaments forwarded' );
    is( ref( $term->{completion_entry_function} ), 'CODE', 'legacy completion adapter installed' );
    is(
        scalar( ( $term->{test_history} // [] )->@* ),
        $result < 0 || $result == 2 ? 0 : 1,
        'only accepted expansions enter history'
    );
}
for my $minimum ( undef, 0, 3, 9 ) {
    local *Term::ReadLine::Gnu::Attribs =
        { term_set => [ '', '' ], outstream => $output, test_line => 'abc', MinLength => $minimum };
    my $term    = bless \%Term::ReadLine::Gnu::Attribs, 'ReadlineCoverage';
    my $startup = 0;
    $term->{startup_hook} = sub { $startup++; };
    is( $term->readline( 'prompt', 'prefix' ), 'abc',    'preput preserves returned line' );
    is( $term->{test_insert},                  'prefix', 'startup inserts preput' );
    is( $startup,                              1,        'existing startup callback invoked' );
    is(
        scalar( ( $term->{test_history} // [] )->@* ),
        defined($minimum) && $minimum > 0 && $minimum <= 3 ? 1 : 0,
        'history minimum enforced'
    );
    delete $term->{startup_hook};
    is( $term->readline( 'prompt', 'prefix' ), 'abc', 'preput without previous startup callback' );
    $term->{test_line} = undef;
    is( $term->readline('prompt'), undef, 'EOF remains undef' );
}
{
    local *Term::ReadLine::Gnu::Attribs = {
        term_set                 => [ '', '' ],
        outstream                => $output,
        test_line                => '',
        Tk_getc                  => sub { return 0; },
        completion_function      => sub { return 'legacy'; },
        _trp_completion_function => sub { return 'adapter'; },
    };
    my $term = bless \%Term::ReadLine::Gnu::Attribs, 'ReadlineCoverage';
    local $Term::ReadLine::registered = 0;
    local $Term::ReadLine::toloop     = 1;
    local *Tk::DoOneEvent             = sub { return 0; };
    is( $term->readline('prompt'), '', 'Tk adapter preserves empty line' );
    is( $term->{test_tk},          1,  'Tk registration delegated' );
    delete $term->{completion_entry_function};
    my $callback = sub { return 'line'; };
    $term->CallbackHandlerInstall( 'callback', $callback );
    is( $term->{_callback_handler}, $callback,  'callback identity retained' );
    is( $term->{test_callback}[0],  'callback', 'callback prompt forwarded' );
    is( ref( $term->{completion_entry_function} ),
        'CODE', 'callback installs compatibility completion adapter' );
    $term->CallbackHandlerInstall( 'second', $callback );
    is( $term->{test_callback}[0],
        'second', 'callback can be replaced with adapter already present' );
    delete $term->{completion_function};
    delete $term->{completion_entry_function};
    $term->CallbackHandlerInstall( 'third', $callback );
    is( $term->{completion_entry_function},
        undef, 'callback without completion stays unconfigured' );
}
close $output or die $!;
done_testing;
