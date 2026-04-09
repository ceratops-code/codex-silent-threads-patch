[CmdletBinding()]
param(
  [string]$AsarPath,
  [string]$OutputPath,
  [string]$BackupDirectory = (Join-Path $env:USERPROFILE '.codex\backups'),
  [switch]$StopCodex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\CodexDesktopPatcher.psd1') -Force

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-CodexProcess {
  [CmdletBinding(SupportsShouldProcess)]
  param()

  Get-Process Codex, codex -ErrorAction SilentlyContinue | ForEach-Object {
    if ($PSCmdlet.ShouldProcess($_.ProcessName, 'Stop process')) {
      $_ | Stop-Process -Force
    }
  }
}

if (-not $AsarPath) {
  $installRoot = Get-CodexInstallRoot
  $AsarPath = Get-CodexAppAsarPath -InstallRoot $installRoot
}

$asarFullPath = [System.IO.Path]::GetFullPath($AsarPath)
$windowsAppsRoot = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps'))
$patchingInstalledApp = $asarFullPath.StartsWith($windowsAppsRoot, [System.StringComparison]::OrdinalIgnoreCase) -and -not $OutputPath

if ($patchingInstalledApp -and -not (Test-IsAdministrator)) {
  throw 'In-place patching of the installed Codex app requires an elevated PowerShell session.'
}

if ($StopCodex) {
  if (-not (Test-IsAdministrator)) {
    throw 'Stopping the installed Codex processes requires an elevated PowerShell session.'
  }

  Stop-CodexProcess -Confirm:$false
}

$inPlace = -not $OutputPath
$effectiveOutputPath =
  if ($inPlace) {
    Join-Path $env:TEMP ('codex-app-' + [guid]::NewGuid().ToString('N') + '.asar')
  }
  else {
    [System.IO.Path]::GetFullPath($OutputPath)
  }

$backupPath = $null
if ($patchingInstalledApp) {
  $backupPath = Backup-CodexAppAsar -AsarPath $asarFullPath -BackupDirectory $BackupDirectory
}

$result = Write-CodexPatchedAsar -InputAsarPath $asarFullPath -OutputAsarPath $effectiveOutputPath

if ($inPlace) {
  if ($result.Status -eq 'Patched') {
    Copy-Item -LiteralPath $effectiveOutputPath -Destination $asarFullPath -Force
  }

  Remove-Item -LiteralPath $effectiveOutputPath -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
  Status         = $result.Status
  BundlePath     = $result.BundlePath
  AsarPath       = $asarFullPath
  BackupPath     = $backupPath
  OutputPath     = if ($inPlace) { $asarFullPath } else { $effectiveOutputPath }
  FastPathUsed   = $result.FastPathUsed
  PatchedInPlace = $inPlace
} | Format-List
