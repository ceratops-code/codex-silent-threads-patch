# Contributing

## Workflow

1. Keep changes small and reversible.
2. Update tests when patch logic changes.
3. Fail safe: if a new Codex build no longer matches the expected anchors, make the patcher stop with a clear error instead of guessing.
4. Validate on a copied `app.asar` before testing in place.

## Local Checks

Run the linter:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Run-Lint.ps1
```

Run the smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Run-SmokeTests.ps1
```

Run a dry patch to another file:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\patch-codex.ps1 -AsarPath C:\path\to\app.asar -OutputPath C:\path\to\patched.asar
```
