# Contributor instructions

## Objective

Maintain the Windows-only GitHub-only Term-ReadLine-GnuWin32 distribution providing
Term::ReadLine::Gnu, derived
from Term::ReadLine::Gnu 1.47 and bundled GNU Readline. Require Windows 11+,
MSVC Perl 5.44+, Visual C++ 2026+, and native x64 or ARM64. Do not introduce
MinGW, MSYS2, Cygwin, or Unix shell dependencies into installation.

## Implementation constraints

- Keep vendor sources pristine and preserve their upstream structure. Put
  upstream edits in ordered patches applied to build copies by Perl.
- Match the target Perl's architecture, compiler settings, and CRT.
- Treat Perl/CRT FILE pointers, descriptors, and memory ownership as ABI boundaries.
- Build outside the upstream source directories.
- Use standard MakeMaker build and installation targets.
- Support modern Windows VT consoles, UTF-8, redirected input, and callbacks.
- Restore console modes and code pages when editing finishes or is interrupted.
- Keep public Perl APIs compatible and report unsupported behavior honestly.

## Verification

Run native C checks, the applicable Perl suite, and console integration checks.
Inspect binary dependencies for forbidden runtimes. Record actual results and
limitations in README.md; never present an untested feature as verified.

## Working practices

Read existing changes before editing. Do not overwrite unrelated work.
Use focused portability helpers rather than global compiler impersonation.
Do not suppress failing tests merely to obtain a passing build.
Use standard MakeMaker targets. New code is GPL-3.0-or-later;
retain original upstream and prior grants.
