# Thousand Nights Protocol — PS1 configurable-output edition (codex-magi-venv)

Windows PowerShell **5.1 / Windows** implementation for a dedicated **Python 3.12** runtime,
with explicitly chosen installation and report locations. **Version: 0.2.1**.

> This is a new implementation built from the known runtime/dependency contract,
> **not a patched copy of the earlier `Thousand_Nights_Protocol_Kit.zip`**, whose
> original script was not available for a direct source-level comparison.

## Installation folder picker (Windows)

When running **`-Mode Install`** or **`-Mode Verify`** interactively, the script opens
Windows' native **Browse for Folder** dialog to select the **install location**.
It selects the folder itself as `InstallRoot` and creates `Venv/` inside it only
when installation is requested. The selection happens before the runtime is changed.

```powershell
# From the codex-magi-venv repository root (always opens folder picker):
.\thousand-nights-protocol\windows\Install-Interactive.ps1

# Opens the installation folder picker automatically:
.\thousand-nights-protocol\windows\ThousandNights.ps1 -Mode Install

# Explicitly request the picker even in Plan mode:
.\thousand-nights-protocol\windows\ThousandNights.ps1 -Mode Plan -InstallFolderPicker Always

# Unattended execution: do not display a dialog:
.\thousand-nights-protocol\windows\ThousandNights.ps1 -Mode Install -InstallFolderPicker Never -InstallRoot 'D:\Thousand Nights\Runtime' -ManifestPath '.\requirements\CODEX_FINAL_1001_DEPENDENCIES.txt'
```

Picker rules: `Auto` (default) shows the dialog for Install/Verify if no
`-InstallRoot` or `install_root` config value was supplied; `Always` forces it
(including Plan); `Never` disables it. Selecting **Cancel** aborts before
installing anything. The folder picker requires an interactive Windows desktop
and an STA PowerShell session (Windows PowerShell 5.1 normally uses STA).

The **output/report folder is separate**. `-OutputRoot` can still point elsewhere.

## Output modes

| Mode | Meaning | Where artifacts go |
|---|---|---|
| `Default` | Use standard runtime report location | `<InstallRoot>\Reports\Run-<unique-id>` |
| `Auto` *(default)* | Choose a base folder, create a unique run folder | `<OutputRoot>\Run-<unique-id>`, or default if omitted |
| `Custom` | Write exactly to your chosen directory | `<OutputRoot>` (refuses to overwrite pre-existing summaries) |

Formats: `All` *(default)*, `Json`, `Markdown`, `Csv`.
Output settings can also be loaded from `-ConfigPath` (JSON), with explicit CLI flags taking precedence.
**Note:** Format controls the *summary files*. Detailed logs and audit artifacts
are written when applicable regardless of the chosen summary format.

## Quick start

Use a Windows PowerShell terminal in the extracted repository directory. If
Windows blocks local PS1 scripts, optionally set execution policy for **that
terminal session only**: `Set-ExecutionPolicy -Scope Process Bypass`. Then:

```powershell
# Safe preview: no packages installed
.\thousand-nights-protocol\windows\install_thousand_nights_protocol.ps1 -Mode Plan `
  -OutputMode Custom -OutputRoot 'D:\Thousand Nights\Audit' `
  -ReportFormat All

# Install into a dedicated venv; manifest discovered from root requirements.
# Omitting -InstallRoot opens the native folder picker.
.\thousand-nights-protocol\windows\install_thousand_nights_protocol.ps1 -Mode Install `
  -OutputMode Auto -OutputRoot 'E:\Thousand Nights\Reports' `
  -ReportFormat All -InstallChromium

# Verify an existing runtime (does not install packages)
.\thousand-nights-protocol\windows\install_thousand_nights_protocol.ps1 -Mode Verify `
  -InstallRoot 'D:\Thousand Nights\Runtime' `
  -OutputMode Auto -OutputRoot 'E:\Thousand Nights\Reports'
```

When the picker is disabled and no path was supplied, the installation root defaults to:

`%USERPROFILE%\Documents\Magi 3\Runtime\Dependencies\Python\Thousand Nights Protocol`

To install a large list one item at a time and keep going after package failures,
add `-ContinueOnPackageError`. This may leave a partially installed environment.

### Persistent output configuration

