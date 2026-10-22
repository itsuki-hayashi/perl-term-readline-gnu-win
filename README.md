# Term::ReadLine::Gnu

Native GNU Readline and history editing for **Windows 11, Perl 5.44+, and
Visual C++ 2026+**. The source distribution bundles GNU Readline 8.3 and
builds it with the same MSVC architecture and shared CRT as the target Perl.
It needs no MinGW, MSYS2, Cygwin, Unix shell, or network access to build.

This is an independent fork of Hiroo Hayashi's **Term::ReadLine::Gnu 1.47**.
It is distributed through GitHub as **Term-ReadLine-Gnu**, and provides
**`Term::ReadLine::Gnu`** for automatic backend discovery and CPAN command
completion. Version **1.470_001** identifies this Windows fork of upstream 1.47.
This project is not published to CPAN or PAUSE.

This replaces upstream `Term::ReadLine::Gnu` in the selected library tree.
Do not install both implementations into the same destination. Use an isolated
`INSTALL_BASE` to try this fork, with its library directories first in `PERL5LIB`.
Installing upstream later can replace this fork; CPAN conflict metadata cannot
protect two implementations of the same package.

## Requirements

| Component | Requirement |
|---|---|
| Client OS | Windows 11 or later, with a VT-capable console |
| Server OS | Windows Server 2025 or later; supplementary x64 CI |
| Perl | Native MSVC Perl 5.44+, shared release CRT (`/MD`) |
| Architectures | x64 and ARM64; x86 is rejected |
| Compiler | Visual C++ 2026, v145 / compiler 19.50+, or newer |
| SDK | A Windows SDK installed with the C++ toolchain |
| Build tool | MSVC `nmake`; MakeMaker 7.78 or later |

Strawberry/MinGW and Cygwin Perl cannot build this extension. An x64 Perl
running under ARM emulation still produces an x64 extension; native ARM64
validation requires an ARM64 Perl and compiler.

## Installation

Open the **matching Visual Studio Native Tools command prompt**, select your
MSVC Perl, extract the distribution, and run:

```bat
perl Makefile.PL
nmake
nmake test
nmake install
```

For a separate installation, use `perl Makefile.PL INSTALL_BASE="C:\Perl modules"`.
Configuration checks prerequisites; compilation happens during `nmake`.
Readline is patched in `build/readline/`, never in the maintained vendor tree.

See [INSTALL.md](INSTALL.md) for installation options and troubleshooting.

## Select the backend

`Term::ReadLine` automatically discovers this backend when `PERL_RL` is unset.
CPAN recognizes its GNU identity and installs command completion. An explicit
`PERL_RL=Gnu` also works.
Load the backend through the standard interface:

```perl
use Term::ReadLine;

my $term = Term::ReadLine->new('example');
$term->enableUTF8();
while (defined(my $line = $term->readline('input> '))) {
    print "You entered: $line\n";
}
```

Check `$term->ReadLine eq 'Term::ReadLine::Gnu'` to detect fallback.
Do not `use Term::ReadLine::Gnu` directly. This fork and upstream provide the same package and cannot coexist in one
library destination.

In PowerShell, select the backend for the debugger:

```powershell
$env:PERL_RL = 'Gnu'
perl -d your-script.pl
```

The installed REPL is **`perlsh.bat`**. It selects the backend
itself and uses `HOME`, then `USERPROFILE`, then `HOMEDRIVE` + `HOMEPATH`
for `.perlsh_history` and `.perlshrc`.

## Behavior and API

The fork retains upstream methods, attributes, history functions, completion
hooks, and callbacks. The main module's POD contains the inherited API reference
and Windows guidance: `perldoc Term::ReadLine::Gnu`.

- Console input is converted from UTF-16 to UTF-8, including supplementary
  characters. `enableUTF8()` controls Perl string decoding.
- Completion and history paths use Windows Unicode filesystem APIs.
- The bundled `win32` description uses VT sequences. An unset `TERM` defaults
  to `win32`; `TERM=dumb` requests plain terminal behavior.
- Console modes and code pages are restored after editing, EOF, interruption,
  and callback removal. Applications control encoding outside Readline.
- Readline is single-instance per interpreter. Applications drive callback
  reads when input is ready; no GUI event loop is supplied.

See [examples](examples/) and [architecture](docs/ARCHITECTURE.md). Historical
Unix examples remain reference material, not Windows dependency guarantees.

## Tests and CI

`nmake test` runs inherited Perl tests, platform rejection checks, pristine
vendor verification, and native C/console tests. The native driver creates its
own hidden console and injects events; no interactive desktop input is needed.
Console creation failures fail required tests. Optional Tk is reported separately.

