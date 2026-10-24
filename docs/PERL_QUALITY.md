# Perl modernization and author checks

The supported runtime remains native MSVC Perl 5.44 or later. Public methods,
prototypes, aliases, exports, singleton hash objects, tied attributes, callback
contracts and lazy XS dispatch retain their existing interfaces. Author tools
are development dependencies, not installation prerequisites.

## Running the gates

In a matching Visual Studio Native Tools PowerShell 7 (`pwsh`) session:

```powershell
$env:LC_ALL = 'C'
perl Makefile.PL
nmake
.github/scripts/install-author-tools.ps1
perl script/check-perl.pl
nmake test
perl script/coverage-perl.pl --require-full
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

The installer also temporarily removes repository author/release/extended-test
flags and inherited Perl library, installation and instrumentation overrides.
`AUTOMATED_TESTING` remains enabled in CI. This runs dependencies' normal
installation tests without demanding their optional maintainer-test modules;
it does not disable this project's author or release checks. Temporary files
use a dedicated controlled directory and its Windows short spelling when
available, limiting nested DESTDIR paths in dependency tests. All original
environment values, including unset versus empty values, are restored after
success or failure.
Dependency tests are never forced or bypassed.

CI caches the tested author library separately from Perl. Use
`.github/scripts/install-author-tools.ps1 -VerifyOnly` to validate an existing
completed installation without network access. A missing or stale completion
marker requires a normal installation; it must not be fabricated to bless a
partial library. The verifier uses only the contained author library and Perl's
core libraries, checks exact tool versions, exercises the Critic/PPI/Tidy stack
and calibrates native Devel::Cover. See [CI.md](CI.md#author-dependency-cache)
for cache keys, invalidation, reports and failure recovery.

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

`perl script/coverage-perl.pl --require-full` is the mandatory CI command. It
forces native integration and requires literal 100% statement and branch
coverage for every maintained production Perl source: `Makefile.PL`, all six
`inc/Gnu` modules, `inc/build-native.pl`, both runtime modules, and all seven
scripts, including extensionless `perlsh`. Tests and test support are executed
and pass the same static gates, but are excluded from the coverage denominator.
Inherited examples, vendor code, generated files, dependencies and C/XS are
outside that denominator. Native C, console and dependency checks remain
mandatory and are not represented by the Perl percentage.

The runner first calibrates the pinned native Devel::Cover build using ordinary
branches, postfix exception guards, loops, callbacks and short-circuit logic.
Both statement and branch measurements must be complete. Condition
instrumentation is also enabled: Devel::Cover 1.52 needs it to populate some
branch counters correctly, even though condition coverage is not a target.
Unsupported instrumentation fails explicitly rather than skipping coverage.

Every run creates a fresh database. Absolute source names, an unrelated
filename root and absolute AutoSplit line directives preserve measurements
across console subprocess working directories. Syntax-only compilation children
clear instrumentation so disposable staging cannot replace canonical runtime
source names. Staged copies contribute only when their bytes match the current
maintained source. Installation children clear author libraries and harness
options, so installed smoke tests cannot accidentally use checkout libraries.

Author scripts use named phases because early exceptions in a `do FILE` probe
can discard main-program optrees and falsely report complete coverage. Frozen
per-source statement and branch totals in `config/coverage-baseline.json`
reject missing or truncated measurements. A source change that alters totals
requires reviewing a fresh integrated report and updating those totals; do not
reduce the denominator simply to pass. Zero branches are accepted only for a
loaded source with no branch sites. No source sites are marked uncoverable.
Exact covered and total counts decide success; rounded percentages cannot pass.

Without flags, the runner provides a faster test and per-module regression
check. `--integration` adds actual configuration, native build, release and
fresh archive installation. Only `--require-full` enforces the complete target;
it implies `--integration`. The default command is not a substitute for the CI
gate. Existing 100% module floors remain enforced in every mode.

`build/quality/calibration.json`, `coverage.json`, `coverage-target.json` and
`coverage-tests.log` record calibration, per-source counts, uncovered locations,
failures and subprocess results. CI uploads these with native and archive logs.
Devel::Cover may announce replacement of a reused, non-target generated fixture
file; maintained targets still require matching bytes and exact site totals.
Runner fixtures reject missing metrics, lost totals, excluded sites, partial
coverage, invalid baselines, stale reports, child failures and report I/O
failures. Checker fixtures cover formatting, Critic, POD, syntax, AutoLoader,
configuration and subprocess failures. Fault injection is confined to disposable
fixture children; the mandatory native integration runs real tools.

Coverage is evidence that instrumented paths ran, not proof of all possible
inputs or native behavior. Contract tests assert argument acceptance, context,
prototypes, dispatch, tied variables, callbacks, UTF-8, REPL evaluation and
completion, errors and warnings. Test-local Unix and Tk models exercise Perl
adapters without claiming those platforms or a real Tk integration were tested.
The legacy `rl_tty_set_default_bindings` and
`rl_tty_unset_default_bindings` wrappers retain their existing unavailable-native-symbol errors, with regression tests;
coverage does not imply those historical adapters work.

Native ARM64 and hosted CI require actual runs on their respective machines.
The committed totals were measured with the pinned x64 toolchain; an
architecture-dependent discrepancy must be investigated and recorded, not
silently ignored or used to weaken the full gate.

The 2026-10-24 Windows 11 x64 run of `--require-full` passed all 17 targets:
1,597/1,597 statements and 710/710 branches, with no excluded sites. The run
passed 1,342 instrumented tests, 180 release/author checks and 1,161 extracted
archive tests. All 54 maintained sources passed the static gates. The actual
archive installed and loaded outside its source tree, and DLL imports passed
inspection. See README for the toolchain and unavailable platform validation.
