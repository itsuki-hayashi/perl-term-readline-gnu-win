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
its native `nmake` makefile. These CI tools are not CPAN installation dependencies.
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
