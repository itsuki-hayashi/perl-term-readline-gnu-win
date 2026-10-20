# Contributor instructions

## Objective

Build the supplied GNU Readline and Term::ReadLine::Gnu with MSVC and an
MSVC-built Perl. Do not introduce MinGW, MSYS2, Cygwin, or Unix shell dependencies.

## Implementation constraints

- Keep Windows/MSVC changes conditional and preserve upstream Unix behavior.
- Match the target Perl's architecture, compiler settings, and CRT.
- Treat Perl/CRT FILE pointers, descriptors, and memory ownership as ABI boundaries.
- Build and stage outside the upstream source directories.
- Default to staging; install into Perl only when explicitly requested.
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
