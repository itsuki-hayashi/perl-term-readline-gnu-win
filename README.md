# GNU Readline and Perl with MSVC

This repository contains GNU Readline 8.3 and Term::ReadLine::Gnu 1.47.
The goal is a native Windows build using MSVC and an MSVC-built Perl,
without MinGW, MSYS2, Cygwin, or a Unix shell at build or runtime.

## Target environment

- Windows 10/11 consoles and Windows Terminal with VT support.
- Visual Studio 2026 C++ tools and Windows SDK.
- An MSVC-built Perl with matching architecture and shared CRT.
- Perl discovery: explicit executable, per-user installation under
  `%LOCALAPPDATA%\Programs\Perl`, then `C:\Program Files\Perl`.

The development machine has x64 Perl 5.44.0 built with `cl`, `/MD`, and
`nmake`. Building Perl itself is outside this repository's scope.

## Work in progress

The native build script, portability layer, and integration tests are being
implemented. Successful compilation alone is not evidence of working console
editing. Validation must cover history, completion, callbacks, Unicode input,
redirected streams, and restoration of console state.

Upstream source licenses remain applicable; see each source tree for details.
