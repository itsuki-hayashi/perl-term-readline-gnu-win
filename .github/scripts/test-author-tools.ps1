# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
# Dependency-free fixtures: no CPAN downloads and no preinstalled author tools.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
. "$PSScriptRoot/install-author-tools.ps1"
$script:checks = 0
$script:installs = 0
$script:verifications = 0
$fixture = Join-Path $root ('build/author-fixtures-' + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path "$fixture/config", "$fixture/.github/scripts" -Force | Out-Null
Copy-Item -LiteralPath "$root/config/author-tools.json" -Destination "$fixture/config/author-tools.json"
Copy-Item -LiteralPath "$root/.github/scripts/install-author-tools.ps1" -Destination "$fixture/.github/scripts/install-author-tools.ps1"
Copy-Item -LiteralPath "$root/.perlcriticrc" -Destination "$fixture/.perlcriticrc"
New-Item -ItemType Directory -Path "$fixture/patches/author", "$fixture/inc/Gnu" -Force | Out-Null
Copy-Item "$root/patches/author/*.patch" "$fixture/patches/author/"
Copy-Item -LiteralPath "$root/inc/Gnu/Patch.pm" -Destination "$fixture/inc/Gnu/Patch.pm"
$marker = Join-Path $fixture 'build/author/.author-tools-complete.json'

function Assert-Author {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw "FAIL: $Message" }
    $script:checks++
}

function Assert-AuthorFailure {
    param([scriptblock]$Action, [string]$Pattern)
    $message = $null
    try { & $Action } catch { $message = $_.Exception.Message }
    Assert-Author ($null -ne $message -and $message -match $Pattern) "Expected failure $Pattern, received '$message'"
}

function Invoke-AuthorScenario {
    param([string]$Scenario = 'success', [switch]$VerifyOnly)
    function Get-AuthorIdentity {
        param($Scripts, $Directory, $Log)
        if ($Scenario -eq 'identity-fails') { throw 'fixture native identity failure' }
        return [pscustomobject]@{ archname = 'fixture-native'; version = '5.44.0'; cc = 'cl' }
    }
    function Install-AuthorDependencies {
        param($Root, $Prefix, $Tools, $Log)
        $script:installs++
        Assert-Author (!$env:RELEASE_TESTING -and !$env:AUTHOR_TESTING -and !$env:EXTENDED_TESTING) 'maintainer flags isolated'
        Assert-Author ($env:AUTOMATED_TESTING -eq '1') 'automated testing preserved'
        foreach ($name in @('NO_COLOR', 'ANSI_COLORS_DISABLED', 'PERL5LIB', 'PERL5OPT', 'PERL_LOCAL_LIB_ROOT',
            'PERL_MB_OPT', 'PERL_MM_OPT', 'PERL_CPANM_OPT', 'HARNESS_PERL_SWITCHES', 'DEVEL_COVER_OPTIONS')) {
            Assert-Author ($null -eq [Environment]::GetEnvironmentVariable($name, 'Process')) "$name isolated"
        }
        Assert-Author ($env:TEMP -eq $env:TMP -and $env:TMP -eq $env:TMPDIR -and (Test-Path -LiteralPath $env:TEMP)) 'controlled scratch directory exists'
        Assert-Author ($env:PERL_CPANM_HOME -eq (Join-Path $Root 'build/author-cpanm')) 'contained cpanm work directory'
        Assert-Author (!(Test-Path -LiteralPath $marker)) 'old completion marker removed before installation'
        New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
        if ($Scenario -eq 'install-fails') {
            $work = Join-Path $env:PERL_CPANM_HOME 'work/current'
            New-Item -ItemType Directory -Path $work -Force | Out-Null
            'fixture detailed dependency failure' | Set-Content -LiteralPath "$work/build.log"
            throw 'fixture cpanm failure'
        }
    }
    function Test-AuthorLibrary {
        param($Root, $Prefix, $Scripts, $Directory, $Log)
        $script:verifications++
        if ($Scenario -eq 'verify-fails') { throw 'fixture incomplete library' }
        return @{
            tools = [pscustomobject]@{ Fixture = [pscustomobject]@{ version = '1' } }
            calibration = [pscustomobject]@{ statement = @{ covered = 1; total = 1 }; branch = @{ covered = 2; total = 2 } }
        }
    }
    Invoke-AuthorTools -Root $fixture -VerifyOnly:$VerifyOnly
}

# Exercise both null and empty values and restore the test caller's environment.
$names = @('RELEASE_TESTING', 'AUTHOR_TESTING', 'EXTENDED_TESTING', 'AUTOMATED_TESTING', 'NO_COLOR', 'ANSI_COLORS_DISABLED',
    'PERL5LIB', 'PERL5OPT', 'PERL_LOCAL_LIB_ROOT', 'PERL_MB_OPT', 'PERL_MM_OPT', 'PERL_CPANM_OPT',
    'HARNESS_PERL_SWITCHES', 'DEVEL_COVER_OPTIONS', 'PERL_CPANM_HOME', 'TEMP', 'TMP', 'TMPDIR')
