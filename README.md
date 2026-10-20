# GNU Readline and Perl with MSVC

This repository contains GNU Readline 8.3 and Term::ReadLine::Gnu 1.47.
It provides a native Windows build using MSVC and an MSVC-built Perl,
without MinGW, MSYS2, Cygwin, or a Unix shell at build or runtime.

## Target environment

- Windows 10/11 consoles and Windows Terminal with VT support.
- Visual Studio 2026 C++ tools and Windows SDK.
- PowerShell 7.3 or later.
- An MSVC-built Perl with matching architecture and shared CRT.
- Perl discovery: explicit executable, per-user installation under
  `%LOCALAPPDATA%\Programs\Perl`, then `C:\Program Files\Perl`.

The development machine has x64 Perl 5.44.0 built with `cl`, `/MD`, and
`nmake`. Building Perl itself is outside this repository's scope.

## Build and stage

Run from PowerShell; a Visual Studio developer prompt is not required:

```powershell
./build.ps1
```

The script discovers Perl in the order above, initializes Visual Studio's
matching x64 or x86 environment, builds static `readline.lib` and `history.lib`,
builds the XS extension, runs tests, and stages the installation. No downloads
or Unix build tools are needed. To select paths explicitly:

```powershell
./build.ps1 -Perl "$env:LOCALAPPDATA/Programs/Perl/bin/perl.exe" `
    -BuildDir './build' -InstallPrefix './stage'
```

The default outputs are:

- `stage/include/readline/`: public C headers.
- `stage/lib/`: native static libraries; C consumers link `user32.lib` as well.
- `stage/perl/`: Perl extension and scripts, laid out using `INSTALL_BASE`.
- `build/build.log`, `perl-config.json`, `dependencies.txt`, `validation.json`:
  build output, target configuration, DLL imports, and validation status.
- `build/native/`: C test executables and console/integration logs.

`-LibrariesOnly` builds and tests the C libraries without building the module.
`-Install` additionally installs the tested extension into the selected Perl's
normal site directories. The default only writes to the build and stage trees.
Use a new build directory when changing Perl versions or architectures.

## Use the staged module

Set `PERL5LIB` for the current shell, using the architecture from the target Perl:

```powershell
$perl = "$env:LOCALAPPDATA/Programs/Perl/bin/perl.exe"
$arch = & $perl -MConfig -e 'print $Config{archname}'
$prefix = (Resolve-Path './stage').Path
$env:PERL5LIB = "$prefix/perl/lib/perl5/$arch;$prefix/perl/lib/perl5"
$env:PERL_RL = 'Gnu'
& $perl -d -e '0'
```

For Unicode Perl strings, call `$term->enableUTF8()` after constructing the
`Term::ReadLine` object. Native console input and filesystem names use UTF-8;
the port does not change the process-wide C locale. An unset `TERM` defaults
to the bundled `win32` VT description. `TERM=dumb` requests plain output.

The module's `--prefix`, `--includedir`, and `--libdir` options accept quoted
Windows paths. Multiple paths use semicolons on Windows and colons on Unix.

## Validation and limits

Verified on this machine with x64 MSVC Perl 5.44.0 and Visual Studio 2026:

- All 296 checks in the eight upstream Perl test files pass. Optional Tk tests
  are unavailable; native callback tests exercise callbacks separately.
- Native tests cover history read/write/append/truncation, Japanese filenames,
  completion, redirected input and EOF, UTF-8 decoding, Japanese characters,
  supplementary characters, combining-character width, and multibyte deletion.
- Hidden native console tests cover editing keys, history, tab completion,
  bracketed paste, wrapping, resize handling, Ctrl-C, EOF, callbacks, and
  restoration of console modes and code pages.
- The staged Perl module passes console Unicode/history/callback tests, and
  the Perl debugger confirms it selected `Term::ReadLine::Gnu`.
- `perlsh.bat` startup tests cover `HOME`, `USERPROFILE`, and
  `HOMEDRIVE`/`HOMEPATH`, loading `.perlshrc`, evaluation, history, and exit.
  Windows uses Perl's native signal handler instead of POSIX `sigaction`.
- A clean build succeeds with spaces in both output paths. DLL imports contain
  only Perl, Windows, and Microsoft CRT libraries.

The first target is modern VT-capable Windows consoles. ARM, debug/static-CRT
Perl, POSIX job control, Readline's POSIX alarm/select timeout facilities, and
legacy non-VT rendering are not supported. x86 is selected from Perl's config
but has not been tested on this machine. Unicode editing operates on code
points, with approximate terminal cell widths; it does not promise full
grapheme-cluster or font-specific emoji layout. Interactive Windows Terminal
rendering and optional Tk integration still merit manual testing.

Upstream source licenses remain applicable; see each source tree for details.
In particular, the linked GNU Readline code is GPLv3-or-later; the root license
does not replace the upstream licenses.
