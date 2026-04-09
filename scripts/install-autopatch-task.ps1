[CmdletBinding()]
param(
  [string]$TaskName = 'Codex Desktop Autopatch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\CodexDesktopPatcher.psd1') -Force

$task = Register-CodexAutopatchTask -PatchScriptPath (Join-Path $PSScriptRoot 'patch-codex.ps1') -TaskName $TaskName

[pscustomobject]@{
  TaskName = $task
  Script   = (Join-Path $PSScriptRoot 'patch-codex.ps1')
} | Format-List
