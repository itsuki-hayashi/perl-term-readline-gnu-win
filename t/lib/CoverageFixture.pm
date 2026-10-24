# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package CoverageFixture;
use v5.44;
use strict;
use warnings;
use Symbol   qw(qualify_to_ref);
use JSON::PP ();
use lib 'inc';
use Gnu::Quality     ();
use Gnu::Toolchain   ();
use Devel::Cover::DB ();

# Only the disposable runner subprocess installs these substitutions. Real
# calibration, native commands and reports are exercised by --integration.
sub run ( $scenario, $code ) {
    my @calls;
    my $capture = qualify_to_ref('Gnu::Quality::capture');
    local *{$capture} = sub {
        push @calls, [@_];
        warn "fixture warning\n" if $scenario eq 'warning' && @calls == 1;
        return ( 1,   'probe failed' )           if $scenario eq 'probe-fails'  && @calls == 1;
        return ( 0,   "wrong\n" )                if $scenario eq 'probe-output' && @calls == 1;
        return ( 0,   "10\n" )                   if @calls == 1;
        return ( 256, 'fixture child failed' )   if $scenario eq 'tests-fail'    && @calls == 2;
        return ( 256, 'fixture command failed' ) if $scenario eq 'command-fails' && @calls == 3;
        return ( 0,   "fixture succeeded\n" );
    };
    my $activate = qualify_to_ref('Gnu::Toolchain::activate');
    local *{$activate} = sub { return 'fixture compiler'; };
    my $inventory = qualify_to_ref('Gnu::Quality::coverage_sources');
    local *{$inventory} = sub { return ('script/coverage-perl.pl'); };
    my $constructor = qualify_to_ref('Devel::Cover::DB::new');
    local *{$constructor} = sub {
        my ( undef, %options ) = @_;
        return CoverageFixture::Database->new( $scenario, $options{db} );
    };
    my $result = eval { $code->() };
    my $error  = $@;
    open my $trace, '>:raw', $ENV{GNU_COVER_FIXTURE_TRACE} or die $!;
    print {$trace} JSON::PP->new->encode( \@calls ) or die $!;
    close $trace                                    or die $!;
    die $error if length $error;
    return $result;
}

package CoverageFixture::Database;
use v5.44;
use strict;
use warnings;

sub new ( $class, $scenario, $path ) {
    my $probe = $path =~ /calibration-db\z/;
    my $missed =
        ( !$probe && $scenario eq 'partial' ) || ( $probe && $scenario eq 'bad-calibration' );
    my $statement = { covered => 1, total => 1, percentage => 100 };
    my $branch    = { covered => $missed ? 1 : 2, total => 2, percentage => $missed ? 50 : 100 };
    if ( !$probe && $scenario eq 'wrong-denominator' ) {
        $branch = { covered => 1, total => 1, percentage => 100 };
    }
    my $measurements = { statement => $statement, branch => $branch };
    my $file         = 'script/coverage-perl.pl';
    my $summary =
        { Total => $measurements, $file => $measurements, 'unrelated.pm' => $measurements };
    $summary = { Total => $measurements } if !$probe && $scenario eq 'no-project';
    my $cover = {
        $file => {
            statement => { 1 => [ CoverageFixture::Site->new( 1, 1 ) ] },
            branch    =>
                { 2 => [ CoverageFixture::Site->new( $branch->{covered}, $branch->{total} ) ] },
        }
    };

    if ( !$probe && $scenario eq 'no-branches' ) {
        delete $measurements->{branch};
        delete $cover->{$file}{branch};
    }
    if ( !$probe && $scenario eq 'missing-metric' ) {
        delete $measurements->{statement};
    }
    if ( !$probe && $scenario eq 'partial-statement' ) {
        $measurements->{statement} = { covered => 1, total => 2, percentage => 50 };
        $cover->{$file}{statement}{3} = [ CoverageFixture::Site->new( 0, 1 ) ];
    }
    if ( !$probe && $scenario eq 'excluded-site' ) {
        $measurements->{branch}{uncoverable} = 1;
        $cover->{$file}{branch}{2} = [ CoverageFixture::Site->new( 2, 2, 1 ) ];
    }
    return bless { summary => $summary, cover => $cover }, $class;
}
sub merge_runs        ($self)             { return $self; }
sub calculate_summary ( $self, @ignored ) { return $self; }

sub summary ( $self, $file, $criterion = undef ) {
    return defined $criterion ? $self->{summary}{$file}{$criterion} : $self->{summary}{$file};
}
sub cover ($self) { return $self->{cover}; }

package CoverageFixture::Site;
use v5.44;
use strict;
use warnings;

sub new ( $class, $covered, $total, $uncoverable = 0 ) {
    return bless { covered => $covered, total => $total, uncoverable => $uncoverable }, $class;
}
sub covered     ($self) { return $self->{covered}; }
sub total       ($self) { return $self->{total}; }
sub error       ($self) { return $self->{total} - $self->{covered}; }
sub uncoverable ($self) { return $self->{uncoverable}; }
sub text        ($self) { return 'fixture branch'; }
1;
