# Architecture and build contract

## Layers

1. `lib/Term/ReadLine/Gnu.pm` implements the backend and inherited API.
2. `xs/Gnu.xs`, `xs/typemap`, and private `XS.pm` bind Readline. AutoSplit creates
   installed AutoLoader routines; opaque classes live under `Pointer`.
3. `win32/` handles consoles, UTF-8/scalar conversion, directory enumeration,
   Unicode filesystem calls, and a bounded VT capability table.
4. `vendor/readline/` is pristine upstream source. Ordered patches supply
   minimal Windows hooks in a generated build copy.
5. `inc/Gnu/` holds private build utilities and is never installed.

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

XS sources, their typemap and the bundled `ppport.h` live together in `xs/`.
MakeMaker explicitly maps each XS source to its generated C file and uses
`TYPEMAPS` for `xs/typemap`. Generated C, object and compiler debug files also
live in `xs/`; Git and the release manifest exclude these disposable outputs.
The MSVC compile rule explicitly selects the object path so the compiler
does not leave an object file at the project root.

Standard `clean`/`realclean` remove
generated outputs without modifying the vendor baseline.

## Integer boundaries

MSVC uses LLP64: `int` and `long` remain 32-bit, while `size_t`, `ptrdiff_t`,
Perl IV/UV and Perl stack counts are 64-bit. The public Readline API and its
structures retain their upstream `int` fields and callback signatures.
Replacing those fields wholesale with 64-bit integers would change the ABI.

XS uses native-width sizes/counts and checks integer and string arguments
before narrowing them for Readline. Conversion failures raise Perl
exceptions. The Windows descriptor wrappers keep native-width signatures,
use 64-bit seek/truncation functions, and reject read/write counts beyond
the CRT's `INT_MAX` limit with `EOVERFLOW` before touching the buffer.

`win32/checked.h` checks the remaining internal Readline conversions,
preserving signed pointer differences and multibyte error sentinels.
Unrepresentable internal sizes abort with a diagnostic rather than permit
index wraparound and memory corruption, following Readline's existing
fatal-allocation-failure model. This does not add support for multi-gigabyte
editable lines. Optional POSIX-only locals are declared with their features.
The source patches live in `patches/readline/`; vendor files remain pristine.

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
