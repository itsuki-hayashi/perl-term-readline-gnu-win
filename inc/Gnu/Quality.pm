# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package Gnu::Quality;
use v5.44;
use strict;
use warnings;
use File::Find qw(find);
use File::Spec ();
use IPC::Open3 qw(open3);
use Gnu::Build ();

# This inventory deliberately excludes vendor, generated code and examples.
sub sources ($root) {
    my @files = qw(Makefile.PL script/perlsh);
    for my $dir (qw(lib inc script t xt)) {
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    return unless -f $_ && /\.(?:pm|pl|t)\z/;
                    my $name = File::Spec->abs2rel( $_, $root );
                    $name =~ tr{\\}{/};
                    push @files, $name;
                }
            },
            File::Spec->catdir( $root, $dir )
        );
    }
    return sort @files;    ## no critic (Subroutines::ProhibitReturnSort) -- Source discovery is an explicitly list-valued internal interface.
}

# Tests are executed but are not part of the production coverage denominator.
# Reuse lint discovery so newly added helpers and extensionless perlsh cannot
# silently disappear from the coverage inventory.
sub coverage_sources ($root) {
    return grep { !m{\A(?:t|xt)/} } sources($root);
}

# Devel::Cover merges byte-identical copies by digest and may retain the
# absolute filename of a staged or installed copy as its canonical name.
# Map such copies only after comparing bytes with a discovered source.
sub coverage_source_name ( $root, $file, $targets ) {
    my $path = $file;
    $path =~ tr{\\}{/};
    for my $target ( $targets->@* ) {
        next
            unless $path eq $target
            || $path =~ m{/(?:blib/)?\Q$target\E\z}
            || $path eq "blib/$target";
        my $original = File::Spec->catfile( $root, $target );
        next unless -f $file && -f $original;
        return $target if Gnu::Build::slurp($file) eq Gnu::Build::slurp($original);
    }
    return undef;
}

