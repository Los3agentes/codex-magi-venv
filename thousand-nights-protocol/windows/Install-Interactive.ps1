#requires -Version 5.1
<#
.SYNOPSIS
    Start Thousand Nights installation with the Windows folder picker.
.DESCRIPTION
    Opens the native folder picker for the installation directory, even if
    a default was configured. Does not prompt for or change report location.
.EXAMPLE
    .\windows\Install-Interactive.ps1 -ManifestPath 'D:\Manifests\CODEX_FINAL_1001_DEPENDENCIES.txt'
#>
& (Join-Path $PSScriptRoot 'install_thousand_nights_protocol.ps1') -Mode Install -InstallFolderPicker Always @args
exit $LASTEXITCODE
