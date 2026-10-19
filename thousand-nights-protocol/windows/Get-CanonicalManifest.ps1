#requires -Version 5.1
<#
Downloads the known manifest using the authenticated GitHub CLI.
Never requires embedding a credential in this script or sharing the manifest publicly.
#>
[CmdletBinding()]
param(
    [string]$Destination = (Join-Path (Split-Path -Parent $PSScriptRoot) 'requirements\CODEX_FINAL_1001_DEPENDENCIES.txt')
)
$ErrorActionPreference = 'Stop'
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($null -eq $gh) { throw 'GitHub CLI not found. Install gh and authenticate using gh auth login.' }
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
if (Test-Path -LiteralPath $target) { throw ('Refusing to overwrite existing file: ' + $target) }
$parent = Split-Path -Parent $target
New-Item -Path $parent -ItemType Directory -Force | Out-Null
$endpoint = 'repos/Los3agentes/codex-magi-venv/contents/requirements/CODEX_FINAL_1001_DEPENDENCIES.txt'
$result = @(& $gh.Source api -H 'Accept: application/vnd.github.raw+json' $endpoint)
if ($LASTEXITCODE -ne 0) { throw 'The GitHub CLI could not read the original manifest. Check repository permissions.' }
$names = @($result | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
if ($names.Count -ne 1001) { throw ('Got ' + $names.Count + ' entries, expected 1001. No file was written.') }
$result | Set-Content -LiteralPath $target -Encoding UTF8
Write-Host ('Saved verified 1001-entry manifest to ' + $target)
