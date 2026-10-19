#requires -Version 5.1
<#
.SYNOPSIS
    Thousand Nights Protocol -- isolated Python 3.12 environment with configurable report output.
.DESCRIPTION
    Plan is the default (never creates a Python runtime). Install creates/updates the
    selected virtual environment. Verify inspects an existing virtual environment.
    OutputMode Default/Auto writes to a unique run folder; Custom writes directly
    into OutputRoot and rejects overwrites. ReportFormat controls summary formats.
    The canonical dependency manifest is supplied separately; no global pip changes.
.EXAMPLE
    .\windows\ThousandNights.ps1 -Mode Plan -OutputMode Custom -OutputRoot 'D:\My Reports'
.EXAMPLE
    .\windows\ThousandNights.ps1 -Mode Install -ManifestPath '.\requirements\CODEX_FINAL_1001_DEPENDENCIES.txt' -OutputRoot 'E:\TN\Reports' -InstallChromium
    # Opens Windows folder picker for installation location.
.EXAMPLE
    .\windows\ThousandNights.ps1 -Mode Verify -InstallRoot 'D:\TN\Runtime' -ReportFormat Json
#>
[CmdletBinding()]
param(
    [ValidateSet('Plan','Install','Verify')][string]$Mode = 'Plan',
    [string]$InstallRoot = (Join-Path $env:USERPROFILE 'Documents\Magi 3\Runtime\Dependencies\Python\Thousand Nights Protocol'),
    [ValidateSet('Auto','Always','Never')][string]$InstallFolderPicker = 'Auto',
    [ValidateSet('Default','Auto','Custom')][string]$OutputMode = 'Auto',
    [Alias('OutputPath','Output')][string]$OutputRoot,
    [ValidateSet('All','Json','Markdown','Csv')][Alias('OutputFormat')][string]$ReportFormat = 'All',
    [string]$ManifestPath,
    [string]$ConfigPath,
    [switch]$InstallChromium,
    [switch]$ContinueOnPackageError,
    [string]$PythonLauncher = 'py',
    [switch]$SkipAudit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Steps = New-Object 'System.Collections.Generic.List[object]'
$script:Problems = New-Object 'System.Collections.Generic.List[string]'
$script:State = 'SUCCESS'
$script:Failure = $null
$script:Started = (Get-Date).ToUniversalTime()
$script:RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6))
$script:ManifestCount = 0
$script:ManifestSha = $null
$script:ManifestSource = $null
$script:InstallRootSelection = 'Default'
$script:RunDir = $null
$script:LogDir = $null
$script:OutputBase = $null
$script:PythonExe = $null
$script:ExitCode = 0
$script:AuditTool = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\audit_runtime.py'

function Record-Step([string]$Step, [string]$Status, [string]$Detail) {
    $script:Steps.Add([pscustomobject]@{
        time_utc = (Get-Date).ToUniversalTime().ToString('o')
        step = $Step
        status = $Status
        detail = $Detail
    })
    Write-Host ('[{0}] {1}: {2}' -f $Status, $Step, $Detail)
}
function Record-Warning([string]$Detail) {
    $script:Problems.Add($Detail)
    Record-Step 'warning' 'WARN' $Detail
}
function Resolve-PathText([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'A path argument cannot be empty.' }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Value)
}
# Windows native folder dialog. Installs into the selected directory itself, not
# into an automatically-added child path. An existing ancestor is used to seed
# the dialog when the preferred runtime directory has not been created yet.
function Select-InstallDirectory([string]$SuggestedPath) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'The installation folder picker is supported only on Windows. Pass -InstallRoot on other platforms.'
    }
    if (-not [Environment]::UserInteractive -or $env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true') {
        throw 'The folder picker needs an interactive Windows desktop session. Supply -InstallRoot and -InstallFolderPicker Never for unattended runs.'
    }
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw 'The Windows folder picker requires an STA PowerShell session. Launch with powershell.exe -STA or supply -InstallRoot.'
    }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = 'Thousand Nights Protocol - choose the installation folder (runtime/Venv)' 
        $dialog.ShowNewFolderButton = $true
        $candidate = Resolve-PathText $SuggestedPath
        while (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            $parent = Split-Path -Parent $candidate
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) { break }
            $candidate = $parent
        }
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $dialog.SelectedPath = $candidate
        }
        $selection = $dialog.ShowDialog()
        if ($selection -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
            throw 'Installation folder selection cancelled. No runtime changes were made.'
        }
        return (Resolve-PathText $dialog.SelectedPath)
    } finally {
        $dialog.Dispose()
    }
}

