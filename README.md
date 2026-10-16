# CODEX MAGI 1,001+

Reproducible Python/tooling environment for MAGI/Codex work.

## Master contract

- **1,001 explicit top-level Python targets** in `requirements/CODEX_FINAL_1001_DEPENDENCIES.txt`.
- **`+` = external/native/runtime capabilities** installed alongside the Python catalog.
- Chromium is now an official `1,001+` runtime dependency and is installed through Playwright's browser manager.
- The actual `pip list` total may be greater than 1,001 because pip installs transitive dependencies.
- Windows local runtime and Codex Cloud/Linux share the same Python catalog but use platform-specific installers.

## Layout

```text
requirements/
  CODEX_FINAL_1001_DEPENDENCIES.txt
  CODEX_FINAL_1001_MANIFEST.tsv
  CODEX_FINAL_109_NEW_ADDITIONS.txt
external/
  EXTERNAL_RUNTIME_DEPENDENCIES.txt
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

## What `1,001+` means

`1,001` is the exact first-class Python target contract. The `+` is for non-Python runtimes and native tools that extend the worker without changing that Python count.

Current official `+` runtime:

```text
Chromium (managed by Playwright)
```

Chromium provides a real browser engine for Playwright/browser instrumentation: DOM inspection, JavaScript execution, network tracing, screenshots, console capture, storage/cookies, performance observation and E2E automation.

## Windows local Codex

The Windows installer targets Codex's existing Python 3.12 runtime and:

1. skips Python packages already installed;
2. installs missing Python targets immediately;
3. records failures/timeouts and continues;
4. runs `pip check`;
5. installs/updates the Playwright-managed Chromium runtime.

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

It reads the same 1,001-package master list, skips already-installed distributions, skips the explicit Windows-only exclusion set, installs the remaining missing packages one by one, then installs the Playwright-managed Chromium runtime.

## Important native/external runtimes

`1,001+` is intended to grow on this side without changing the exact 1,001 Python-target contract. Chromium is now managed automatically. Other external runtimes may include Ghidra, FluidSynth, Rubber Band, VLC, FFmpeg, ASIO drivers, UAD software/licensing, and CLAP/JUCE native hosts as they are incorporated into the bootstrap.
