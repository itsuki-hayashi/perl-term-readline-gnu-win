# SPDX-FileCopyrightText: 2026 itsuki-hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use 5.044;
use strict;
use warnings;
use Test::More;
use CPAN::Meta;
use ExtUtils::Manifest qw(maniread manicheck filecheck);
use Pod::Checker;
use File::Find;
use lib 'inc';
use GnuWin32::Build;
my $meta=CPAN::Meta->load_file('META.json');
is($meta->name,'Term-ReadLine-GnuWin32','independent distribution');
is($meta->as_struct->{release_status},$meta->version =~ /_/ ? 'unstable' : 'stable','release status matches version');
is_deeply($meta->as_struct->{license},['gpl_3'],'GPLv3 metadata');
is($meta->as_struct->{x_spdx_expression},'GPL-3.0-or-later','explicit or-later grant');
is($meta->effective_prereqs->requirements_for('runtime','requires')->requirements_for_module('perl'),'5.044','minimum Perl');
my @missing=manicheck(); is_deeply(\@missing,[],'all manifest entries exist');
my @extra=filecheck(); is_deeply(\@extra,[],'no unmanifested release files');
my $files=maniread();
ok(!(grep {m{^(?:build|stage|blib|dist)/|/\.git/|\.(?:obj|dll|exe|pdb|lib)$}} keys %$files),'source-only archive');
ok(GnuWin32::Build::verify_vendor(),'vendor hashes match');
for my $file (qw(lib/Term/ReadLine/GnuWin32.pm lib/Term/ReadLine/GnuWin32/XS.pm)) {
    is(podchecker($file),0,"POD valid: $file");
}
for my $file (qw(LICENSE COPYING REUSE.toml THIRD_PARTY_NOTICES.md docs/licensing/vendor-inventory.json LICENSES/GPL-3.0-or-later.txt LICENSES/GPL-2.0-or-later.txt LICENSES/GPL-1.0-or-later.txt LICENSES/LGPL-2.1-or-later.txt LICENSES/GFDL-1.3-no-invariants-or-later.txt LICENSES/Artistic-1.0-Perl.txt LICENSES/Unlicense.txt)) {
    ok(exists $files->{$file},"license/notice included: $file");
}
my @packages;
find(sub { return unless /\.pm$/; my $text=GnuWin32::Build::slurp($_); push @packages, $text =~ /^package\s+([\w:]+)/mg },'lib');
ok(!(grep {!/^Term::ReadLine::GnuWin32(?:::|$)/} @packages),'only fork-owned Perl packages');
done_testing;
