# Contributing

Use MSVC Perl 5.44+ and VS 2026+. Run `perl Makefile.PL` and `nmake` in the
matching Native Tools prompt; a working
Strawberry build does not prove ABI compatibility. Keep platform diagnostics
specific. Do not add x86 support or shell-tool dependencies to installation.

Run `nmake test` after changes. Add behavior regressions for console, ownership,
namespace and packaging failures. Required console tests must not be skipped
to make CI green. Optional integrations must explain their skips. Validate
the installed archive through `script/test-archive.pl` before release.

Maintained Perl must also pass `perl script/check-perl.pl` and
`perl script/coverage-perl.pl --require-full`. Install pinned author dependencies with
`.github/scripts/install-author-tools.ps1` in the same Native Tools environment.
See [the Perl quality guide](PERL_QUALITY.md) for policy decisions, formatting,
AutoLoader checks and exact 100% statement/branch requirements. Inherited examples are excluded
from the initial author gates; vendor sources must not be reformatted.

Keep vendor sources pristine. Upstream hooks belong in patches; Windows
implementations belong in `win32/`. Follow UPDATING_READLINE.md and audit
licenses and new files when updating. Never commit generated binaries or logs.

New contributions are GPL-3.0-or-later. Preserve original notices, add your
copyright only for your contributions, and date significant modifications.
No copyright assignment or upstream endorsement is implied.

Report environment and logs as described in INSTALL.md. Pull requests should
explain changed behavior, ABI implications, and actual tests. Document unavailable
ARM64 or GUI testing honestly.
