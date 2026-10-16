# CODEX / MAGI — FINAL 1001 EXPLICIT DEPENDENCIES

## Count contract

- Previous explicit target set: **892**
- New first-class additions: **109**
- Final explicit top-level targets: **1001**
- Normalized duplicates: **0**

This is a target-count contract, not a `pip list` distribution-count contract.
The actual environment can contain more than 1001 distributions because pip
adds transitive dependencies. The installer reports how many of the exact 1001
manifest targets are present.

## New additions

- Audio / MIDI / music / realtime: **60**
- UI / desktop / visualization: **15**
- Coding / project / quality: **20**
- Binary / file / forensics: **14**

## Project-history restorations

The final additions intentionally include `dawdreamer` and `pyflp`, because they
are directly relevant to the MAGI / MAGIDreamer / FL Studio parser work and were
not present in the previous 892-target master list.

The audio expansion also includes live MIDI (`python-rtmidi`), realtime audio
I/O (`sounddevice`), synthesis (`pyo`, `pyfluidsynth`), UI/media infrastructure
(`PySide6`), and Rubber Band integration (`pyrubberband`).

## Native/external runtime notes

Some Python packages are bridges and still need external software for full use:

- `pyfluidsynth` -> FluidSynth native library / SoundFonts.
- `pyrubberband` -> Rubber Band executable/library.
- `python-vlc` -> VLC installation.
- `sounddevice` -> audio device driver; ASIO requires an ASIO-capable driver/backend.
- `pyo` -> may require a source/native build on Python 3.12 Windows if no compatible wheel exists.
- `PySide6` -> large Qt runtime.
- `msclap` and `laion-clap` are CLAP *audio-language models*, NOT CLAP plugin-format hosts.
- CLAP plugin hosting still belongs to a native CLAP host/bridge.
- UAD plugins still require their vendor installation/licensing/hardware as applicable.

## Files

- `CODEX_FINAL_1001_DEPENDENCIES.txt` — exact final target list.
- `CODEX_FINAL_109_NEW_ADDITIONS.txt` — only the new additions.
- `CODEX_FINAL_109_NEW_ADDITIONS_BY_CATEGORY.md` — grouped additions.
- `CODEX_FINAL_1001_MANIFEST.tsv` — indexed manifest.
- `install_codex_FINAL_1001_direct.ps1` — direct installer, skips existing packages.
- `test_codex_FINAL_1001_preflight.ps1` — separate tester, installs nothing.
