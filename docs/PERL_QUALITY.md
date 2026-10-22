# Perl modernization and author checks

The supported runtime remains native MSVC Perl 5.44 or later. Public methods,
prototypes, aliases, exports, singleton hash objects, tied attributes, callback
contracts and lazy XS dispatch retain their existing interfaces. Author tools
are development dependencies, not installation prerequisites.

## Running the gates

In a matching Visual Studio Native Tools PowerShell session:

```powershell
$env:LC_ALL = 'C'
perl Makefile.PL
nmake
.github/scripts/install-author-tools.ps1
perl script/check-perl.pl
nmake test
perl script/coverage-perl.pl
perl script/release.pl
perl script/test-archive.pl
```

The installer verifies the SHA-256 of cpanminus 1.7049, installs the versions
in `config/author-tools.json` under `build/author`, and runs dependency tests.
The check scripts locate this local library automatically. The native Perl
cache and runtime metadata do not acquire author-only prerequisites. The direct
tool versions and PPI parser are pinned; transitive CPAN dependencies are not
a complete dependency lock. Review and rerun both architectures when updating.
The contained installation also avoids relying on author modules already in
the developer's site library. Module::Pluggable is pinned to 6.3 because 6.4's
extra install hook fails native installation here. Color-test preferences are
cleared temporarily during dependency tests and restored afterwards.

`script/check-perl.pl` discovers `Makefile.PL`, maintained `.pm`, `.pl` and `.t`
files under `lib`, `inc`, `script`, `t` and `xt`, and extensionless
`script/perlsh`. It excludes inherited examples, vendor sources, patches,
generated XS C, build output and third-party author dependencies. Optional
integration tests are compiled without requiring their optional runtime
dependencies to be installed. Existing runtime skips remain visible.

Every discovered source must pass pinned Perl::Tidy formatting, the Critic
profile, POD error/warning checks and subprocess compilation. Formatting checks
do not rewrite sources. To format an edited file deliberately:

```powershell
perl -Ibuild/author/lib/perl5 -MPerl::Tidy -e 'exit Perl::Tidy::perltidy()' -- -b path/to/file.pl
```

The runner stages current sources in a disposable directory because `perl -c`
executes `BEGIN` blocks and imports. The backend is loaded through
`Term::ReadLine` using the built native extension. AutoSplit generates staged
`.al` files and every AutoLoader routine is compiled in its real loading scope.
For static analysis, replacing only the `__END__` marker exposes those bodies
to PPI without changing diagnostic line numbers. Tidy's AutoLoader option also
formats those bodies. Plain `perlcritic lib` would miss them and incorrectly
report their shared scratch lexicals as unused.

The historical AutoSplit warning about names sharing their first eight
characters is expected; supported Windows filesystems retain the full names.
The checked API fixture contains the original subroutine prototypes, including
their observable whitespace, rather than treating prototypes as signatures.

Reports are written under `build/quality` and retained by CI. The workflow
runs these gates on both existing native architectures. Repository owners must
configure branch protection to require the resulting job statuses.

## Policy decisions

`.perlcriticrc` starts with all core policies at severity 1 and explicitly
includes selected policies from Community, Bangs, StricterSubs and Pulp.
The report lists the policies actually enabled. Unselected plugin policies do
not become active merely because another plugin collection is installed.

* Community adds strict/warnings, conditional declaration, `each`, indirect
  syntax, multidimensional-array emulation and POSIX-import checks.
* Bangs adds no-plan, ref/prototype ambiguity and useless-regex-modifier checks.
* StricterSubs checks exports of undeclared functions. Its undeclared-call and
  unexported-call checks cannot model this backend's XS registration, generated
  aliases, AutoLoader and AUTOLOAD dispatch reliably, so they are not enabled.
* Pulp adds final POD-cut and duplicate-see-also checks. Other documentation
  heuristics can mistake Readline function signatures and inherited reference
  text for prose errors; POD syntax and warnings are checked directly.
* Perl::Critic::PJCJ v0.3.0 was reviewed and attempted locally. Its generated
  Makefile fails native nmake with U1035. It is not a required dependency, and
  its tests were not forced or bypassed. Tidy provides the formatting gate.
* Moose-specific policies and runtime type frameworks are inapplicable to the
  existing compatible object representation. These checks do not provide
  whole-program static typing.

