# Installation and troubleshooting

## Select the target Perl

Use native MSVC Perl 5.44+ for x64 or ARM64 with shared release `/MD` runtime.
Inspect `perl -V`. The module does not build Perl for end users; CI separately
provisions Perl for each selected native ABI.

Typical executables are `%LOCALAPPDATA%\Programs\Perl\bin\perl.exe` and
`C:\Program Files\Perl\bin\perl.exe`. Invoke the desired executable directly
when several distributions exist. Check `where perl` and `where cl` in cmd,
or `Get-Command perl,cl,nmake` in PowerShell.

## Standard CPAN flow

In the matching Visual Studio 2026 Native Tools prompt:

```bat
perl Makefile.PL
nmake
nmake test
nmake install
```

A CPAN client uses the same MakeMaker contract. Start it in that developer
environment so `cl`, `lib`, `link`, and `nmake` are available. The archive
includes all library sources and patches; it needs no additional download
or Unix commands. There is no switch to silently link a system Readline.

Standard MakeMaker options such as `INSTALL_BASE` and `DESTDIR` control Perl
installation. `perl script/build.pl` instead activates MSVC automatically
and stages into `stage/`. Unlike the former PowerShell layout, this directory
is itself the Perl installation base, containing `lib/perl5` and `bin`.
The helper's `--install` installs into the invoking Perl after tests pass.

## Migrating from upstream or the prototype

| Previous use | This fork |
|---|---|
| `PERL_RL=Gnu` | `PERL_RL=GnuWin32` |
| `Term::ReadLine::Gnu` | `Term::ReadLine::GnuWin32` |
| `perlsh.bat` | `perlsh-gnu-win32.bat` |
| Global pointer classes | `Term::ReadLine::GnuWin32::Pointer::*` |

For staging, add `stage/lib/perl5` and its architecture directory to
`PERL5LIB`, and `stage/bin` to PATH. Set the backend before loading Term::ReadLine.
Do not reuse compiled extensions across Perl versions or architectures.
Run `nmake realclean` before switching target Perl or compiler.

## Diagnosing failures

- **Missing compiler:** use the matching Native Tools prompt or Perl build
  helper. Install the C++ workload and Windows SDK.
- **Unsupported CRT/Perl:** this is an ABI requirement, not a flag to override.
  Obtain or build a compatible interpreter.
- **Stub fallback:** check backend selection, installation paths, and loading
  errors. The fork does not overwrite upstream Gnu for automatic discovery.
- **Wrong machine type:** select the compiler for the interpreter's architecture,
  not merely the host OS. x64 on ARM emulation is still x64.
- **Vendor/patch mismatch:** restore the pristine tree or follow the dependency
  update guide. Patches deliberately do not use fuzzy matching.
- **Console test failure:** inspect `build/native/*.log`; required console
  failures must not be hidden behind blanket skips.
- **Unicode output outside readline:** configure the application's PerlIO
  layers and terminal settings. This module restores caller code pages.

Bug reports should include `perl -V`, Windows build, toolset/SDK,
`build/configuration.json`, build output, failing TAP, and console logs.
Review private history or `.perlshrc` contents before sharing them.
