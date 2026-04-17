[CmdletBinding()]
param(
  [string]$AsarPath,
  [string]$BackupPath,
  [string]$BackupDirectory = (Join-Path $env:USERPROFILE '.codex\backups'),
  [switch]$StopCodex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\CodexDesktopPatcher.psd1') -Force
. (Join-Path $PSScriptRoot 'PatcherScriptSupport.ps1')

function Get-RestoreReinvokeArgumentList {
  $arguments = @()

  if ($AsarPath) {
    $arguments += @('-AsarPath', (ConvertTo-ProcessArgument -Value $AsarPath))
  }

  if ($BackupPath) {
    $arguments += @('-BackupPath', (ConvertTo-ProcessArgument -Value $BackupPath))
  }

  if ($BackupDirectory) {
    $arguments += @('-BackupDirectory', (ConvertTo-ProcessArgument -Value $BackupDirectory))
  }

  if ($StopCodex.IsPresent) {
    $arguments += '-StopCodex'
  }

  return $arguments
}

if (-not (Test-IsAdministrator)) {
  Start-ScriptElevated -ScriptPath $PSCommandPath -ArgumentList (Get-RestoreReinvokeArgumentList)
}

if (-not $AsarPath) {
  $installRoot = Get-CodexInstallRoot
  $AsarPath = Get-CodexAppAsarPath -InstallRoot $installRoot
}

if ($StopCodex) {
  Get-Process Codex, codex -ErrorAction SilentlyContinue | Stop-Process -Force
}

$asarFullPath = [System.IO.Path]::GetFullPath($AsarPath)
$windowsAppsRoot = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps'))
$restoringInstalledApp = $asarFullPath.StartsWith($windowsAppsRoot, [System.StringComparison]::OrdinalIgnoreCase)

if (-not $BackupPath) {
  $BackupPath = Get-ChildItem -LiteralPath $BackupDirectory -Filter '*.bak' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    ForEach-Object { $_.FullName }
}

if (-not $BackupPath) {
  throw "No backup file was found in '$BackupDirectory'."
}

$copyResult = Copy-ItemWithAclFallback -Source $BackupPath -Destination $asarFullPath -AllowTemporaryAcl:$restoringInstalledApp

[pscustomobject]@{
  AsarPath         = $asarFullPath
  RestoredFrom     = $BackupPath
  TemporaryAclUsed = $copyResult.TemporaryAclUsed
  SystemTaskUsed   = $copyResult.SystemTaskUsed
} | Format-List