Profile exclusions have adjacent explanations. Formatting style is delegated
to one Tidy configuration; there is no second, conflicting Tidy Critic policy.
Other exclusions avoid changing existing return contexts, public package state,
names, regex byte/text semantics and interleaved API documentation merely to
satisfy a style preference. The complexity limit remains 20; the patch parser
was split into a file parser and a hunk helper instead of exempting it.

Necessary compatibility exceptions name individual policies and explain why:
dynamic symbol lookup, existing prototypes, intentional persistent console
state, tied attributes and REPL evaluation. The gate rejects blanket or
unexplained `no critic` comments. Ordinary warnings remain enabled; suppressions
name their categories. Global fatal warnings would change caller behavior.
The new dispatch regressions explicitly assert that no unexpected warnings
are emitted.

## Language-feature review

The modernization reviewed installed perldeltas from 5.10 through 5.44 and the
installed `feature`, `builtin`, `perlsub`, `perlintro`, `perlreftut`, `perldsc`,
`perlootut`, `perlclass`, `perlre`, `perlexperiment` and `source::encoding`
documentation. Consult the target interpreter's `perldoc`, rather than assuming
that a feature introduced in a release is already stable. These are the main
applicable decisions:

| Feature family | Decision |
| --- | --- |
| Version bundles, lexical variables, defined-or, state | Establish 5.44 throughout; retain existing state lifetimes and defined/false distinctions. Do not replace caller-visible globals with private state. |
| Stable signatures since 5.36 | Use for new private helpers and a compatible slurp helper; retain public prototypes and permissive arguments. Defaults and ignored trailing arguments preserve accepted calls. |
| Stable postfix dereferencing | Use in new helpers, checks and tests. Preserve reference aliases where mutation is intentional. |
| Stable multi-variable foreach and `builtin::indexed` | Use for author-tool inventories and licensing evidence; indexed preserves line numbering and values. |
| Explicit imports and direct method syntax | Declare required imports and use `Class->new`; preserve Carp's original exported names. |
| Unicode strings, source encoding and bitwise bundles | Audit effects instead of changing byte protocols. The binary UTF-8 fixture explicitly disables source-encoding enforcement to retain byte literals. Readline state flags keep their numeric meanings. |
| REPL lexical feature environment | Use compile-time `require v5.44`, followed by existing strict/warnings, rather than enabling a new bundle in user expressions. Retain POSIX's existing exports for startup-file compatibility. |
| Stable `try`, lexical subs, `isa`, distinguished booleans and other builtins | Available where useful, but no forced substitution for `$@`, exception timing, dynamic lookup, `ref`, or observable scalar representations. |
| Experimental classes, named signature parameters, reference alias declarations, enhanced `/xx`, `any`/`all`, `defer` | Not introduced. Their availability does not justify experimental dependencies or a new object/type system. |

Keep comments about historical API behavior where they still explain a contract.
Obsolete Perl 5.8 test shims have been removed; old release references in the
inherited API manual remain historical documentation, not supported targets.
Licensing evidence remains byte-oriented: its JSON now escapes non-ASCII source
bytes rather than emitting potentially invalid UTF-8 or guessing a vendor file's
encoding. The recorded values and vendor sources are preserved.

## Coverage and limits

`script/coverage-perl.pl` first calibrates the pinned native Devel::Cover build
with a small program exercising both sides of an `if`. Statement and branch
instrumentation must each report 100% for that probe. Unsupported instrumentation
fails explicitly and writes calibration evidence; it is not silently skipped.

The runner then executes the complete Perl/native suite and author-tool
regressions with statement and branch instrumentation. Every run uses a fresh
database, so earlier runs cannot inflate the result. Baseline comparison is
per module, fails on missing measurements, and has regression tests for both
missing and reduced coverage. `config/coverage-baseline.json` records measured
minimum percentages rounded down to two decimal places, not an arbitrary target.

These are initial non-regression floors, not claims of comprehensive coverage.
Some branch floors are zero. Optional Tk, exceptional OS/I/O paths, unexercised
build-tool routines and some native callbacks still need additional testing.
Toolchain provisioning and release/update scripts are compiled and linted but
do not have runtime coverage baselines. C/XS coverage is not measured by this
Perl tool; native tests and dependency inspection remain separate requirements.
The tool also undercounts some exception guards: a local probe exercising both
outcomes of a postfix `die if` still reported that guard uncovered. Reported
percentages are comparable instrumentation measurements, not proof that such
guards lack tests. No branches are marked uncoverable to improve the numbers.
Do not lower a floor to obtain a green build. Review changed measurements,
add behavior tests, and record actual platform evidence when updating a floor.
