# Licensing and attribution policy

## Project choice

New fork code uses `GPL-3.0-or-later`. The combined extension statically links
GNU Readline, whose principal code uses that license. The original Perl wrapper
offers the same terms as Perl, including GPL version 1-or-later; its GPL option
permits this GPLv3 combination. Preserve the original dual-license notices for
upstream portions instead of claiming ownership or erasing their grants.

The root LICENSE explains scope, COPYING contains GPLv3, and LICENSES holds
the applicable full texts. CPAN's `gpl_3` metadata token does not express
"or later"; the custom SPDX field, POD and notices supply that information.
Bundled manuals and helper files retain their separate licenses/exceptions.

References: [Perl licensing](https://dev.perl.org/licenses/),
[GNU compatibility guidance](https://www.gnu.org/licenses/license-compatibility.en.html),
[GNU licensing instructions](https://www.gnu.org/licenses/gpl-howto.en.html).

## Recording authorship

- Retain original copyright, license, warranty and author notices.
- Credit Hiroo Hayashi for the Perl wrapper and the FSF for its Readline
  copyrights. Credit Chet Ramey's maintainership without assigning others'
  copyright to him or to this fork.
- Add dated descriptions of our changes to modified files/patches. Add
  copyright only for contributions actually made, with the author's identity.
- Keep pristine vendor files untouched. The vendor manifest, patches and
  external evidence inventory document their origin without rewriting them.
- New first-party files use SPDX headers or external REUSE-style annotations.
  Do not claim that a partial annotation file is a complete REUSE compliance audit.
- Review all licenses and notices when changing dependencies, including
  generated manuals and support scripts that the Windows build does not use.

The inventory generator retains notice evidence for every upstream file and
references corresponding manual source for binary formats. Original per-file
text remains authoritative; an automated keyword scan is not a legal conclusion.

## Existing grants and redistribution

Earlier project contributions had an Unlicense grant, preserved in this
release. Later licensing statements do not revoke that grant. Unmodified
Windows-port code keeps its existing permissive provenance; new additions
are offered under GPLv3-or-later and incorporated into the combined work.

Distributing the combined binary requires satisfying applicable GPL terms,
including corresponding-source obligations. Keep the exact source, local
patches and build materials that produced a binary. This project grants no
special Readline linking exception and does not label the combined binary
"Perl-license-only". Unrelated software is not relabeled by a project notice.

For a source-only CPAN candidate, the release checks verify inclusion of
license texts, notices and vendor hashes. A separate binary distributor must
choose and satisfy an applicable GPL source-conveyance method; this guide is
not a substitute for reviewing that distributor's actual arrangement.