$original = @{}
$expected = @{}
foreach ($name in $names) {
    $original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    $expected[$name] = 'fixture-value'
}
$expected.AUTOMATED_TESTING = '1'
$expected.NO_COLOR = ''
$expected.ANSI_COLORS_DISABLED = $null
try {
    foreach ($name in $names) {
        if ($null -eq $expected[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $expected[$name], 'Process') }
    }
    Invoke-AuthorScenario
    Assert-Author (Test-Path -LiteralPath $marker) 'successful installation creates marker'
    Invoke-AuthorScenario -VerifyOnly
    Assert-Author ($script:installs -eq 1 -and $script:verifications -eq 2) 'warm verification never invokes installation'
    foreach ($name in $names) {
        Assert-Author ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $expected[$name]) "$name restored on success"
    }
    $completed = Get-Content -LiteralPath $marker -Raw
    foreach ($inputFile in @("$fixture/patches/author/0001-path-tiny-windows-tests.patch", "$fixture/inc/Gnu/Patch.pm")) {
        $bytes = [IO.File]::ReadAllBytes($inputFile)
        try {
            [IO.File]::AppendAllText($inputFile, "`nfixture change`n")
            Assert-AuthorFailure { Invoke-AuthorScenario -VerifyOnly } 'Invalid author-tool cache.*does not match'
        } finally { [IO.File]::WriteAllBytes($inputFile, $bytes) }
    }
    foreach ($field in @('configuration', 'installer', 'perl', 'schema')) {
        $bad = $completed | ConvertFrom-Json
        if ($field -eq 'perl') { $bad.perl.archname = 'another-architecture' } else { $bad.$field = 'invalid' }
        $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $marker
        Assert-AuthorFailure { Invoke-AuthorScenario -VerifyOnly } 'Invalid author-tool cache.*does not match'
    }
    'malformed JSON' | Set-Content -LiteralPath $marker
    Assert-AuthorFailure { Invoke-AuthorScenario -VerifyOnly } 'Invalid author-tool cache'
    Remove-Item -LiteralPath $marker
    Assert-AuthorFailure { Invoke-AuthorScenario -VerifyOnly } 'Missing author-tool completion marker'
    $completed | Set-Content -LiteralPath $marker
    Assert-AuthorFailure { Invoke-AuthorScenario -VerifyOnly -Scenario 'verify-fails' } 'incomplete library'
    Assert-AuthorFailure { Invoke-AuthorScenario -Scenario 'install-fails' } 'fixture cpanm failure'
    Assert-Author (!(Test-Path -LiteralPath $marker)) 'failed installation cannot retain marker'
    Assert-Author ((Get-Content -LiteralPath "$fixture/build/quality/author-install.log" -Raw) -match 'fixture detailed dependency failure') 'full dependency diagnostics retained'
    Assert-AuthorFailure { Invoke-AuthorScenario -Scenario 'verify-fails' } 'incomplete library'
    Assert-Author (!(Test-Path -LiteralPath $marker)) 'failed verification cannot create marker'
    Assert-AuthorFailure { Invoke-AuthorScenario -Scenario 'identity-fails' } 'native identity failure'
    foreach ($name in $names) {
        Assert-Author ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $expected[$name]) "$name restored on failure"
    }
    $report = Get-Content -LiteralPath "$fixture/build/quality/author-tools.json" -Raw | ConvertFrom-Json
    Assert-Author ($report.status -eq 'failed' -and $report.error -match 'identity') 'failure report replaces previous success'
} finally {
    foreach ($name in $names) {
        if ($null -eq $original[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process') }
    }
}

# Bootstrap failures do not require network access to reproduce.
& {
    function Receive-AuthorBootstrap { param($Archive); throw 'fixture download failure' }
    Assert-AuthorFailure { Initialize-AuthorBootstrap -Root $fixture -Log "$fixture/bootstrap.log" } 'download failure'
}
& {
    function Receive-AuthorBootstrap { param($Archive); 'invalid archive' | Set-Content -LiteralPath $Archive }
    Assert-AuthorFailure { Initialize-AuthorBootstrap -Root $fixture -Log "$fixture/bootstrap.log" } 'checksum mismatch'
}
& {
    function Receive-AuthorBootstrap { param($Archive); 'fixture archive' | Set-Content -LiteralPath $Archive }
    function Get-FileHash { param($LiteralPath, $Algorithm); return @{ Hash = 'b9ffb88e62a06aa91bd7d5a28ef6bdbb942608aea90e3969aa29b33640035214' } }
    function Invoke-AuthorNative { param($Program, $Arguments, $Log); throw 'fixture extraction failure' }
    Assert-AuthorFailure { Initialize-AuthorBootstrap -Root $fixture -Log "$fixture/bootstrap.log" } 'extraction failure'
}
& {
    function Initialize-AuthorBootstrap { param($Root, $Log); return @{ library = 'fixture-library'; cpanm = 'fixture-cpanm' } }
    function Initialize-AuthorPathTiny { param($Root, $Log); return "$Root/staged-Path-Tiny-0.150.tar.gz" }
    function Invoke-AuthorNative {
        param($Program, $Arguments, $Log)
        Assert-Author ($Program -eq 'perl' -and $Arguments -contains '--local-lib-contained') 'contained cpanm invocation'
        Assert-Author ($Arguments -notcontains '--notest' -and $Arguments -notcontains '--force') 'dependency tests cannot be bypassed'
        Assert-Author (($Arguments | Where-Object { $_ -like '*.tar.gz' }).Count -eq 10) 'all ten pinned distributions requested'
        Assert-Author ($Arguments.IndexOf("$fixture/staged-Path-Tiny-0.150.tar.gz") -lt $Arguments.IndexOf('D/DB/DBOOK/Perl-Critic-Community-v1.0.4.tar.gz')) 'tested Path::Tiny archive precedes dependent tools'
    }
    $tools = Get-Content -LiteralPath "$fixture/config/author-tools.json" -Raw | ConvertFrom-Json
    Install-AuthorDependencies -Root $fixture -Prefix "$fixture/build/author" -Tools $tools -Log "$fixture/cpanm.log"
    $tools.distributions.PSObject.Properties.Remove('PPI')
    Assert-AuthorFailure { Install-AuthorDependencies -Root $fixture -Prefix "$fixture/build/author" -Tools $tools -Log "$fixture/cpanm.log" } 'Missing pinned distribution for PPI'
    Assert-AuthorFailure { Install-AuthorDependencies -Root $fixture -Prefix "$fixture/build/author" -Tools ([pscustomobject]@{ required = [pscustomobject]@{}; coverage = [pscustomobject]@{} }) -Log "$fixture/cpanm.log" } 'Empty author-tool inventory'
}

# Actual Perl subprocesses check exit propagation and verifier isolation.
$patchSource = Join-Path $fixture 'patch-source'
New-Item -ItemType Directory -Path "$patchSource/t", "$patchSource/lib" -Force | Out-Null
$filesystem = (@('') * 464) + @(
    '    is readlink($link2), $link, ''symbolic link is available after spewing'';',
    '    is readlink($link),  $file, ''symbolic link is available after spewing'';')
$symlinks = (@('') * 26) + '    is readlink $bar, "../foo", "the link seems right";'
$relative = (@('') * 186) + '    $expect = $path->relative( $deep->parent->child("F/G")->realpath );'
[IO.File]::WriteAllText("$patchSource/t/filesystem.t", ($filesystem -join "`n") + "`n")
[IO.File]::WriteAllText("$patchSource/t/symlinks.t", ($symlinks -join "`n") + "`n")
[IO.File]::WriteAllText("$patchSource/t/rel-abs.t", ($relative -join "`n") + "`n")
'unchanged runtime' | Set-Content -LiteralPath "$patchSource/lib/runtime.txt"
$patchArguments = @("-I$root/inc", '-MGnu::Patch', '-e', 'Gnu::Patch::apply(@ARGV)',
    $patchSource, "$root/patches/author/0001-path-tiny-windows-tests.patch")
Invoke-AuthorNative -Program 'perl' -Arguments $patchArguments -Log "$fixture/patch.log"
Assert-Author ((Get-Content "$patchSource/t/filesystem.t" -Raw) -match 'path\(readlink\(\$link2\)\)') 'absolute symlink assertions normalize Windows separators'
Assert-Author ((Get-Content "$patchSource/t/symlinks.t" -Raw) -match 'path\(readlink \$bar\)') 'relative symlink assertion normalizes Windows separators'
Assert-Author ((Get-Content "$patchSource/t/rel-abs.t" -Raw) -match '\$deep->parent->child\("F/G"\)->mkdir;') 'physical relative-path fixture exists on Windows'
Assert-Author ((Get-Content "$patchSource/t/rel-abs.t" -Raw) -match '\$deep->parent->child\("F/G"\)->realpath') 'original symlink resolution assertion remains enabled'
Assert-Author ((Get-Content "$patchSource/lib/runtime.txt" -Raw).Trim() -eq 'unchanged runtime') 'dependency runtime files remain unchanged'
Assert-AuthorFailure { Invoke-AuthorNative -Program 'perl' -Arguments $patchArguments -Log "$fixture/patch.log" } 'Author command failed'
& {
    function Invoke-WebRequest { param($Uri, $OutFile); 'invalid archive' | Set-Content -LiteralPath $OutFile }
    Assert-AuthorFailure { Initialize-AuthorPathTiny -Root $fixture -Log "$fixture/patch.log" } 'archive checksum mismatch'
}
& {
    function Invoke-WebRequest { param($Uri, $OutFile); throw 'fixture Path::Tiny download failure' }
    Assert-AuthorFailure { Initialize-AuthorPathTiny -Root $fixture -Log "$fixture/patch.log" } 'Path::Tiny download failure'
}
$directory = Join-Path $fixture 'native probes with spaces'
New-Item -ItemType Directory -Path $directory | Out-Null
$scripts = New-AuthorVerificationScripts -Directory $directory
$alias = Get-AuthorScratchPath -Scripts $scripts -Directory $directory -Log "$fixture/native.log"
'scratch identity' | Set-Content -LiteralPath "$directory/scratch-marker.txt"
Assert-Author ((Get-Content -LiteralPath (Join-Path $alias 'scratch-marker.txt') -Raw).Trim() -eq 'scratch identity') 'short scratch spelling addresses the same directory'
Assert-Author ($alias.Length -le $directory.Length) 'scratch spelling does not lengthen nested dependency paths'
$identity = Get-AuthorIdentity -Scripts $scripts -Directory $directory -Log "$fixture/native.log"
Assert-Author ($identity.cc -eq 'cl' -and $identity.archname -match '^MSWin32-(x64|arm64)-') 'actual native Perl identity'
'exit 7;' | Set-Content -LiteralPath "$directory/exit.pl"
Assert-AuthorFailure { Invoke-AuthorNative -Program 'perl' -Arguments @("$directory/exit.pl") -Log "$fixture/native.log" } 'failed \(7\)'
$empty = Join-Path $fixture 'empty-library'
New-Item -ItemType Directory -Path "$empty/lib/perl5/Fixture" -Force | Out-Null
$manifest = Join-Path $directory 'tools.json'
$arguments = @($scripts.helper, 'verify', $empty, $manifest, "$fixture/.perlcriticrc", "$directory/output.json")
'{"required":{"Fixture::Missing":"1"},"coverage":{}}' | Set-Content -LiteralPath $manifest
Assert-AuthorFailure { Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log "$fixture/native.log" } 'Author command failed'
Assert-Author ((Get-Content -LiteralPath "$fixture/native.log" -Raw) -match 'Fixture/Missing.pm') 'missing module cannot fall back to installed author library'
'package Fixture::Version; our $VERSION=1; 1;' | Set-Content -LiteralPath "$empty/lib/perl5/Fixture/Version.pm"
'{"required":{"Fixture::Version":"2"},"coverage":{}}' | Set-Content -LiteralPath $manifest
Assert-AuthorFailure { Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log "$fixture/native.log" } 'Author command failed'
Assert-Author ((Get-Content -LiteralPath "$fixture/native.log" -Raw) -match '2 required, found 1') 'wrong version rejected'
'{"required":{"strict":"1.06"},"coverage":{}}' | Set-Content -LiteralPath $manifest
# Use the actual core version so the ownership check, rather than version check, fails.
$version = & perl -Mstrict -e 'print $strict::VERSION'
@{ required = @{ strict = $version }; coverage = @{} } | ConvertTo-Json | Set-Content -LiteralPath $manifest
Assert-AuthorFailure { Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log "$fixture/native.log" } 'Author command failed'
Assert-Author ((Get-Content -LiteralPath "$fixture/native.log" -Raw) -match 'outside author library') 'core/site fallback is not accepted as an owned tool'

$workflow = Get-Content -LiteralPath "$root/.github/workflows/windows.yml" -Raw
Assert-Author ($workflow -match 'actions/cache/restore@' -and $workflow -match 'actions/cache/save@') 'independent dependency restore/save actions'
Assert-Author ($workflow -notmatch 'restore-keys:' -and $workflow -match 'author-tools-v1-\$native-') 'exact dependency cache uses native Perl identity'
Assert-Author ($workflow -match "cache-hit != 'true'" -and $workflow -match "cache-hit == 'true'") 'cold and warm paths are conditional'
Assert-Author ($workflow.IndexOf('Save tested Perl author tools') -lt $workflow.IndexOf('Enforce Perl formatting')) 'verified dependencies saved before unrelated project gates'
@{ checks = $script:checks; status = 'passed' } | ConvertTo-Json |
    Set-Content -LiteralPath "$fixture/results.json" -Encoding utf8NoBOM
# Expected negative subprocesses must not leak a failure exit code to Actions.
Invoke-AuthorNative -Program 'perl' -Arguments @('-e', 'exit 0') -Log "$fixture/native.log"
Write-Host "$($script:checks) author-installer checks passed; evidence in $fixture"
