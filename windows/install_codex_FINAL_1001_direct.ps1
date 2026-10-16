# CODEX / MAGI - FINAL 1001 DIRECT INSTALLER
# Reads the canonical package list from ../requirements/CODEX_FINAL_1001_DEPENDENCIES.txt
# and installs only missing explicit targets. No preflight is performed here.

param(
    [string]$RuntimeRoot = "C:\Users\halmi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python",
    [int]$InstallTimeoutSeconds = 1200
)

$ErrorActionPreference = "Continue"
$Python = Join-Path $RuntimeRoot "python.exe"
$Scripts = Join-Path $RuntimeRoot "Scripts"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Requirements = Join-Path $RepoRoot "requirements\CODEX_FINAL_1001_DEPENDENCIES.txt"
$LogRoot = Join-Path (Split-Path $RuntimeRoot -Parent) "MAGI_TOOLKIT_INSTALL"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $Python)) { throw "Codex Python not found: $Python" }
if (-not (Test-Path $Requirements)) { throw "Requirements file not found: $Requirements" }

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$env:PATH = "$Scripts;$env:PATH"

$ReportFile = Join-Path $LogRoot "FINAL1001_install_report_$Timestamp.txt"
$AlreadyFile = Join-Path $LogRoot "FINAL1001_already_$Timestamp.txt"
$InstalledFile = Join-Path $LogRoot "FINAL1001_installed_now_$Timestamp.txt"
$FailedFile = Join-Path $LogRoot "FINAL1001_failed_$Timestamp.txt"
$TimeoutFile = Join-Path $LogRoot "FINAL1001_timeout_$Timestamp.txt"
$BeforeFreeze = Join-Path $LogRoot "FINAL1001_before_freeze_$Timestamp.txt"
$AfterFreeze = Join-Path $LogRoot "FINAL1001_after_freeze_$Timestamp.txt"

$Version = & $Python -c "import sys; print(sys.version.split()[0])"
$MajorMinor = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ($MajorMinor -ne "3.12") { throw "Expected Codex Python 3.12.x; found $Version" }

$Packages = @(Get-Content $Requirements | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($Packages.Count -ne 1001) { throw "Manifest contract violation: expected 1001 explicit targets, found $($Packages.Count)." }

& $Python -m pip freeze | Set-Content -Path $BeforeFreeze -Encoding UTF8

$Already = New-Object System.Collections.Generic.List[string]
$InstalledNow = New-Object System.Collections.Generic.List[string]
$Failed = New-Object System.Collections.Generic.List[string]
$TimedOut = New-Object System.Collections.Generic.List[string]

function Test-Installed {
    param([string]$Name)
    $Code = @'
import importlib.metadata as m, sys
try:
    m.version(sys.argv[1])
    raise SystemExit(0)
except m.PackageNotFoundError:
    raise SystemExit(1)
'@
    & $Python -c $Code $Name *> $null
    return ($LASTEXITCODE -eq 0)
}

function Install-One {
    param([string]$Package, [int]$TimeoutSeconds)
    $Safe = ($Package -replace '[^A-Za-z0-9_.-]', '_')
    $StdOut = Join-Path $LogRoot "FINAL1001_${Safe}_${Timestamp}.out.log"
    $StdErr = Join-Path $LogRoot "FINAL1001_${Safe}_${Timestamp}.err.log"
    $Proc = Start-Process -FilePath $Python -ArgumentList @("-m","pip","install","--prefer-binary",$Package) -PassThru -NoNewWindow -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr
    $Finished = $Proc.WaitForExit($TimeoutSeconds * 1000)
    if (-not $Finished) {
        try { $Proc.Kill() } catch {}
        return [PSCustomObject]@{Status="TIMEOUT"; ExitCode=$null; StdErr=$StdErr}
    }
    return [PSCustomObject]@{Status="EXIT"; ExitCode=$Proc.ExitCode; StdErr=$StdErr}
}

Write-Host "=== CODEX / MAGI FINAL 1001 DIRECT INSTALL ===" -ForegroundColor Cyan
Write-Host "Python: $Version"
Write-Host "Targets: $($Packages.Count)"

$i = 0
foreach ($Package in $Packages) {
    $i++
    if (Test-Installed $Package) {
        $Already.Add($Package)
        Write-Host "[$i/1001] HAVE    $Package" -ForegroundColor DarkGreen
        continue
    }

    Write-Host "[$i/1001] INSTALL $Package" -ForegroundColor Cyan
    try {
        $Result = Install-One -Package $Package -TimeoutSeconds $InstallTimeoutSeconds
        if ($Result.Status -eq "TIMEOUT") {
            $TimedOut.Add("$Package`tTIMEOUT")
            Write-Host "            TIMEOUT" -ForegroundColor Yellow
            continue
        }
        if ($Result.ExitCode -eq 0 -and (Test-Installed $Package)) {
            $InstalledNow.Add($Package)
            Write-Host "            INSTALLED" -ForegroundColor Green
        } else {
            $Tail = ""
            if (Test-Path $Result.StdErr) { $Tail = ((Get-Content $Result.StdErr -Tail 10) -join " | ") }
            $Failed.Add("$Package`tEXIT $($Result.ExitCode)`t$Tail")
            Write-Host "            FAILED" -ForegroundColor Red
        }
    } catch {
        $Failed.Add("$Package`tPROCESS ERROR`t$($_.Exception.Message)")
        Write-Host "            PROCESS ERROR" -ForegroundColor Red
    }
}

$Already | Set-Content $AlreadyFile -Encoding UTF8
$InstalledNow | Set-Content $InstalledFile -Encoding UTF8
$Failed | Set-Content $FailedFile -Encoding UTF8
$TimedOut | Set-Content $TimeoutFile -Encoding UTF8

$PipCheck = & $Python -m pip check 2>&1
$PipCheckExit = $LASTEXITCODE
& $Python -m pip freeze | Set-Content -Path $AfterFreeze -Encoding UTF8
$ExplicitPresent = $Already.Count + $InstalledNow.Count
$DistributionCount = & $Python -c "import importlib.metadata as m; print(len(list(m.distributions())))"

$Report = @"
CODEX / MAGI FINAL 1001 DIRECT INSTALL REPORT
==============================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Python: $Version
Runtime: $RuntimeRoot
Explicit top-level targets: 1001
Already present:            $($Already.Count)
Installed this run:         $($InstalledNow.Count)
Explicit targets present:   $ExplicitPresent / 1001
Install failures:           $($Failed.Count)
Install timeouts:           $($TimedOut.Count)
Total Python distributions: $DistributionCount

PIP CHECK (exit $PipCheckExit)
------------------------------
$($PipCheck -join [Environment]::NewLine)
"@
$Report | Set-Content $ReportFile -Encoding UTF8

Write-Host "=== COMPLETE ===" -ForegroundColor Green
Write-Host "Explicit targets present: $ExplicitPresent / 1001"
Write-Host "Failed: $($Failed.Count)  Timed out: $($TimedOut.Count)"
Write-Host "Report: $ReportFile"
