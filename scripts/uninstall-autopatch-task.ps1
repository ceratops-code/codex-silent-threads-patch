[CmdletBinding()]
param(
  [string]$TaskName = 'Codex Desktop Autopatch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\CodexDesktopPatcher.psd1') -Force

Unregister-CodexAutopatchTask -TaskName $TaskName

[pscustomobject]@{
  TaskName = $TaskName
  Removed  = $true
} | Format-List
