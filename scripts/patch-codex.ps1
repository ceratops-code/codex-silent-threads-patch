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
. (Join-Path $PSScriptRoot 'PatcherScriptSupport.ps1')

function Get-PatchReinvokeArgumentList {
  $arguments = @()

  if ($AsarPath) {
    $arguments += @('-AsarPath', (ConvertTo-ProcessArgument -Value $AsarPath))
  }

  if ($OutputPath) {
    $arguments += @('-OutputPath', (ConvertTo-ProcessArgument -Value $OutputPath))
  }

  if ($BackupDirectory) {
    $arguments += @('-BackupDirectory', (ConvertTo-ProcessArgument -Value $BackupDirectory))
  }

  if ($StopCodex.IsPresent) {
    $arguments += '-StopCodex'
  }

  return $arguments
}

function Stop-CodexProcess {
  [CmdletBinding(SupportsShouldProcess)]
  param()

  $processes = @(Get-Process Codex, codex -ErrorAction SilentlyContinue)

  $processes | ForEach-Object {
    if ($PSCmdlet.ShouldProcess($_.ProcessName, 'Stop process')) {
      $_ | Stop-Process -Force
    }
  }

  foreach ($process in $processes) {
    try {
      Wait-Process -Id $process.Id -Timeout 30 -ErrorAction Stop
    }
    catch {
      if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
        throw "Timed out waiting for Codex process $($process.Id) to exit."
      }
    }
  }
}

if ((-not $AsarPath) -and (-not $OutputPath) -and -not (Test-IsAdministrator)) {
  Start-ScriptElevated -ScriptPath $PSCommandPath -ArgumentList (Get-PatchReinvokeArgumentList)
}

if (-not $AsarPath) {
  $installRoot = Get-CodexInstallRoot
  $AsarPath = Get-CodexAppAsarPath -InstallRoot $installRoot
}

$asarFullPath = [System.IO.Path]::GetFullPath($AsarPath)
$windowsAppsRoot = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps'))
$patchingInstalledApp = $asarFullPath.StartsWith($windowsAppsRoot, [System.StringComparison]::OrdinalIgnoreCase) -and -not $OutputPath

if ($patchingInstalledApp -and -not (Test-IsAdministrator)) {
  Start-ScriptElevated -ScriptPath $PSCommandPath -ArgumentList (Get-PatchReinvokeArgumentList)
}

if ($StopCodex) {
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
$temporaryAclUsed = $false
$systemTaskUsed = $false

if ($inPlace) {
  if ($result.Status -eq 'Patched') {
    $copyResult = Copy-ItemWithAclFallback -Source $effectiveOutputPath -Destination $asarFullPath -AllowTemporaryAcl:$patchingInstalledApp
    $temporaryAclUsed = $copyResult.TemporaryAclUsed
    $systemTaskUsed = $copyResult.SystemTaskUsed
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
  TemporaryAclUsed = $temporaryAclUsed
  SystemTaskUsed = $systemTaskUsed
} | Format-List
