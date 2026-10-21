# Term::ReadLine::GnuWin32

Native GNU Readline and history editing for **Windows 11, Perl 5.44+, and
Visual C++ 2026+**. The source distribution bundles GNU Readline 8.3 and
builds it with the same MSVC architecture and shared CRT as the target Perl.
It needs no MinGW, MSYS2, Cygwin, Unix shell, or network access to build.

This is an independent fork of Hiroo Hayashi's **Term::ReadLine::Gnu 1.47**.
It installs `Term::ReadLine::GnuWin32`, not the upstream module. The initial
version, **0.001_001**, is a developer release; see [release policy](docs/RELEASING.md).

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

`Term::ReadLine` does not automatically discover third-party backend names.
Set `PERL_RL` **before loading it**:

```perl
BEGIN { $ENV{PERL_RL} = 'GnuWin32' }
use Term::ReadLine;

my $term = Term::ReadLine->new('example');
$term->enableUTF8();
while (defined(my $line = $term->readline('input> '))) {
    print "You entered: $line\n";
}
```

Check `$term->ReadLine eq 'Term::ReadLine::GnuWin32'` to detect fallback.
Do not `use Term::ReadLine::GnuWin32` directly. The original upstream namespace
remains available to its own distribution; this fork installs no shim over it.

In PowerShell, select the backend for the debugger:

```powershell
$env:PERL_RL = 'GnuWin32'
perl -d your-script.pl
```

The installed REPL is **`perlsh-gnu-win32.bat`**. It selects the backend
itself and uses `HOME`, then `USERPROFILE`, then `HOMEDRIVE` + `HOMEPATH`
for `.perlsh_history` and `.perlshrc`.

## Behavior and API

The fork retains upstream methods, attributes, history functions, completion
hooks, and callbacks. The main module's POD contains the inherited API reference
and Windows guidance: `perldoc Term::ReadLine::GnuWin32`.

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
Windows SDK 10.0.26100.0. All 332 tests passed with both the existing
MSVC Perl and a fresh Perl built by the CI bootstrap. The fresh build also
passed from a source directory containing spaces. The 24 release checks
passed, including source-only contents, metadata, POD and vendor hashes.
Integer-boundary regression tests bring the suite to 350 tests. The MSVC
`/W3` build has no warnings from the bundled Readline, Windows port or XS
sources; Perl 5.44's installed `CORE/inline.h` still emits one C4244 warning.
ARM64 library cross-compilation passed; native ARM64 runtime tests and
hosted GitHub Actions runs remain pending. Optional Tk was unavailable.

Before release, run `perl script/release.pl` and `perl script/test-archive.pl`
in the developer environment. The latter rebuilds a fresh archive, installs
into a prefix containing spaces, inspects DLL imports, and exercises the
installed module outside its source directory. These tools do not upload to
CPAN or install into the user's Perl. Logs and target configuration are under
`build/`; candidate archives are under `dist/`.

## Limitations

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
- Windows fork and CPAN packaging: Itsuki Hayashi.

Read [LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and
[the licensing guide](docs/LICENSING.md). Original upstream licensing is not
erased. Component-specific grants are preserved in their source notices and
the accompanying license texts.

Report fork issues at the [repository tracker](https://github.com/itsuki-hayashi/perl-term-readline-gnu-win/issues).
