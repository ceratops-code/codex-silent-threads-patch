@{
  RootModule        = 'CodexDesktopPatcher.psm1'
  ModuleVersion     = '0.1.1'
  GUID              = '14d52131-c0be-4f1c-aa31-d30434d1a5db'
  Author            = 'RomanOstr'
  CompanyName       = 'RomanOstr'
  Copyright         = '(c) 2026 RomanOstr. Licensed under the MIT License.'
  Description       = 'PowerShell helpers for patching the Windows Codex desktop app automation instruction template.'
  PowerShellVersion = '5.1'
  CompatiblePSEditions = @(
    'Desktop'
    'Core'
  )
  FunctionsToExport = @(
    'Backup-CodexAppAsar'
    'Get-AsarFileContent'
    'Get-CodexAppAsarPath'
    'Get-CodexInstallRoot'
    'Read-AsarArchive'
    'Register-CodexAutopatchTask'
    'Restore-CodexAppAsar'
    'Unregister-CodexAutopatchTask'
    'Write-AsarArchiveFromMap'
    'Write-CodexPatchedAsar'
  )
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()
  PrivateData       = @{
    PSData = @{
      Tags = @(
        'codex'
        'windows'
        'powershell'
        'asar'
      )
    }
  }
}
