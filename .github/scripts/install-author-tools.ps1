# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'

function Invoke-AuthorNative {
    param([string]$Program, [string[]]$Arguments, [string]$Log)
    $PSNativeCommandUseErrorActionPreference = $false
    & $Program @Arguments 2>&1 | Tee-Object -FilePath $Log -Append | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE) { throw "Author command failed ($LASTEXITCODE): $Program $($Arguments -join ' ')" }
}

function Receive-AuthorBootstrap {
    param([string]$Archive)
    Invoke-WebRequest 'https://cpan.metacpan.org/authors/id/M/MI/MIYAGAWA/App-cpanminus-1.7049.tar.gz' -OutFile $Archive
}

function Initialize-AuthorBootstrap {
    param([string]$Root, [string]$Log)
    $bootstrap = Join-Path $Root 'build/author-bootstrap'
    New-Item -ItemType Directory -Force $bootstrap | Out-Null
    $archive = Join-Path $bootstrap 'App-cpanminus-1.7049.tar.gz'
    Receive-AuthorBootstrap -Archive $archive
    $expected = 'b9ffb88e62a06aa91bd7d5a28ef6bdbb942608aea90e3969aa29b33640035214'
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
        throw 'Author-tool bootstrap checksum mismatch'
    }
    Invoke-AuthorNative -Program "$env:SystemRoot/System32/tar.exe" -Arguments @('-xzf', $archive, '-C', $bootstrap) -Log $Log
    return @{
        cpanm = Join-Path $bootstrap 'App-cpanminus-1.7049/bin/cpanm'
        library = Join-Path $bootstrap 'App-cpanminus-1.7049/lib'
    }
}

function Install-AuthorDependencies {
    param([string]$Root, [string]$Prefix, $Tools, [string]$Log)
    $modules = @()
    foreach ($group in @($Tools.required, $Tools.coverage)) {
        foreach ($entry in $group.PSObject.Properties) {
            $distribution = $Tools.distributions.PSObject.Properties[$entry.Name]
            if (-not $distribution) { throw "Missing pinned distribution for $($entry.Name)" }
            $modules += $distribution.Value
        }
    }
    if (!$modules.Count) { throw 'Empty author-tool inventory' }
    $bootstrap = Initialize-AuthorBootstrap -Root $Root -Log $Log
    # Keep normal dependency tests enabled. PERL_CPANM_OPT is isolated too.
    $arguments = @("-I$($bootstrap.library)", $bootstrap.cpanm, '--local-lib-contained', $Prefix,
        '--mirror', 'https://cpan.metacpan.org', '--mirror-only') + $modules
    Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log $Log
}