function Call-Process([string]$Step, [string]$Command, [string[]]$ArgumentList, [string]$LogName) {
    $logFile = Join-Path $script:LogDir $LogName
    Record-Step $Step 'RUN' ($Command + ' ' + ($ArgumentList -join ' '))
    $previous = $ErrorActionPreference
    try {
        # PowerShell 5.1 may treat redirected native stderr as nonterminating errors.
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        & $Command @ArgumentList 2>&1 | Tee-Object -FilePath $logFile | Out-Host
        $code = [int]$LASTEXITCODE
    } catch {
        $code = 1
        $_.Exception.ToString() | Add-Content -LiteralPath $logFile -Encoding UTF8
    } finally {
        $ErrorActionPreference = $previous
    }
    Record-Step $Step $(if($code -eq 0){'OK'}else{'ERROR'}) ('exit_code=' + $code)
    return $code
}
function Read-SafeManifest([string]$PathText, [string]$Destination) {
    $entries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in (Get-Content -LiteralPath $PathText -Encoding UTF8)) {
        $s = $line.Trim()
        if (-not $s -or $s.StartsWith('#')) { continue }
        # Explicitly disallow pip directives, recursive includes, URLs and local paths.
        # Canonical 1001 manifest contains simple distribution names.
        if ($s.StartsWith('-') -or $s.Contains('://') -or $s.Contains(' @ ') -or $s.Contains('\\') -or $s.Contains('/') -or $s -notmatch '^[A-Za-z0-9][A-Za-z0-9_.+!\[\],;=<>~\-\s\x22\x27]*$') {
            throw ('Unsupported manifest entry (only named packages/version constraints are permitted): ' + $s)
        }
        $entries.Add($s)
    }
    if ($entries.Count -eq 0) { throw 'The manifest contains no dependencies.' }
    $entries.ToArray() | Set-Content -LiteralPath $Destination -Encoding UTF8
    return $entries.ToArray()
}
function Write-Summaries {
    $report = [ordered]@{
        protocol = 'Thousand Nights Protocol'
        version = '0.2.1-ps1-install-folder-picker'
        mode = $Mode
        output_mode = $OutputMode
        report_format = $ReportFormat
        run_id = $script:RunId
        started_utc = $script:Started.ToString('o')
        finished_utc = (Get-Date).ToUniversalTime().ToString('o')
        install_root = $InstallRoot
        output_root = $script:OutputBase
        run_directory = $script:RunDir
        python_executable = $script:PythonExe
        manifest_path = $script:ManifestSource
        manifest_sha256 = $script:ManifestSha
        install_root_selection = $script:InstallRootSelection
        install_folder_picker = $InstallFolderPicker
        manifest_count = $script:ManifestCount
        browser_install_requested = [bool]$InstallChromium
        status = $script:State
        error = $script:Failure
        warnings = @($script:Problems.ToArray())
        steps = @($script:Steps.ToArray())
    }
    if ($ReportFormat -in @('All','Json')) {
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:RunDir 'run.json') -Encoding UTF8
    }
    if ($ReportFormat -in @('All','Markdown')) {
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add('# Thousand Nights Protocol — Execution Report')
        $lines.Add('')
        foreach ($name in @('version','mode','output_mode','status','run_id','install_root','output_root','run_directory','manifest_count','manifest_sha256','started_utc','finished_utc')) {
            $lines.Add(('- **{0}:** {1}' -f $name, $report[$name]))
        }
        $lines.Add('')
        $lines.Add('## Warnings')
        if ($script:Problems.Count -eq 0) { $lines.Add('- None') }
        foreach ($problem in $script:Problems) { $lines.Add('- ' + $problem) }
        $lines.Add('')
        $lines.Add('## Operations')
        foreach ($item in $script:Steps) {
            $lines.Add(('- {0} | {1} | {2} | {3}' -f $item.time_utc, $item.status, $item.step, $item.detail))
        }
        $lines.ToArray() | Set-Content -LiteralPath (Join-Path $script:RunDir 'run.md') -Encoding UTF8
    }
    if ($ReportFormat -in @('All','Csv')) {
        if ($script:Steps.Count -gt 0) {
            $script:Steps.ToArray() | Export-Csv -LiteralPath (Join-Path $script:RunDir 'steps.csv') -NoTypeInformation -Encoding UTF8
        } else {
            'time_utc,step,status,detail' | Set-Content -LiteralPath (Join-Path $script:RunDir 'steps.csv') -Encoding UTF8
        }
    }
}

