# Third-party notices and attribution

## GNU Readline 8.3

Source: <https://ftp.gnu.org/gnu/readline/readline-8.3.tar.gz>

The Readline library is copyright **Free Software Foundation, Inc.**, with
years recorded in each file (for example, `readline.c`: 1987–2025). It is
maintained by **Chet Ramey**. Other authors' and contributors' notices are
preserved verbatim. This fork does not transfer their copyright to its maintainer.

The complete upstream source tree is in `vendor/readline/`; its archive and
file hashes are in `vendor/manifest.json`. `patches/readline/` records local
MSVC/Windows changes. Dated modification notices accompany patched sources.
Pristine upstream files are not rewritten to add project-wide license headers.

The principal library license is **GPL-3.0-or-later**, with these notable
component-specific grants, all retained in their original files:

| Material | Original terms / attribution |
|---|---|
| `gettimeofday.c` | LGPL-2.1-or-later; Free Software Foundation |
| `examples/rlfe` source | GPL-2.0-or-later; Per Bothner and other recorded authors |
| Main Readline/History/user manuals and generated formats | GFDL 1.3-or-later, no invariant sections or cover texts, as stated by their Texinfo masters |
| Older manual fragments/manpages | Their original copying/modification notices; preserved with corresponding source |
| `support/wcwidth.c` | Markus Kuhn's permissive use/copy/modify/distribute grant and warranty disclaimer; upstream modifications credited to Chet Ramey |
| `support/install-sh` | X Consortium permission and name-use conditions; FSF changes described as public domain |
| `support/config.rpath` | FSF unlimited-copy/distribution permission subject to retaining its notice |
| `support/config.guess`, `support/config.sub` | GPLv3-or-later plus the included configuration-script exception |
| `doc/texinfo.tex` | GPLv3-or-later plus its document-output exception |
| `configure`, generated Autoconf material | Included generation/copying exceptions and per-file notices |
| `support/mkinstalldirs` | Public-domain statement |

The file-level evidence index is `docs/licensing/vendor-inventory.json`.
That index points to retained text; it is not a blanket relicensing of files.
Some non-Windows examples and build tools are retained solely to preserve
upstream structure and source provenance; the Windows build does not execute them.

## Term::ReadLine::Gnu 1.47

Author: **Hiroo Hayashi** <hiroo.hayashi@computer.org>.

Source: <https://cpan.metacpan.org/authors/id/H/HA/HAYASHI/Term-ReadLine-Gnu-1.47.tar.gz>

Project: <https://github.com/hirooih/perl-trg>

Original copyright notices cover 1996–2025 in the distribution, with exact
years differing by file. Other contributor notices, including Ilya
Zakharevich's OS/2 contributions, remain credited where present. Original
release history and README/install documentation are retained in `docs/`.

The original module states "the same terms as Perl itself": Artistic License
or GNU GPL version 1-or-later. We use its GPL option for the GPLv3-or-later
combined work. The original grants remain applicable to the original portions.
The new namespace, Windows-only build and packaging changes are this fork's
work, not an upstream release. Modified files carry dated fork notices.

## Devel::PPPort 3.68 (`xs/ppport.h`)

The generated portability header is retained unmodified. It credits Marcus
Holland-Moritz, Paul Marquess and Kenneth Albanowski for the respective version
series and uses the same terms as Perl. Consult its COPYRIGHT/LICENSE POD.

## Earlier Windows-port contributions

Earlier project code was released under the Unlicense. The existing `win32/`
implementation retains that grant, while new packaging/build code is
GPL-3.0-or-later. No later project notice retracts rights already granted
under the Unlicense. Its full text is preserved under `LICENSES/`.

## License texts and boundaries

`COPYING` and `LICENSES/` include GPLv3, GPLv2, GPLv1, LGPLv2.1, the original
Perl Artistic License, GFDL 1.3, and the historical Unlicense. Specialized
permissive grants and exceptions are included verbatim in the files above.
Metadata describes the combined GPLv3 software; it does not claim that GNU
manuals or all original components have been relicensed under that one license.
