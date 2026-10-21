# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('x64','arm64')][string]$Architecture, [int]$VisualStudio, [string]$Toolset)
$ErrorActionPreference = 'Stop'
$before = @{}
Get-ChildItem Env: | ForEach-Object { $before[$_.Name] = $_.Value }
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
if (!(Test-Path $vswhere)) { $vswhere = "$env:ProgramFiles/Microsoft Visual Studio/Installer/vswhere.exe" }
$vs = & $vswhere -latest -products '*' -version "[$VisualStudio.0,$($VisualStudio+1).0)" -property installationPath
if (!$vs) { throw "Visual Studio $VisualStudio unavailable" }
$target = if ($Architecture -eq 'arm64') {'arm64'} else {'amd64'}
$hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {'arm64'} else {'amd64'}
$batch = Join-Path $env:RUNNER_TEMP 'gnuwin32-toolchain.cmd'
@"
@echo off
call "$vs/Common7/Tools/VsDevCmd.bat" -no_logo -arch=$target -host_arch=$hostArch -vcvars_ver=$Toolset >nul
if errorlevel 1 exit /b 1
set
"@ | Set-Content $batch
$lines = & $env:ComSpec /d /c call $batch
if ($LASTEXITCODE) { throw 'MSVC setup failed' }
foreach ($line in $lines) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process')
        if ($Matches[1] -notmatch '^(?:GITHUB_|RUNNER_|NODE_OPTIONS$)' -and $before[$Matches[1]] -ne $Matches[2]) {
            "$($Matches[1])=$($Matches[2])" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
        }
    }
}
"tools=$($env:VCToolsVersion.TrimEnd('\'))" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
"sdk=$($env:WindowsSDKVersion.TrimEnd('\'))" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
