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

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
  throw 'Restoring the installed Codex app requires an elevated PowerShell session.'
}

if (-not $AsarPath) {
  $installRoot = Get-CodexInstallRoot
  $AsarPath = Get-CodexAppAsarPath -InstallRoot $installRoot
}

if ($StopCodex) {
  Get-Process Codex, codex -ErrorAction SilentlyContinue | Stop-Process -Force
}

$restoredFrom = Restore-CodexAppAsar -AsarPath ([System.IO.Path]::GetFullPath($AsarPath)) -BackupPath $BackupPath -BackupDirectory $BackupDirectory

[pscustomobject]@{
  AsarPath     = [System.IO.Path]::GetFullPath($AsarPath)
  RestoredFrom = $restoredFrom
} | Format-List
