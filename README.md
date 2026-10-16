# codex-magi-venv

Reproducible Python/tooling environment for MAGI/Codex work.

## Master contract

- **1,001 explicit top-level Python targets** in `requirements/CODEX_FINAL_1001_DEPENDENCIES.txt`.
- The actual `pip list` total may be greater than 1,001 because pip installs transitive dependencies.
- Windows local runtime and Codex Cloud/Linux share the same master catalog but use platform-specific installers.

## Layout

```text
requirements/
  CODEX_FINAL_1001_DEPENDENCIES.txt
  CODEX_FINAL_1001_MANIFEST.tsv
  CODEX_FINAL_109_NEW_ADDITIONS.txt
windows/
  install_codex_FINAL_1001_direct.ps1
  test_codex_FINAL_1001_preflight.ps1
cloud/
  install_cloud.sh
  PLATFORM_EXCLUSIONS.txt
docs/
  CODEX_FINAL_1001_REPORT.md
  CODEX_FINAL_109_NEW_ADDITIONS_BY_CATEGORY.md
```

## Windows local Codex

The Windows installer targets Codex's existing Python 3.12 runtime and:

1. skips packages already installed;
2. installs missing targets immediately;
3. records failures/timeouts and continues;
4. runs `pip check` at the end.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\install_codex_FINAL_1001_direct.ps1
```

The preflight tester is separate and installs nothing:

```powershell
.\windows\test_codex_FINAL_1001_preflight.ps1
```

## Codex Cloud / Linux

Use the cloud bootstrap from the repository root:

```bash
bash cloud/install_cloud.sh
```

It reads the same 1,001-package master list, skips already-installed distributions, skips the explicit Windows-only exclusion set, and installs the remaining missing packages one by one so one incompatible package does not abort the full bootstrap.

## Important native/external runtimes

Some Python packages are bridges and still need system software for full capability, for example Ghidra, FluidSynth, Rubber Band, VLC, FFmpeg, ASIO drivers, UAD software/licensing, and CLAP/JUCE native hosts.