To define output once, edit `thousand-nights-protocol/config/output.example.json` or save a copy as
`thousand-nights-protocol/config/output.json`, then launch:

```powershell
.\thousand-nights-protocol\windows\install_thousand_nights_protocol.ps1 -Mode Plan -ConfigPath '.\thousand-nights-protocol\config\output.json'
```

Flags passed at execution (for example `-OutputRoot`) take precedence over the
JSON configuration. This file is not required for normal operation.

### Parameters

| Parameter | Behavior |
|---|---|
| `-Mode Plan\|Install\|Verify` | Preview / install / inspect existing environment; defaults to `Plan`. |
| `-InstallRoot` | Explicit runtime directory (virtual environment under `Venv`); bypasses Auto picker. |
| `-InstallFolderPicker Auto\|Always\|Never` | Windows native folder picker. Default: `Auto`. |
| `-OutputMode Default\|Auto\|Custom` | Report folder behavior. |
| `-OutputRoot` | Report destination; aliases `-OutputPath` and `-Output`. |
| `-ReportFormat All\|Json\|Markdown\|Csv` | Report formats; alias `-OutputFormat`. |
| `-ConfigPath` | Optional JSON file for output/install paths and format. |
| `-ManifestPath` | Optional; by default resolves the canonical manifest from the parent repository's `requirements/` directory. |
| `-InstallChromium` | Optional Playwright Chromium installation within InstallRoot. |
| `-ContinueOnPackageError` | Install each manifest item independently; continue through failures. |
| `-PythonLauncher` | Name/path of launcher supporting `-3.12`; default `py`. |
| `-SkipAudit` | Omit standard-library distribution snapshot and graph extraction. |

## Run output contract

```text
<SelectedOutput>/
    run.json                   # if Json or All
    run.md                     # if Markdown or All
    steps.csv                  # if Csv or All
    manifest_validated.txt     # if a manifest was supplied
    audit_before.json          # Install, unless SkipAudit
    audit_after.json           # Install or Verify, unless SkipAudit
    targets_before.csv         # Install, unless SkipAudit
    targets_after.csv          # Install or Verify, unless SkipAudit
    distributions_before.csv   # Install, unless SkipAudit
    distributions_after.csv    # Install or Verify, unless SkipAudit
    dependency_edges.csv       # Install or Verify, unless SkipAudit
    changes.json               # Install with baseline, unless SkipAudit
    failed_packages.txt        # if individual installs fail
    Logs/                      # commands and pip diagnostics
```

The script also records the input manifest's **SHA-256**, package target counts,
interpreter checks, `pip check`, `pip inspect`, status, warnings and failed installs.
Distribution overlap (`before` vs `after`) is stored in `changes.json`.

## Source manifest

Canonical list: `Los3agentes/codex-magi-venv`,
`requirements/CODEX_FINAL_1001_DEPENDENCIES.txt`. The script discovers this
parent-repository manifest automatically when running from this folder.
Use `-ManifestPath` only to select another manifest. For standalone copies,
the GitHub CLI helper is available:

```powershell
.\thousand-nights-protocol\windows\Get-CanonicalManifest.ps1
```
 The name/count is known, but **not every distribution
will necessarily install successfully on Windows** due to platform conflicts.

## Scope and limitations

- No global Python package installation. `Install` writes into `<InstallRoot>\Venv`.
- Default mode is `Plan`. Reports **do** write into the specified output directory.
- `Verify` and `Plan` do not install packages or Chromium.
- The historical kit's complete MD/PDF dependency report formatting was unavailable;
  **PDF generation and original overlap categories are not claimed to be reproduced**.
- Large dependency lists can require significant disk space and still fail resolution.
- Never store access tokens, credentials, locally generated logs or binary runtimes in Git.
- This package contains no third-party dependencies; Python 3.12 installation is an
  external prerequisite. Third-party packages in the canonical manifest keep their
  own licenses. No license is granted for the repository until the owner chooses one.

## Testing

`python -m unittest discover -s tests -v` runs stdlib audit tests. GitHub Actions
has PowerShell 5.1 parse/Plan checks on `windows-latest`; full 1001-install is not
run in CI.

This directory lives inside [Los3agentes/codex-magi-venv](https://github.com/Los3agentes/codex-magi-venv). The existing `windows/install_codex_FINAL_1001_direct.ps1` remains untouched.
