# Codex Silent Threads Patch

Patch the Windows Codex desktop app so automation behavior follows the active automation prompt and applicable `AGENTS.md` files instead of a hard-coded higher-level automation inbox or memory policy.

This repo is self-contained. It uses PowerShell only. It does not require `node`, `npm`, `gh`, Python, or a full rebuilt `app.asar`.

## What It Does

- Finds the installed `OpenAI.Codex_*` Windows package.
- Backs up the current `app.asar`.
- Reads and rebuilds the `asar` archive directly in PowerShell.
- Patches the embedded runtime bundles by replacing the hard-coded automation developer-instruction template and app-context inbox guidance.
- Restores from backup if needed.
- Optionally registers an elevated scheduled task to re-run the patch automatically after updates.

## How It Works

The patcher targets the Codex automation developer-instruction template and app-context automation guidance inside the Electron app bundle. It replaces the forced-output text so future automation runs:

- follow the active automation prompt and applicable `AGENTS.md` files for memory handling, silent-run policy, conflict reporting, and completion gates
- stop forcing an inbox item for every automation response
- stop forcing automation memory reads and writes when lower-level instructions forbid them

The patcher fails safe. If the expected anchor text is not found in a new Codex build, it stops with a clear error instead of patching blindly.

## Requirements

- Windows
- Elevated PowerShell for in-place patching of the installed app under `C:\Program Files\WindowsApps`

## Usage

Patch the installed Codex app in place:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\patch-codex.ps1 -StopCodex
```

Patch a copied `app.asar` to another output file:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\patch-codex.ps1 -AsarPath C:\path\to\app.asar -OutputPath C:\path\to\patched.asar
```

Restore the latest backup:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore-codex.ps1 -StopCodex
```

Install the optional autopatch scheduled task from elevated PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-autopatch-task.ps1
```

Remove the scheduled task:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall-autopatch-task.ps1
```

## Backups

By default, backups are stored in:

```text
%USERPROFILE%\.codex\backups
```

## Validation

Run the linter:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Run-Lint.ps1
```

Run the smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Run-SmokeTests.ps1
```

## Limitations

- The patcher is intentionally narrow. It patches known automation instruction and app-context anchors.
- If OpenAI changes those anchors substantially, the patcher will stop until the anchors are updated here.
- Windows app repairs or updates can replace the patched `app.asar`. Re-run the patch or let the scheduled task re-apply it.

## Repository Layout

- `src/CodexDesktopPatcher.psd1`: module manifest and public export surface
- `src/CodexDesktopPatcher.psm1`: core `asar` reader, writer, patch logic, backup, restore, and scheduled-task helpers
- `scripts/patch-codex.ps1`: patch entrypoint
- `scripts/restore-codex.ps1`: restore entrypoint
- `scripts/install-autopatch-task.ps1`: register the scheduled repatch task
- `scripts/uninstall-autopatch-task.ps1`: unregister the scheduled task
- `tests/Run-SmokeTests.ps1`: smoke test without external dependencies

## Safety Notes

- Review the backup path before deleting old backups.
- Close Codex before patching unless you explicitly use `-StopCodex`.
- Test on a copied `app.asar` first if you are updating the patch logic.