The [workflow matrix](.github/workflows/windows.yml) builds native MSVC Perl
from a pinned archive and tests these initial configurations:

| Runner | Architecture | Perl | Toolchain |
|---|---|---|---|
| `windows-2025-vs2026` | x64 | 5.44.0 | VS 2026 / v145 |
| `windows-11-vs2026-arm` | ARM64 | 5.44.0 | VS 2026 / v145 |

The x64 hosted job uses Server, not Windows 11. Windows 11 x64 is tested
locally; a self-hosted row can add client CI. Adding ARM64 to the matrix does
not imply it passed before its first run. See [CI.md](docs/CI.md).

Local validation on 2026-10-21 used Windows 11 x64, Perl 5.44.0,
Visual Studio 2026 Community (MSVC 19.51 / tools 14.51.36231), and
Windows SDK 10.0.26100.0. All **360 tests** passed with the fresh MSVC Perl,
including native C/console tests, automatic backend discovery, explicit GNU
and Stub selection, CPAN shell callback initialization, and actual Tab
completion of a CPAN command. The 24 release checks passed, including
source-only contents, metadata, POD and pristine vendor hashes. An extracted
archive passed the same suite and installed into a temporary prefix containing
spaces. The installed backend was automatically discovered with `PERL_RL`
unset, and DLL inspection found no MinGW, MSYS2 or Cygwin dependencies.
ARM64 library cross-compilation passed; native ARM64 runtime tests and
hosted GitHub Actions runs remain pending. Optional Tk was unavailable.

Perl modernization was revalidated on 2026-10-23 on Windows 11 x64 with
MSVC Perl 5.44.0 and Visual Studio 2026. All **607 checkout tests** passed,
including native C/console integration; the instrumented suite passed
**621 tests** including author-check regressions. All **35 maintained Perl
sources** passed formatting, configured severity-1 analysis, POD and staged
compilation. The 25 release checks and a fresh archive build, test, temporary
installation and DLL dependency inspection also passed. Pinned author tools
were installed with their dependency tests into a contained local library.
Coverage calibration and the measured per-module floors passed; partial
coverage and instrumentation limitations are documented in
[PERL_QUALITY.md](docs/PERL_QUALITY.md). Native ARM64, hosted CI and optional
Tk validation for these changes remain unavailable locally.

Before release, run `perl script/release.pl` and `perl script/test-archive.pl`
in the developer environment. The latter rebuilds a fresh archive, installs
into a prefix containing spaces, inspects DLL imports, and exercises the
installed module outside its source directory. These tools do not publish releases or install into the user's Perl. Logs and target configuration are under
`build/`; candidate archives are under `dist/`.

## Limitations

Maintained Perl has mandatory formatting, severity-1 static analysis, POD,
compilation and measured coverage gates in the existing native CI jobs.
Author dependencies are separate from installation prerequisites. See
[the Perl quality guide](docs/PERL_QUALITY.md) for commands, compatibility
exceptions, excluded examples and coverage limitations.

This release excludes x86, legacy non-VT rendering, POSIX job control,
POSIX alarm/select timeouts, static-CRT/debug Perl, and MinGW/Cygwin ABIs.
Unicode editing operates on code points with approximate cell widths;
font-specific emoji and full grapheme-cluster layout are not guaranteed.
Readline's globals do not provide concurrent independent sessions.
GUI/Tk integrations need separate dependencies and validation.

Readline retains its 32-bit `int` API for line indexes and counts. Sizes,
pointer differences and Perl callback counts use native-width types until
an API boundary. Out-of-range Perl integer arguments raise exceptions;
native I/O requests beyond `INT_MAX` return `EOVERFLOW`. Internal Readline
size overflow fails fast instead of truncating an index. See the
[integer policy](docs/ARCHITECTURE.md#integer-boundaries).

## Attribution and licensing

The combined software and new fork contributions use **GNU GPL version 3
or later**. Upstream components retain their notices and applicable licenses,
including GNU documentation, LGPL and permissive exceptions.

- GNU Readline 8.3: Free Software Foundation copyright; maintained by Chet Ramey.
- Term::ReadLine::Gnu 1.47: Hiroo Hayashi and its recorded contributors.
- Windows fork and GitHub distribution: Itsuki Hayashi.

Read [LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and
[the licensing guide](docs/LICENSING.md). Original upstream licensing is not
erased. Component-specific grants are preserved in their source notices and
the accompanying license texts.

Report fork issues at the [repository tracker](https://github.com/itsuki-hayashi/perl-term-readline-gnu-win/issues).
