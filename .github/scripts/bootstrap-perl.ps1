# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$Version, [string]$Sha256, [string]$Prefix, [string]$Cctype)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^5\.\d+\.\d+$' -or $Sha256 -notmatch '^[a-f0-9]{64}$' -or $Cctype -notmatch '^MSVC\d+$') { throw 'Invalid bootstrap matrix values' }
# Perl's native install recipes pass INST_TOP to xcopy, which interprets
# forward slashes in otherwise valid Windows paths as command switches.
$Prefix = [System.IO.Path]::GetFullPath($Prefix).Replace('/', '\')
$archive = Join-Path $env:RUNNER_TEMP "perl-$Version.tar.gz"
Invoke-WebRequest "https://www.cpan.org/src/5.0/perl-$Version.tar.gz" -OutFile $archive
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) { throw 'Perl archive checksum mismatch' }
& "$env:SystemRoot/System32/tar.exe" -xzf $archive -C $env:RUNNER_TEMP
if ($LASTEXITCODE) { throw 'Cannot extract Perl source' }
Push-Location "$env:RUNNER_TEMP/perl-$Version/win32"
try {
    $argsList = @('/nologo', "CCTYPE=$Cctype", "CCHOME=$($env:VCToolsInstallDir.TrimEnd('\'))", "INST_TOP=$Prefix", 'WIN64=define', 'USE_ITHREADS=define', 'USE_MULTI=define', 'USE_IMP_SYS=define')
    & nmake @argsList
    if ($LASTEXITCODE) { throw 'Native MSVC Perl build failed' }
    & nmake @argsList install
    if ($LASTEXITCODE) { throw 'Native Perl installation failed' }
} finally { Pop-Location }
