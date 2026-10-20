#requires -Version 7.3
[CmdletBinding()]
param(
    [string]$Perl,
    [string]$BuildDir = (Join-Path $PSScriptRoot 'build'),
    [string]$InstallPrefix = (Join-Path $PSScriptRoot 'stage'),
    [switch]$Install,
    [switch]$LibrariesOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments 2>&1 | Tee-Object -FilePath $script:BuildLog -Append
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
if (!$Perl) {
    # Sandboxed shells can redirect LOCALAPPDATA. Also consider the real profile.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/Perl/bin/perl.exe'),
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData/Local/Programs/Perl/bin/perl.exe'),
        'C:/Program Files/Perl/bin/perl.exe'
    )
    $Perl = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$Perl -or !(Test-Path -LiteralPath $Perl)) { throw 'Specify -Perl with the path to an MSVC-built perl.exe.' }
$Perl = (Resolve-Path -LiteralPath $Perl).Path
$savedLocale = $env:LC_ALL
$savedPath = $env:PATH
$savedPerl5Lib = $env:PERL5LIB
$savedTestPerl = $env:RL_TEST_PERL
$savedTestScript = $env:RL_TEST_SCRIPT
$savedTestPerlsh = $env:RL_TEST_PERLSH
$validationFile = $null
try {
$env:LC_ALL = 'C'
$configText = & $Perl '-MConfig' '-MJSON::PP' '-e' 'print encode_json({map {$_=>$Config{$_}} qw(version archname cc ccflags make libperl archlibexp useshrplib ptrsize)})'
if ($LASTEXITCODE) { throw 'Cannot query Perl configuration.' }
$config = $configText | ConvertFrom-Json
if ($config.cc -notmatch '(^|[\\/])cl(?:\.exe)?$' -or $config.archname -notmatch '^MSWin32-') { throw 'The selected Perl must be built with MSVC.' }
if ($config.ccflags -notmatch '[-/]MD\b' -or $config.useshrplib -ne 'true') { throw 'This build requires a shared Perl using the release DLL CRT (/MD).' }
if ($config.archname -match 'arm') { throw 'ARM Perl is not supported by this build script yet.' }
$arch = if ([int]$config.ptrsize -eq 8) { 'amd64' } else { 'x86' }
$vswhereCandidates = @(
    "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe",
    'C:/Program Files/Microsoft Visual Studio/Installer/vswhere.exe'
)
$vswhere = $vswhereCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$vs = if ($vswhere) { & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath } else { $null }
if (!$vs) {
    $vs = 'C:/Program Files/Microsoft Visual Studio/18/Community'
    if (!(Test-Path "$vs/Common7/Tools/VsDevCmd.bat")) { throw 'Install Visual Studio C++ tools and a Windows SDK.' }
}
$devcmd = Join-Path $vs 'Common7/Tools/VsDevCmd.bat'
$envLines = & $env:ComSpec /d /c "`"$devcmd`" -no_logo -arch=$arch -host_arch=amd64 >nul && set"
if ($LASTEXITCODE) { throw 'Cannot initialize the MSVC environment.' }
foreach ($line in $envLines) {
    if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
}
$env:PATH = "$(Split-Path -Parent $Perl);$env:PATH"
$BuildDir = [IO.Path]::GetFullPath($BuildDir)
$InstallPrefix = [IO.Path]::GetFullPath($InstallPrefix)
$native = Join-Path $BuildDir 'native'
$include = Join-Path $InstallPrefix 'include/readline'
$lib = Join-Path $InstallPrefix 'lib'
New-Item -ItemType Directory -Force $native, $include, $lib | Out-Null
$script:BuildLog = Join-Path $BuildDir 'build.log'
Set-Content $script:BuildLog "Native MSVC build for Perl $($config.version) ($($config.archname))"
$config | ConvertTo-Json | Set-Content (Join-Path $BuildDir 'perl-config.json')
$validationFile = Join-Path $BuildDir 'validation.json'
@{ status = 'running'; perl = $Perl; architecture = $config.archname; visualStudio = $vs;
   tools = $env:VCToolsVersion; sdk = $env:WindowsSDKVersion } | ConvertTo-Json | Set-Content $validationFile
$source = Join-Path $PSScriptRoot 'readline-8.3'
$port = Join-Path $PSScriptRoot 'win32'
$names = 'readline vi_mode funmap keymaps parens search rltty complete bind isearch display signals util kill undo macro input callback terminal text nls misc history histexpand histfile histsearch shell mbutil tilde colors parse-colors xmalloc xfree compat gettimeofday' -split ' '
$objects = @()
foreach ($name in $names) {
    $obj = Join-Path $native "$name.obj"
    Invoke-Checked cl @('/nologo', '/c', '/std:c11', '/MD', '/O2', '/W3', '/DHAVE_CONFIG_H', "/I$port", "/I$source", "/Fo$obj", (Join-Path $source "$name.c"))
    $objects += $obj
}
foreach ($name in @('compat', 'termcap', 'console')) {
    $obj = Join-Path $native "win_$name.obj"
    Invoke-Checked cl @('/nologo', '/c', '/std:c11', '/MD', '/O2', '/W3', '/DHAVE_CONFIG_H', "/I$port", "/I$source", "/Fo$obj", (Join-Path $port "$name.c"))
    $objects += $obj
}
Invoke-Checked lib (@('/nologo', "/OUT:$lib/readline.lib") + $objects)
$historyObjects = @('history', 'histexpand', 'histfile', 'histsearch', 'shell', 'mbutil', 'xmalloc', 'xfree', 'win_compat') | ForEach-Object { Join-Path $native "$_.obj" }
Invoke-Checked lib (@('/nologo', "/OUT:$lib/history.lib") + $historyObjects)
foreach ($header in @('readline.h','chardefs.h','keymaps.h','history.h','tilde.h','rlstdc.h','rlconf.h','rltypedefs.h')) { Copy-Item (Join-Path $source $header) $include }
$testExe = Join-Path $native 'native-tests.exe'
Invoke-Checked cl @('/nologo', '/std:c11', '/MD', '/O2', '/W3', "/I$port", "/I$source", "/Fo$native/native-tests.obj", "/Fe$testExe", "$PSScriptRoot/tests/native.c", "$lib/readline.lib", 'user32.lib')
Push-Location $native
try { Invoke-Checked $testExe @() } finally { Pop-Location }
if (!$LibrariesOnly) {
    $module = Join-Path $BuildDir 'Term-ReadLine-Gnu'
    New-Item -ItemType Directory -Force $module | Out-Null
    Copy-Item "$PSScriptRoot/Term-ReadLine-Gnu-1.47/*" $module -Recurse -Force
    Push-Location $module
    try {
        Invoke-Checked $Perl @('Makefile.PL', "--prefix=$InstallPrefix", "INSTALL_BASE=$InstallPrefix/perl")
        Invoke-Checked nmake @('/nologo')
        Invoke-Checked nmake @('/nologo', 'test')
        Invoke-Checked nmake @('/nologo', 'install')
        $env:PERL5LIB = "$InstallPrefix/perl/lib/perl5/$($config.archname);$InstallPrefix/perl/lib/perl5"
        $env:RL_TEST_PERL = $Perl
        $env:RL_TEST_SCRIPT = "$PSScriptRoot/tests/perl-console.pl"
        $env:RL_TEST_PERLSH = "$InstallPrefix/perl/bin/perlsh.bat"
        Push-Location $native
        try {
            Invoke-Checked $testExe @('--perl')
            Invoke-Checked $testExe @('--debugger')
            Invoke-Checked $testExe @('--perlsh')
        } finally { Pop-Location }
        $dll = Join-Path $module 'blib/arch/auto/Term/ReadLine/Gnu/Gnu.dll'
        $dependencies = & dumpbin /nologo /dependents $dll
        if ($LASTEXITCODE) { throw 'Cannot inspect extension dependencies.' }
        $dependencies | Set-Content (Join-Path $BuildDir 'dependencies.txt')
        if ($dependencies -match 'cygwin|msys-2|libgcc|libstdc\+\+|libwinpthread') { throw 'An unexpected non-native runtime dependency was found.' }
        if ($Install) {
            Invoke-Checked $Perl @('Makefile.PL', "--prefix=$InstallPrefix")
            Invoke-Checked nmake @('/nologo', 'install')
        }
    } finally { Pop-Location }
}
Write-Host "Staged MSVC libraries and headers in $InstallPrefix"
@{ status = 'passed'; native = 'passed'; perl = $(if ($LibrariesOnly) { 'not run' } else { 'passed' });
   architecture = $config.archname; version = $config.version; prefix = $InstallPrefix;
   visualStudio = $vs; tools = $env:VCToolsVersion; sdk = $env:WindowsSDKVersion } |
    ConvertTo-Json | Set-Content $validationFile
} catch {
    if ($validationFile) {
        @{ status = 'failed'; error = $_.Exception.Message } | ConvertTo-Json | Set-Content $validationFile
    }
    throw
} finally {
    $env:LC_ALL = $savedLocale
    $env:PATH = $savedPath
    $env:PERL5LIB = $savedPerl5Lib
    $env:RL_TEST_PERL = $savedTestPerl
    $env:RL_TEST_SCRIPT = $savedTestScript
    $env:RL_TEST_PERLSH = $savedTestPerlsh
}
