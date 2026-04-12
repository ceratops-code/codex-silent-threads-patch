[CmdletBinding()]
param(
  [string]$TaskName = 'Codex Desktop Autopatch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\CodexDesktopPatcher.psd1') -Force
. (Join-Path $PSScriptRoot 'PatcherScriptSupport.ps1')

if (-not (Test-IsAdministrator)) {
  $arguments = @()
  if ($TaskName) {
    $arguments += @('-TaskName', (ConvertTo-ProcessArgument -Value $TaskName))
  }

  Start-ScriptElevated -ScriptPath $PSCommandPath -ArgumentList $arguments
}

Unregister-CodexAutopatchTask -TaskName $TaskName

[pscustomobject]@{
  TaskName = $TaskName
  Removed  = $true
} | Format-List
