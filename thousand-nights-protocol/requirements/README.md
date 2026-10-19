# Manifest location

This component uses the canonical file already present in the parent GitHub repository:

`../../requirements/CODEX_FINAL_1001_DEPENDENCIES.txt`

The PowerShell installer discovers that file automatically. Do not duplicate the 1001 entries.
If you extract this folder standalone, use `-ManifestPath` or the provided
`windows/Get-CanonicalManifest.ps1` helper to fetch the manifest with `gh`.
