# Architecture and build contract

## Layers

1. `lib/Term/ReadLine/GnuWin32.pm` implements the backend and inherited API.
2. `GnuWin32.xs`, `typemap`, and private `XS.pm` bind Readline. AutoSplit creates
   installed AutoLoader routines; opaque classes live under `Pointer`.
3. `win32/` handles consoles, UTF-8/scalar conversion, directory enumeration,
   Unicode filesystem calls, and a bounded VT capability table.
4. `vendor/readline/` is pristine upstream source. Ordered patches supply
   minimal Windows hooks in a generated build copy.
5. `inc/GnuWin32/` holds private build utilities and is never installed.

The extension statically links Readline, avoiding a separate library DLL.
Both native library and XS use `/MD`, matching the target Perl. Streams,
descriptors and allocator ownership cross that shared CRT boundary; they
must not be mixed with another compiler or CRT configuration.

## Build sequence

Configuration probes platform data and compiler macros without building
Readline. The make target verifies vendor hashes, creates `build/readline`,
applies exact unified hunks, copies headers and builds native objects. The XS
object depends on that target. Generated files remain in `build/`, `blib/`,
or conventional MakeMaker output names.

Standard `clean`/`realclean` remove
generated outputs without modifying the vendor baseline.

## Console boundary

Readline sees UTF-8 bytes. Native UTF-16 key events are combined into Unicode
scalars. Internal character values use 32 bits instead of truncating through
MSVC's 16-bit `wchar_t`. Cell widths are approximations, not grapheme layout.

Output uses VT sequences. Write-only `CONOUT$` streams require an additional
readable handle for console inspection; the backend owns and closes it.
Resize handling uses visible window dimensions rather than scrollback size.
Preparation/depreparation save and restore modes and code pages. Redirected
files use ordinary CRT I/O.

The native test driver creates its own hidden console, injects key-down/up
events with scan codes, and uses bounded child timeouts. It covers the backend,
debugger, and generated REPL launcher without manual input. No Unix terminal
database, POSIX signal emulator, job control or select/alarm layer is supplied.
