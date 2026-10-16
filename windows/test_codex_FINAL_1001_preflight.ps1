# CODEX / MAGI - FINAL 1001 PREFLIGHT TESTER
# Installs NOTHING. Already-installed packages are skipped as HAVE.
# Only missing targets are tested with pip --dry-run.

param(
    [string]$RuntimeRoot = "C:\Users\halmi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python",
    [int]$ResolveTimeoutSeconds = 180
)

$ErrorActionPreference = "Continue"
$Python = Join-Path $RuntimeRoot "python.exe"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Requirements = Join-Path $RepoRoot "requirements\CODEX_FINAL_1001_DEPENDENCIES.txt"
$LogRoot = Join-Path (Split-Path $RuntimeRoot -Parent) "MAGI_TOOLKIT_INSTALL"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $Python)) { throw "Codex Python not found: $Python" }
if (-not (Test-Path $Requirements)) { throw "Requirements file not found: $Requirements" }

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$ReportFile = Join-Path $LogRoot "FINAL1001_preflight_report_$Timestamp.txt"
$HaveFile = Join-Path $LogRoot "FINAL1001_preflight_have_$Timestamp.txt"
$ResolvesFile = Join-Path $LogRoot "FINAL1001_preflight_resolves_$Timestamp.txt"
$FailedFile = Join-Path $LogRoot "FINAL1001_preflight_failed_$Timestamp.txt"
$TimeoutFile = Join-Path $LogRoot "FINAL1001_preflight_timeout_$Timestamp.txt"

$Packages = @(Get-Content $Requirements | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($Packages.Count -ne 1001) { throw "Manifest contract violation: expected 1001 explicit targets, found $($Packages.Count)." }

$Have = New-Object System.Collections.Generic.List[string]
$Resolves = New-Object System.Collections.Generic.List[string]
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

function Test-Resolve {
    param([string]$Package, [int]$TimeoutSeconds)
    $Safe = ($Package -replace '[^A-Za-z0-9_.-]', '_')
    $StdOut = Join-Path $LogRoot "FINAL1001_preflight_${Safe}_${Timestamp}.out.log"
    $StdErr = Join-Path $LogRoot "FINAL1001_preflight_${Safe}_${Timestamp}.err.log"
    $Proc = Start-Process -FilePath $Python -ArgumentList @("-m","pip","install","--dry-run","--prefer-binary",$Package) -PassThru -NoNewWindow -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr
    $Finished = $Proc.WaitForExit($TimeoutSeconds * 1000)
    if (-not $Finished) {
        try { $Proc.Kill() } catch {}
        return [PSCustomObject]@{Status="TIMEOUT"; ExitCode=$null; StdErr=$StdErr}
    }
    return [PSCustomObject]@{Status="EXIT"; ExitCode=$Proc.ExitCode; StdErr=$StdErr}
}

Write-Host "=== CODEX / MAGI FINAL 1001 PREFLIGHT ===" -ForegroundColor Cyan
Write-Host "Installs: NONE"

$i = 0
foreach ($Package in $Packages) {
    $i++
    if (Test-Installed $Package) {
        $Have.Add($Package)
        Write-Host "[$i/1001] HAVE $Package" -ForegroundColor DarkGreen
        continue
    }

    Write-Host "[$i/1001] TEST $Package"
    try {
        $Result = Test-Resolve -Package $Package -TimeoutSeconds $ResolveTimeoutSeconds
        if ($Result.Status -eq "TIMEOUT") {
            $TimedOut.Add("$Package`tTIMEOUT")
            Write-Host "            TIMEOUT" -ForegroundColor Yellow
        } elseif ($Result.ExitCode -eq 0) {
            $Resolves.Add($Package)
            Write-Host "            RESOLVES" -ForegroundColor Green
        } else {
            $Tail = ""
            if (Test-Path $Result.StdErr) { $Tail = ((Get-Content $Result.StdErr -Tail 10) -join " | ") }
            $Failed.Add("$Package`tEXIT $($Result.ExitCode)`t$Tail")
            Write-Host "            RESOLUTION FAIL" -ForegroundColor Red
        }
    } catch {
        $Failed.Add("$Package`tPROCESS ERROR`t$($_.Exception.Message)")
        Write-Host "            PROCESS ERROR" -ForegroundColor Red
    }
}

$Have | Set-Content $HaveFile -Encoding UTF8
$Resolves | Set-Content $ResolvesFile -Encoding UTF8
$Failed | Set-Content $FailedFile -Encoding UTF8
$TimedOut | Set-Content $TimeoutFile -Encoding UTF8

$Report = @"
CODEX / MAGI FINAL 1001 PREFLIGHT REPORT
=========================================
Explicit targets: 1001
HAVE:              $($Have.Count)
Missing+resolves:  $($Resolves.Count)
Resolution fail:   $($Failed.Count)
Timeout:           $($TimedOut.Count)

This tester installs NOTHING.
"@
$Report | Set-Content $ReportFile -Encoding UTF8

Write-Host "=== PREFLIGHT COMPLETE ===" -ForegroundColor Green
Write-Host "HAVE: $($Have.Count)  RESOLVES: $($Resolves.Count)  FAIL: $($Failed.Count)  TIMEOUT: $($TimedOut.Count)"
Write-Host "Report: $ReportFile"
