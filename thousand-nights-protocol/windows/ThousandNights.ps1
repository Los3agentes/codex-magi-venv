#requires -Version 5.1
# Compatibility short-name launcher for the full installer.
& (Join-Path $PSScriptRoot 'install_thousand_nights_protocol.ps1') @args
exit $LASTEXITCODE
