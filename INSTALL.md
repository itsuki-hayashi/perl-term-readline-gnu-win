# Installation and troubleshooting

## Select the target Perl

Use native MSVC Perl 5.44+ for x64 or ARM64 with shared release `/MD` runtime.
Inspect `perl -V`. The module does not build Perl for end users; CI separately
provisions Perl for each selected native ABI.

Typical executables are `%LOCALAPPDATA%\Programs\Perl\bin\perl.exe` and
`C:\Program Files\Perl\bin\perl.exe`. Invoke the desired executable directly
when several distributions exist. Check `where perl` and `where cl` in cmd,
or `Get-Command perl,cl,nmake` in PowerShell.

## Standard MakeMaker flow

In the matching Visual Studio 2026 Native Tools prompt:

```bat
perl Makefile.PL
nmake
nmake test
nmake install
```

Download the source archive from GitHub or use a checkout. Start in the
developer environment so `cl`, `lib`, `link`, and `nmake` are available. The archive
includes all library sources and patches; it needs no additional download
or Unix commands. There is no switch to silently link a system Readline.

Standard MakeMaker options such as `INSTALL_BASE` and `DESTDIR` control Perl
installation. When using a separate `INSTALL_BASE`, add its `lib/perl5` and
architecture directory to `PERL5LIB`, and its `bin` directory to PATH.

## Backend selection

| Setting | Value |
|---|---|
| Backend environment variable | `PERL_RL=Gnu` |
| Backend package | `Term::ReadLine::Gnu` |
| Installed REPL | `perlsh.bat` |

No backend setting is required for automatic discovery. An explicit setting
must precede loading Term::ReadLine. Leave `PERL_RL` unset for automatic selection.
This fork replaces upstream Gnu; use a separate library prefix for trials.
Do not reuse compiled extensions across Perl versions or architectures.
Run `nmake realclean` before switching target Perl or compiler.

## Diagnosing failures

- **Missing compiler:** use the matching Native Tools prompt.
  Install the C++ workload and Windows SDK.
- **Unsupported CRT/Perl:** this is an ABI requirement, not a flag to override.
  Obtain or build a compatible interpreter.
- **Stub fallback:** check backend selection, installation paths, and loading
  errors. Check `$INC{"Term/ReadLine/Gnu.pm"}` to identify the loaded implementation.
- **Wrong machine type:** select the compiler for the interpreter's architecture,
  not merely the host OS. x64 on ARM emulation is still x64.
- **Vendor/patch mismatch:** restore the pristine tree or follow the dependency
  update guide. Patches deliberately do not use fuzzy matching.
- **Console test failure:** inspect `build/native/*.log`; required console
  failures must not be hidden behind blanket skips.
- **Unicode output outside readline:** configure the application's PerlIO
  layers and terminal settings. This module restores caller code pages.

Bug reports should include `perl -V`, Windows build, toolset/SDK,
build output, failing TAP, and console logs.
Review private history or `.perlshrc` contents before sharing them.