function New-AuthorVerificationScripts {
    param([string]$Directory)
    $helper = Join-Path $Directory 'verify.pl'
    # Generated programs are isolated subprocess probes, not runtime modules.
    @'
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
use Config ();
BEGIN { @INC = @Config::Config{qw(privlibexp archlibexp)}; }
use Cwd qw(abs_path);
use JSON::PP qw(decode_json);
use version ();
my ($mode, $prefix, $manifest, $profile, $output, $database, $probe) = @ARGV;
sub write_json ($path, $value) {
    open my $file, '>:raw', $path or die "Cannot write $path: $!";
    print {$file} JSON::PP->new->canonical->pretty->encode($value) or die $!;
    close $file or die $!;
}
if ($mode eq 'scratch') {
    require Win32;
    write_json($output, Win32::GetShortPathName($prefix) || $prefix);
    exit;
}
if ($mode eq 'identity') {
    die "Require native MSVC Perl 5.44+\n"
        unless $Config::Config{cc} eq 'cl' && $Config::Config{archname} =~ /\AMSWin32-(?:x64|arm64)-/;
    my %identity = map { $_ => $Config::Config{$_} // '' }
        qw(version archname cc ccversion ccflags cccdlflags ldflags optimize
           useithreads usemultiplicity useimpsys useshrplib use64bitint
           use64bitall uselongdouble usequadmath ptrsize ivsize nvsize byteorder);
    write_json($output, \%identity);
    exit;
}
unshift @INC, "$prefix/lib/perl5/$Config::Config{archname}", "$prefix/lib/perl5";
if ($mode eq 'verify') {
    open my $file, '<:raw', $manifest or die $!;
    my $tools = decode_json(do { local $/; <$file> });
    close $file or die $!;
    my %actual;
    my $owned = lc abs_path($prefix);
    $owned =~ tr{\\}{/};
    for my $group (qw(required coverage)) {
        for my $module (sort keys $tools->{$group}->%*) {
            die "Invalid tool name $module\n" unless $module =~ /\A\w+(?:::\w+)*\z/;
            (my $name = "$module.pm") =~ s{::}{/}g;
            require $name;
            my $found = $module->VERSION;
            my $wanted = $tools->{$group}{$module};
            die "$module $wanted required, found $found\n"
                unless version->parse($found) == version->parse($wanted);
            my $source = abs_path($INC{$name}) // die "Cannot resolve $module\n";
            $source =~ tr{\\}{/};
            die "$module loaded outside author library: $source\n"
                unless index(lc($source), "$owned/") == 0;
            $actual{$module} = { version => "$found", source => $source };
        }
    }
    die "Empty author-tool inventory\n" unless keys %actual;
    my $critic = Perl::Critic->new(-profile => $profile, '-profile-strictness' => 'fatal');
    my $text = "use strict;\nuse warnings;\n1;\n";
    die "PPI cannot parse probe\n" unless PPI::Document->new(\$text);
    my $formatted = '';
    die "Perl::Tidy probe failed\n" if Perl::Tidy::perltidy(
        source => \$text, destination => \$formatted, argv => ['-npro']);
    die "Empty Perl::Tidy result\n" unless length $formatted;
    write_json($output, \%actual);
} elsif ($mode eq 'probe') {
    require Devel::Cover;
    Devel::Cover->import('-db', $database, '-blib', 0, '-coverage',
        'statement', 'branch', 'condition', '-silent', 1,
        '-ignore', '.', '-select', 'probe[.]pl\z');
    my $value = do $probe;
    die $@ if $@;
    die "Cannot run $probe: $!" unless defined $value;
} elsif ($mode eq 'calibration') {
    require Devel::Cover::DB;
    my $db = Devel::Cover::DB->new(db => $database);
    $db->merge_runs;
    $db->calculate_summary(statement => 1, branch => 1);
    my $summary = $db->summary('Total');
    for my $criterion (qw(statement branch)) {
        my $value = $summary->{$criterion};
        die "Unsupported $criterion instrumentation\n" unless $value
            && $value->{total} && $value->{covered} == $value->{total}
            && !($value->{error} // 0) && !($value->{uncoverable} // 0);
    }
    write_json($output, $summary);
} else { die "Unknown verification mode $mode\n"; }
'@ | Set-Content -LiteralPath $helper -Encoding utf8NoBOM
    $probe = Join-Path $Directory 'probe.pl'
    @'
# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
use v5.44;
use strict;
use warnings;
sub choose ($value) { if ($value) { return 1; } else { return 0; } }
choose(1);
choose(0);
'@ | Set-Content -LiteralPath $probe -Encoding utf8NoBOM
    return @{ helper = $helper; probe = $probe }
}

function Get-AuthorIdentity {
    param($Scripts, [string]$Directory, [string]$Log)
    $output = Join-Path $Directory 'identity.json'
    Invoke-AuthorNative -Program 'perl' -Arguments @($Scripts.helper, 'identity', '', '', '', $output) -Log $Log
    return Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
}

function Get-AuthorScratchPath {
    param($Scripts, [string]$Directory, [string]$Log)
    $output = Join-Path $Directory 'scratch.json'
    Invoke-AuthorNative -Program 'perl' -Arguments @($Scripts.helper, 'scratch', $Directory, '', '', $output) -Log $Log
    return Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
}

function Test-AuthorLibrary {
    param([string]$Root, [string]$Prefix, $Scripts, [string]$Directory, [string]$Log)
    $versions = Join-Path $Directory 'versions.json'
    $calibration = Join-Path $Directory 'calibration.json'
    $database = Join-Path $Directory 'coverage-db'
    $arguments = @($Scripts.helper, 'verify', $Prefix, (Join-Path $Root 'config/author-tools.json'),
        (Join-Path $Root '.perlcriticrc'), $versions, $database, $Scripts.probe)
    Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log $Log
    $arguments[1] = 'probe'
    Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log $Log
    $arguments[1] = 'calibration'
    $arguments[5] = $calibration
    Invoke-AuthorNative -Program 'perl' -Arguments $arguments -Log $Log
    return @{
        tools = Get-Content -LiteralPath $versions -Raw | ConvertFrom-Json
        calibration = Get-Content -LiteralPath $calibration -Raw | ConvertFrom-Json
    }
}

function Invoke-AuthorTools {
    param([string]$Root, [switch]$VerifyOnly)
    $Root = (Resolve-Path -LiteralPath $Root).Path
    $prefix = Join-Path $Root 'build/author'
    $reports = Join-Path $Root 'build/quality'
    New-Item -ItemType Directory -Force $reports | Out-Null
    $log = Join-Path $reports 'author-install.log'
    $report = Join-Path $reports 'author-tools.json'
    $marker = Join-Path $prefix '.author-tools-complete.json'
    $started = Get-Date
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $result = [ordered]@{ status = 'failed'; verify_only = [bool]$VerifyOnly; cache_key = $env:AUTHOR_TOOLS_CACHE_KEY }
    $saved = @{}
    $isolated = @('RELEASE_TESTING', 'AUTHOR_TESTING', 'EXTENDED_TESTING', 'NO_COLOR', 'ANSI_COLORS_DISABLED',
        'PERL5LIB', 'PERL5OPT', 'PERL_LOCAL_LIB_ROOT', 'PERL_MB_OPT', 'PERL_MM_OPT', 'PERL_CPANM_OPT',
        'HARNESS_PERL_SWITCHES', 'DEVEL_COVER_OPTIONS', 'PERL_CPANM_HOME', 'TEMP', 'TMP', 'TMPDIR')
    $installStarted = $false
    try {
        foreach ($name in $isolated) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        # Retain controlled scratch space for diagnosis. CI owns RUNNER_TEMP;
        # local scratch space stays in the ignored build directory.
        $scratchBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { Join-Path $Root 'build' }
        $scratch = Join-Path $scratchBase ('author-' + [IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory $scratch | Out-Null
        $env:PERL_CPANM_HOME = Join-Path $Root 'build/author-cpanm'
        $scripts = New-AuthorVerificationScripts -Directory $scratch
        # Some CPAN tests concatenate source and temporary absolute paths into
        # DESTDIR. Use the Windows short spelling when available; never skip tests.
        $shortScratch = Get-AuthorScratchPath -Scripts $scripts -Directory $scratch -Log $log
        foreach ($name in @('TEMP', 'TMP', 'TMPDIR')) {
            [Environment]::SetEnvironmentVariable($name, $shortScratch, 'Process')
        }
        $result.scratch = $shortScratch
        $identity = Get-AuthorIdentity -Scripts $scripts -Directory $scratch -Log $log
        $manifest = Join-Path $Root 'config/author-tools.json'
        $configuration = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
        $installer = (Get-FileHash -LiteralPath (Join-Path $Root '.github/scripts/install-author-tools.ps1') -Algorithm SHA256).Hash
        $result.perl = $identity
        $result.configuration = $configuration
        $result.installer = $installer
        if ($VerifyOnly) {
            if (!(Test-Path -LiteralPath $marker -PathType Leaf)) { throw 'Missing author-tool completion marker' }
            $completed = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
            if ($completed.schema -ne 1 -or $completed.configuration -ne $configuration -or $completed.installer -ne $installer -or
                ($completed.perl | ConvertTo-Json -Compress) -cne ($identity | ConvertTo-Json -Compress)) {
                throw 'Author-tool completion marker does not match this installer, inventory and native Perl'
            }
        } else {
            # A failed reinstall must not retain an earlier success marker.
            if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
            $tools = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
            $installStarted = $true
            Install-AuthorDependencies -Root $Root -Prefix $prefix -Tools $tools -Log $log
        }
        $verified = Test-AuthorLibrary -Root $Root -Prefix $prefix -Scripts $scripts -Directory $scratch -Log $log
        $result.tools = $verified.tools
        $result.calibration = $verified.calibration
        if (!$VerifyOnly) {
            @{ schema = 1; configuration = $configuration; installer = $installer; perl = $identity } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $marker -Encoding utf8NoBOM
        }
        $result.status = 'passed'
        Write-Host "Author tools verified; verify-only=$VerifyOnly."
    } catch {
        $result.error = $_.Exception.Message
        if ($installStarted -and (Test-Path -LiteralPath $env:PERL_CPANM_HOME)) {
            $details = Get-ChildItem -LiteralPath $env:PERL_CPANM_HOME -Recurse -File -Filter build.log |
                Where-Object LastWriteTime -GE $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($details) {
                Write-Host "Detailed cpanm diagnostics: $($details.FullName)"
                Get-Content -LiteralPath $details.FullName | Tee-Object -FilePath $log -Append | ForEach-Object { Write-Host $_ }
            }
        }
        if ($VerifyOnly) {
            throw "Invalid author-tool cache '$($env:AUTHOR_TOOLS_CACHE_KEY)': $($result.error). Remove that cache entry and rerun; for a local library, rerun without -VerifyOnly."
        }
        throw
    } finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
        $timer.Stop()
        $result.elapsed_seconds = [math]::Round($timer.Elapsed.TotalSeconds, 3)
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $report -Encoding utf8NoBOM
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-AuthorTools -Root (Join-Path $PSScriptRoot '../..') -VerifyOnly:$VerifyOnly
}