try {
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $configFile = Resolve-PathText $ConfigPath
        if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) { throw ('Config not found: ' + $configFile) }
        $config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.PSObject.Properties['output_mode'] -and -not $PSBoundParameters.ContainsKey('OutputMode')) { $OutputMode = [string]$config.output_mode }
        if ($null -ne $config.PSObject.Properties['output_root'] -and -not $PSBoundParameters.ContainsKey('OutputRoot')) { $OutputRoot = [string]$config.output_root }
        if ($null -ne $config.PSObject.Properties['report_format'] -and -not $PSBoundParameters.ContainsKey('ReportFormat')) { $ReportFormat = [string]$config.report_format }
        if ($null -ne $config.PSObject.Properties['install_root'] -and -not $PSBoundParameters.ContainsKey('InstallRoot')) { $InstallRoot = [string]$config.install_root }
        if ($OutputMode -notin @('Default','Auto','Custom')) { throw 'Invalid config output_mode.' }
        if ($ReportFormat -notin @('All','Json','Markdown','Csv')) { throw 'Invalid config report_format.' }
        Record-Step 'config' 'OK' ('Loaded ' + $configFile)
    }
    # CLI or config paths are explicit choices. Auto picker only appears when
    # launching Install/Verify without either one; Always requests it regardless.
    $explicitInstallRoot = $PSBoundParameters.ContainsKey('InstallRoot')
    $configuredInstallRoot = (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and
        $null -ne $config.PSObject.Properties['install_root'] -and
        -not $explicitInstallRoot -and
        -not [string]::IsNullOrWhiteSpace([string]$config.install_root))
    $shouldPickInstallRoot = ($InstallFolderPicker -eq 'Always' -or
        ($InstallFolderPicker -eq 'Auto' -and $Mode -in @('Install','Verify') -and
            -not $explicitInstallRoot -and -not $configuredInstallRoot))
    if ($shouldPickInstallRoot) {
        $InstallRoot = Select-InstallDirectory $InstallRoot
        $script:InstallRootSelection = 'FolderPicker'
        Record-Step 'install_location' 'OK' ('Selected folder: ' + $InstallRoot)
    } elseif ($explicitInstallRoot) {
        $script:InstallRootSelection = 'CommandLine'
    } elseif ($configuredInstallRoot) {
        $script:InstallRootSelection = 'ConfigFile'
    } else {
        $script:InstallRootSelection = 'Default'
    }
    $InstallRoot = Resolve-PathText $InstallRoot
    $script:PythonExe = Join-Path $InstallRoot 'Venv\Scripts\python.exe'
    if ($OutputMode -eq 'Default') {
        if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { throw 'Default output mode does not accept OutputRoot. Choose Auto or Custom.' }
        $script:OutputBase = Join-Path $InstallRoot 'Reports'
    } elseif ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        if ($OutputMode -eq 'Custom') { throw 'Custom output mode requires -OutputRoot.' }
        $script:OutputBase = Join-Path $InstallRoot 'Reports'
    } else {
        $script:OutputBase = Resolve-PathText $OutputRoot
    }
    if ($OutputMode -eq 'Custom') {
        $script:RunDir = $script:OutputBase
        # Refuse silent overwrite of existing outputs.
        foreach ($file in @('run.json','run.md','steps.csv','audit_before.json','audit_after.json','manifest_validated.txt','failed_packages.txt')) {
            if (Test-Path -LiteralPath (Join-Path $script:RunDir $file)) {
                throw ('Custom output directory already contains ' + $file + '. Select a new output directory.')
            }
        }
    } else {
        $script:RunDir = Join-Path $script:OutputBase ('Run-' + $script:RunId)
    }
    $script:LogDir = Join-Path $script:RunDir 'Logs'
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    Record-Step 'output' 'OK' ('Mode=' + $OutputMode + '; path=' + $script:RunDir)

    $manifest = $null
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        $manifest = Resolve-PathText $ManifestPath
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw ('Manifest not found: ' + $manifest) }
    } else {
        # Allow standalone usage and nested use in codex-magi-venv: the 1001 master
        # manifest lives at the repository's /requirements/ folder. Do not copy it.
        $packageRoot = Split-Path -Parent $PSScriptRoot
        $repositoryRoot = Split-Path -Parent $packageRoot
        foreach ($candidate in @(
            (Join-Path $packageRoot 'requirements\CODEX_FINAL_1001_DEPENDENCIES.txt'),
            (Join-Path $repositoryRoot 'requirements\CODEX_FINAL_1001_DEPENDENCIES.txt')
        )) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $manifest = $candidate
                break
            }
        }
    }
    if ($null -ne $manifest) {
        $script:ManifestSource = $manifest
        $clean = Join-Path $script:RunDir 'manifest_validated.txt'
        $packages = @(Read-SafeManifest $manifest $clean)
        $script:ManifestCount = $packages.Count
        $script:ManifestSha = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
        Record-Step 'manifest' 'OK' ('entries=' + $script:ManifestCount + '; sha256=' + $script:ManifestSha)
        if ($packages.Count -ne 1001) { Record-Warning ('Manifest has ' + $packages.Count + ' entries (canonical edition expects 1001; custom manifests are allowed).') }
    } elseif ($Mode -eq 'Install') {
        throw 'Install requires -ManifestPath or requirements/CODEX_FINAL_1001_DEPENDENCIES.txt. No packages were installed.'
    } else {
        Record-Step 'manifest' 'INFO' 'Not supplied; package overlap audit is unavailable.'
    }

    if ($Mode -eq 'Plan') {
        Record-Step 'plan' 'OK' 'Report-only execution: no runtime, Python packages or browsers were installed.'
        Record-Step 'runtime' 'INFO' ('Python 3.12 target: ' + $script:PythonExe)
        if ($InstallChromium) { Record-Step 'browser' 'INFO' 'Chromium requested; no installation occurs in Plan.' }
    } else {
        if ($Mode -eq 'Install' -and -not (Test-Path -LiteralPath $script:PythonExe -PathType Leaf)) {
            New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
            $venv = Join-Path $InstallRoot 'Venv'
            $rc = Call-Process 'create_venv' $PythonLauncher @('-3.12','-m','venv',$venv) 'create_venv.log'
            if ($rc -ne 0) { throw 'Could not create Python 3.12 virtual environment; check create_venv.log.' }
        }
        if (-not (Test-Path -LiteralPath $script:PythonExe -PathType Leaf)) { throw ('Python not found at: ' + $script:PythonExe) }
        $rc = Call-Process 'python_version' $script:PythonExe @('--version') 'python_version.log'
        if ($rc -ne 0) { throw 'Python could not be launched.' }
        $rc = Call-Process 'python_312' $script:PythonExe @('-c','import sys; assert sys.version_info[:2] == (3, 12), sys.version') 'python_312.log'
        if ($rc -ne 0) { throw 'Runtime is not Python 3.12; refusing to install into it.' }

        if ($Mode -eq 'Install') {
            if (-not $SkipAudit) {
                $argsBefore = @($script:AuditTool,'--phase','before','--out-dir',$script:RunDir,'--manifest',(Join-Path $script:RunDir 'manifest_validated.txt'))
                $null = Call-Process 'audit_before' $script:PythonExe $argsBefore 'audit_before.log'
            }
            $rc = Call-Process 'upgrade_pip' $script:PythonExe @('-m','pip','install','--upgrade','pip','--disable-pip-version-check','--no-input') 'upgrade_pip.log'
            if ($rc -ne 0) { Record-Warning 'pip upgrade failed; continuing with installed pip version.' }
            $cleanManifest = Join-Path $script:RunDir 'manifest_validated.txt'
            if ($ContinueOnPackageError) {
                $failed = New-Object 'System.Collections.Generic.List[string]'
                for ($i=0; $i -lt $packages.Count; $i++) {
                    $name = $packages[$i]
                    $percentage = [math]::Round(100.0 * ($i+1) / $packages.Count)
                    Write-Progress -Activity 'Thousand Nights install' -Status ('{0}/{1}: {2}' -f ($i+1),$packages.Count,$name) -PercentComplete $percentage
                    $rc = Call-Process ('install_' + ($i+1)) $script:PythonExe @('-m','pip','install','--disable-pip-version-check','--no-input','--',$name) ('package-{0:D4}.log' -f ($i+1))
                    if ($rc -ne 0) { $failed.Add($name) }
                }
                Write-Progress -Activity 'Thousand Nights install' -Completed
                if ($failed.Count -gt 0) {
                    $failed.ToArray() | Set-Content -LiteralPath (Join-Path $script:RunDir 'failed_packages.txt') -Encoding UTF8
                    Record-Warning ('Individual installs failed: ' + $failed.Count + '. See failed_packages.txt')
                }
            } else {
                $rc = Call-Process 'install_requirements' $script:PythonExe @('-m','pip','install','--disable-pip-version-check','--no-input','-r',$cleanManifest) 'install_requirements.log'
                if ($rc -ne 0) { throw 'The dependency resolution/install failed. No rollback was attempted; see install_requirements.log.' }
            }
            if ($InstallChromium) {
                $savedBrowser = [Environment]::GetEnvironmentVariable('PLAYWRIGHT_BROWSERS_PATH', 'Process')
                try {
                    $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $InstallRoot 'Browsers'
                    $rc = Call-Process 'install_chromium' $script:PythonExe @('-m','playwright','install','chromium') 'install_chromium.log'
                    if ($rc -ne 0) { Record-Warning 'Chromium installation failed.' }
                } finally {
                    [Environment]::SetEnvironmentVariable('PLAYWRIGHT_BROWSERS_PATH',$savedBrowser,'Process')
                }
            }
        }
        $rc = Call-Process 'pip_check' $script:PythonExe @('-m','pip','check') 'pip_check.log'
        if ($rc -ne 0) { Record-Warning 'pip check reported broken dependency requirements.' }
        $rc = Call-Process 'pip_inspect' $script:PythonExe @('-m','pip','inspect','--local') 'pip_inspect.json'
        if ($rc -ne 0) { Record-Warning 'pip inspect failed; consult log.' }
        if (-not $SkipAudit) {
            $argsAfter = @($script:AuditTool,'--phase','after','--out-dir',$script:RunDir)
            if ($null -ne $manifest) { $argsAfter += @('--manifest',(Join-Path $script:RunDir 'manifest_validated.txt')) }
            $rc = Call-Process 'audit_after' $script:PythonExe $argsAfter 'audit_after.log'
            if ($rc -ne 0) { Record-Warning 'Dependency audit failed; see audit_after.log.' }
        }
    }
} catch {
    $script:State = 'FAILED'
    $script:ExitCode = 1
    $script:Failure = $_.Exception.Message
    Record-Step 'execution' 'FAILED' $script:Failure
} finally {
    if ($null -ne $script:RunDir -and (Test-Path -LiteralPath $script:RunDir -PathType Container)) {
        if ($script:State -eq 'SUCCESS' -and $script:Problems.Count -gt 0) {
            $script:State = 'WARN'
            $script:ExitCode = 2
        }
        try { Write-Summaries } catch {
            Write-Warning ('Report writing failed: ' + $_.Exception.Message)
            $script:ExitCode = 1
        }
        Write-Host ('OUTPUT: ' + $script:RunDir)
    }
    Write-Host ('STATUS: ' + $script:State)
}
exit $script:ExitCode
