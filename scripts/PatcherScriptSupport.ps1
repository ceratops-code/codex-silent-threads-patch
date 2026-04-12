Set-StrictMode -Version Latest

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-ProcessArgument {
  param(
    [AllowEmptyString()]
    [string]$Value
  )

  if ($null -eq $Value) {
    return '""'
  }

  if ($Value -notmatch '[\s"]') {
    return $Value
  }

  return '"' + ($Value -replace '"', '\"') + '"'
}

function Start-ScriptElevated {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [string[]]$ArgumentList = @()
  )

  $powerShellArguments = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    (ConvertTo-ProcessArgument -Value ([System.IO.Path]::GetFullPath($ScriptPath)))
  ) + $ArgumentList

  if (-not $PSCmdlet.ShouldProcess($ScriptPath, 'Relaunch script elevated')) {
    return
  }

  try {
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $powerShellArguments -Verb RunAs -Wait -PassThru
  }
  catch {
    throw "Elevation is required, but launching the elevated PowerShell process failed or was canceled. $($_.Exception.Message)"
  }

  if (($null -ne $process.ExitCode) -and ($process.ExitCode -ne 0)) {
    exit $process.ExitCode
  }

  exit 0
}
