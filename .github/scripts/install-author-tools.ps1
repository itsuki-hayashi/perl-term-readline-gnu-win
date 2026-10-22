# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$bootstrap = Join-Path $root 'build/author-bootstrap'
New-Item -ItemType Directory -Force $bootstrap | Out-Null
$archive = Join-Path $bootstrap 'App-cpanminus-1.7049.tar.gz'
Invoke-WebRequest 'https://cpan.metacpan.org/authors/id/M/MI/MIYAGAWA/App-cpanminus-1.7049.tar.gz' -OutFile $archive
$expected = 'b9ffb88e62a06aa91bd7d5a28ef6bdbb942608aea90e3969aa29b33640035214'
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Author-tool bootstrap checksum mismatch'
}
& "$env:SystemRoot/System32/tar.exe" -xzf $archive -C $bootstrap
if ($LASTEXITCODE) { throw 'Cannot extract author-tool bootstrap' }
$cpanm = Join-Path $bootstrap 'App-cpanminus-1.7049/bin/cpanm'
$bootstrapLib = Join-Path $bootstrap 'App-cpanminus-1.7049/lib'
$tools = Get-Content (Join-Path $root 'config/author-tools.json') -Raw | ConvertFrom-Json
$modules = @()
foreach ($group in @($tools.required, $tools.coverage)) {
    foreach ($entry in $group.PSObject.Properties) {
        $distribution = $tools.distributions.PSObject.Properties[$entry.Name]
        if (-not $distribution) { throw "Missing pinned distribution for $($entry.Name)" }
        $modules += $distribution.Value
    }
}
# Author tools stay out of runtime prerequisites and the native Perl cache.
# Dependency tests stay enabled; never use --notest or --force here.
# Color-library tests assert ANSI sequences; inherited display preferences
# must not disable the behavior those dependency tests are exercising.
$savedColor = @{}
$savedCpanmHome = $env:PERL_CPANM_HOME
$env:PERL_CPANM_HOME = Join-Path $root 'build/author-cpanm'
foreach ($name in @('NO_COLOR', 'ANSI_COLORS_DISABLED')) {
    $savedColor[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
}
try {
    & perl "-I$bootstrapLib" $cpanm --local-lib-contained (Join-Path $root 'build/author') --mirror 'https://cpan.metacpan.org' --mirror-only @modules
    if ($LASTEXITCODE) { throw 'Pinned author-tool installation failed' }
} finally {
    if ($null -eq $savedCpanmHome) {
        Remove-Item -LiteralPath Env:PERL_CPANM_HOME -ErrorAction SilentlyContinue
    } else {
        $env:PERL_CPANM_HOME = $savedCpanmHome
    }
    foreach ($name in $savedColor.Keys) {
        if ($null -eq $savedColor[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $savedColor[$name], 'Process')
        }
    }
}