# Full coverage uses integer counts, never rounded display percentages.
# A branch-free file must still have an explicit, valid zero measurement.
sub full_coverage_errors ( $targets, $actual, $expected = undef ) {
    my @errors;
    for my $file ( $targets->@* ) {
        for my $criterion (qw(statement branch)) {
            my $value = ( $actual->{$file} // {} )->{$criterion};
            if ( !$value ) {
                push @errors, "Missing $criterion coverage for $file\n";
                next;
            }
            my ( $covered, $total ) = $value->@{qw(covered total)};
            if (   !defined $covered
                || !defined $total
                || $covered !~ /\A[0-9]+\z/
                || $total   !~ /\A[0-9]+\z/
                || $covered > $total
                || ( $criterion eq 'statement' && !$total )
                || ( $covered == $total && ( $value->{error} // 0 ) )
                || ( $value->{uncoverable} // 0 ) )
            {
                push @errors, "Invalid $criterion measurement for $file\n";
                next;
            }
            push @errors, "$file $criterion coverage $covered/$total below 100%\n"
                if $covered != $total;
        }
    }
    push @errors, "Empty coverage target inventory\n" unless $targets->@*;
    push @errors, coverage_total_errors( $targets, $actual, $expected ) if defined $expected;
    return @errors;
}

# A pruned optree can otherwise produce an apparent 100% with fewer sites.
# Frozen per-file totals make that loss explicit instead of accepting it.
sub coverage_total_errors ( $targets, $actual, $expected ) {
    return "Invalid expected coverage totals\n" unless ref($expected) eq 'HASH';
    my @errors;
    my %wanted = map { $_ => 1 } $targets->@*;
    for my $file ( sort keys $expected->%* ) {
        push @errors, "Unexpected coverage target $file in expected totals\n" unless $wanted{$file};
    }
    for my $file ( $targets->@* ) {
        if ( ref( $expected->{$file} ) ne 'HASH' ) {
            push @errors, "Missing or invalid expected totals for $file\n";
            next;
        }
        for my $criterion (qw(statement branch)) {
            my $total = $expected->{$file}{$criterion};
            if ( !defined $total || $total !~ /\A[0-9]+\z/ ) {
                push @errors, "Missing or invalid expected $criterion total for $file\n";
                next;
            }
            my $value = ( $actual->{$file} // {} )->{$criterion};
            next unless $value && defined $value->{total};
            push @errors,
                "Unexpected $criterion total for $file: $value->{total} instead of $total\n"
                if $value->{total} != $total;
        }
    }
    return @errors;
}

# PPI otherwise treats executable AutoLoader routines as opaque data.
# Replacing only the marker keeps diagnostic source line numbers unchanged.
sub analysis_source ( $path, $text ) {
    if ( $path =~ m{(?:^|/)Gnu/XS\.pm\z} ) {
        $text =~ s/^__END__\r?$/# AutoLoader routines/m
            or die "Missing AutoLoader boundary in $path\n";
    }
    return $text;
}

sub inspect ( $path, $text, $critic, $profile ) {
    require Perl::Tidy;
    require Pod::Checker;
    my @errors;
    my ( $formatted, $stderr, $log ) = ( '', '', '' );
    my $status = Perl::Tidy::perltidy(
        source      => \$text,
        destination => \$formatted,
        stderr      => \$stderr,
        errorfile   => \$log,
        perltidyrc  => $profile,
        argv        => ['--assert-tidy'],
    );
    push @errors, "$path: formatting: $stderr$log" if $status;
    my $source = analysis_source( $path, $text );
    require PPI;
    my $document = PPI::Document->new( \$source );
    die "Cannot parse $path for annotation checks\n" unless $document;

    for my $comment ( ( $document->find('PPI::Token::Comment') || [] )->@* ) {
        next unless $comment->content =~ /\A\#\#\s+no\s+critic\b/;
        push @errors, "$path: unjustified or blanket Critic suppression\n"
            unless $comment->content =~
            /\A\#\#\s+no\s+critic\s+\([\w:]+(?:,\s*[\w:]+)*\)\s+--\s+\S/;
    }
    push @errors,
        map { "$path:" . $_->line_number . ': ' . $_->description . ' [' . $_->policy . "]\n" }
        $critic->critique( \$source );
    open my $pod, '<', \$text or die "Cannot read POD: $!";
    my $diagnostics = '';
    open my $output, '>', \$diagnostics or die "Cannot capture POD: $!";
    my $pod_errors = Pod::Checker::podchecker( $pod, $output, -warnings => 1 );
    close $pod    or die "Cannot close POD: $!";
    close $output or die "Cannot close POD diagnostics: $!";
    push @errors, "$path: POD: $diagnostics" if $pod_errors > 0 || length $diagnostics;
    return @errors;
}

# Merge stderr into stdout so neither pipe can block the other on Windows.
sub capture (@command) {
    my ( $input, $output );
    my $error = '';
    my $pid   = open3( $input, $output, $error, @command );
    close $input or die "Cannot close child input: $!";
    my $text = '';
    while (1) {
        my $count = sysread( $output, my $chunk, 16384 );
        die "Cannot read child output: $!" unless defined $count;
        last                               unless $count;
        $text .= $chunk;
    }
    close $output              or die "Cannot close child output: $!";
    waitpid( $pid, 0 ) == $pid or die "Cannot wait for child: $!";
    return ( $?, $text );
}

sub coverage_errors ( $minimum, $actual ) {
    my @errors;
    for my $file ( sort keys $minimum->%* ) {
        for my $criterion ( sort keys $minimum->{$file}->%* ) {
            my $value = ( $actual->{$file} // {} )->{$criterion};
            if ( !$value ) {
                push @errors, "Missing $criterion coverage for $file\n";
                next;
            }
            my $floor = $minimum->{$file}{$criterion};
            push @errors, "$file $criterion coverage $value->{percentage} below $floor\n"
                if $value->{percentage} + 0.000001 < $floor;
        }
    }
    return @errors;
}

1;
