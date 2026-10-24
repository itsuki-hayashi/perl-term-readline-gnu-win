# CI matrix and evidence

Each row in `.github/workflows/windows.yml` specifies runner, architecture,
Perl version/checksum, Visual Studio major version, toolset and Perl CCTYPE.
Extend explicit rows for future supported versions. Avoid moving `latest`
labels without reviewing the actual environment.

The x64 hosted runner uses Windows Server 2025; ARM64 uses Windows 11.
Server coverage does not prove Windows 11 x64 coverage, which is locally
tested. An optional self-hosted x64 row can use labels for a maintained
Windows 11 client. Do not expose privileged personal runners to untrusted PRs.

PowerShell provisioning initializes MSVC and builds checksum-pinned Perl with
its native `nmake` makefile. These CI tools are not end-user installation dependencies.
Preinstalled MinGW/MSYS2 programs must not become target build dependencies.

The Perl cache key includes source digest, architecture, exact toolset, SDK
and shared/threaded/release configuration. Every run checks `Config` compiler
and architecture. ARM64 validation requires ARM64 Perl, not x64 emulation.
Bump cache revision when provisioning behavior changes. Actions use pinned
release commit IDs.

Jobs test the checkout and a fresh archive, use installation paths containing
spaces, inspect imports and exercise installed code outside the source tree.
Logs, target configuration and candidate archives are retained as artifacts,
including on failure. The workflow has read-only repository permissions,
bounded jobs, no CPAN credentials, and no automatic upload.

Both rows must pass before claiming dual-architecture release validation.
Creating a workflow file is not itself an ARM64 test result.

Both rows install pinned author tools separately from the cached native Perl,
then enforce Perl formatting, severity-1 static analysis, POD, staged compilation
and literal 100% statement/branch coverage with
`perl script/coverage-perl.pl --require-full`. The gate includes all maintained
production Perl and rejects missing measurements or changed site totals; tests
run under instrumentation but are excluded from the denominator. Native tests, release checks and archive
installation remain mandatory. `build/quality` reports join the existing
artifacts. See [PERL_QUALITY.md](PERL_QUALITY.md) for exact scope and exceptions.
Configuring required merge statuses is a repository branch-protection setting.

## Author dependency cache

Both architectures restore `build/author` independently of native Perl. The
author key contains the centrally computed native Perl key (source checksum,
architecture, exact compiler toolset, SDK and shared/threaded/release settings),
CCTYPE, and a hash of the author inventory, installer, Perl bootstrap script,
author dependency patches and Perl patch applicator.
Only exact matches are restored; there are no fallback keys or cross-OS caches.
The native Perl key itself remains unchanged by this addition.

On a miss, `install-author-tools.ps1` installs the pinned tools and their
dependencies with normal CPAN tests enabled, then verifies the library. The
separate cache save action runs immediately after successful verification, so
later project failures do not discard tested dependencies. Bootstrap downloads,
cpanm work trees, scratch directories and logs are outside the cache payload.

On a hit, `install-author-tools.ps1 -VerifyOnly` makes no bootstrap downloads or
cpanm calls. It checks the completion marker against the installer, inventory
and actual native Perl configuration, loads all ten pinned modules from the
contained library without unrelated site modules, constructs the strict Critic
profile, and calibrates Devel::Cover's native statement/branch instrumentation.
All project quality, coverage, native, release and archive gates still run.

Path::Tiny 0.150 is explicitly pinned because its Windows symlink tests fail
when the runner has symlink privileges: `readlink` returns backslashes, and
`mkdir` resolves `..` before traversing a directory symlink. The installer
checks the upstream archive SHA256, extracts a build copy, and applies
`patches/author/0001-path-tiny-windows-tests.patch` using `Gnu::Patch`.
The patch normalizes three target comparisons and creates the missing physical
directory fixture. All assertions and dependency tests remain enabled; runtime
sources and upstream license notices are unchanged. Patch or applicator changes
invalidate both the cache key and completion marker.
The installer repacks a fresh patched copy as a local archive because cpanm
1.7049 does not recognize drive-letter absolute directories as local sources.
Downloaded archives and extracted or patched copies are outside the cache.

An invalid cache fails explicitly and names its key. Delete that author-tool
entry under the repository's Actions caches and rerun. To refresh transitive
dependencies without changing direct pins, bump the `author-tools-v1` revision
in the cache-key step. Direct pins and scripts invalidate the key automatically;
the cache is not a complete transitive dependency lock.

Installer fixtures run on every job without CPAN or external test frameworks.
`build/quality/author-tools.json` records the latest validation and elapsed time;
`author-install.log` and cpanm's detailed `build.log` files retain failure
diagnostics. These join the existing always-uploaded artifacts. Hosted cold/warm
cache behavior and native ARM64 results require actual runs on those runners.

Local Windows 11 x64 validation on 2026-10-24 passed 119 installer fixtures and a
clean, normally tested 73-distribution installation (791.695 seconds). A copy
of only the completed library verified offline in 5.477 seconds; copying took
5.987 seconds. Missing-module rejection and subsequent recovery also passed.
These measurements exclude hosted cache transfer/extraction and do not claim a
GitHub cache-service or ARM64 run. Detailed evidence is in
`build/quality/author-cache-validation.json`; the full project gate passed with
all 17 Perl targets at 100% statements and branches.
