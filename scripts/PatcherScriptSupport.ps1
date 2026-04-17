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

function ConvertTo-PowerShellSingleQuotedLiteral {
  param(
    [AllowEmptyString()]
    [string]$Value
  )

  return "'" + ($Value -replace "'", "''") + "'"
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

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string[]]$ArgumentList = @()
  )

  $output = & $FilePath @ArgumentList 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $message = ($output | Out-String).Trim()
    throw "$FilePath failed with exit code $exitCode. $message"
  }

  return $output
}

function Copy-ItemWithTemporaryWriteAccess {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  if (-not (Test-IsAdministrator)) {
    throw "Temporary ACL fallback for '$Destination' requires an elevated PowerShell session."
  }

  if (-not $PSCmdlet.ShouldProcess($Destination, 'Temporarily grant Administrators write access and copy file')) {
    return [pscustomobject]@{
      TemporaryAclUsed = $false
    }
  }

  $originalAcl = Get-Acl -LiteralPath $Destination

  try {
    Invoke-NativeCommand -FilePath 'takeown.exe' -ArgumentList @('/F', $Destination, '/A') | Out-Null
    Invoke-NativeCommand -FilePath 'icacls.exe' -ArgumentList @($Destination, '/grant', '*S-1-5-32-544:F') | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
  finally {
    if ($originalAcl) {
      Set-Acl -LiteralPath $Destination -AclObject $originalAcl
    }
  }

  return [pscustomobject]@{
    TemporaryAclUsed = $true
    SystemTaskUsed = $false
  }
}

function Copy-ItemWithSystemTask {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  if (-not (Test-IsAdministrator)) {
    throw "SYSTEM copy fallback for '$Destination' requires an elevated PowerShell session."
  }

  if (-not $PSCmdlet.ShouldProcess($Destination, 'Copy file through a temporary SYSTEM scheduled task')) {
    return [pscustomobject]@{
      TemporaryAclUsed = $false
      SystemTaskUsed = $false
    }
  }

  $workDirectory = Join-Path $env:ProgramData 'CodexSilentThreadsPatch'
  if (-not (Test-Path -LiteralPath $workDirectory)) {
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
  }

  $taskId = [guid]::NewGuid().ToString('N')
  $taskName = "CodexSilentThreadsPatchCopy-$taskId"
  $taskScriptPath = Join-Path $workDirectory "$taskName.ps1"
  $taskLogPath = Join-Path $workDirectory "$taskName.log"
  $sourceLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value ([System.IO.Path]::GetFullPath($Source))
  $destinationLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value ([System.IO.Path]::GetFullPath($Destination))
  $logLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Value $taskLogPath

  $taskScript = @"
`$ErrorActionPreference = 'Stop'
try {
  Copy-Item -LiteralPath $sourceLiteral -Destination $destinationLiteral -Force
  "Copied $sourceLiteral to $destinationLiteral" | Set-Content -LiteralPath $logLiteral -Encoding UTF8
  exit 0
}
catch {
  (`$_ | Out-String) | Set-Content -LiteralPath $logLiteral -Encoding UTF8
  exit 1
}
"@

  Set-Content -LiteralPath $taskScriptPath -Value $taskScript -Encoding UTF8

  try {
    $taskArgument = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $taskScriptPath
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgument
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    $deadline = (Get-Date).AddSeconds(60)
    do {
      Start-Sleep -Milliseconds 500
      $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    } while (($task.State -eq 'Running') -and ((Get-Date) -lt $deadline))

    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
    if ($task.State -eq 'Running') {
      throw "Timed out waiting for temporary SYSTEM copy task '$taskName'."
    }

    if ($taskInfo.LastTaskResult -ne 0) {
      $logText = if (Test-Path -LiteralPath $taskLogPath) { (Get-Content -LiteralPath $taskLogPath | Out-String).Trim() } else { '' }
      throw "Temporary SYSTEM copy task '$taskName' failed with result $($taskInfo.LastTaskResult). $logText"
    }
  }
  finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $taskScriptPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $taskLogPath -Force -ErrorAction SilentlyContinue
  }

  return [pscustomobject]@{
    TemporaryAclUsed = $false
    SystemTaskUsed = $true
  }
}

function Copy-ItemWithAclFallback {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [switch]$AllowTemporaryAcl
  )

  try {
    if ($PSCmdlet.ShouldProcess($Destination, 'Copy file')) {
      Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }

    return [pscustomobject]@{
      TemporaryAclUsed = $false
      SystemTaskUsed = $false
    }
  }
  catch {
    if ((-not $AllowTemporaryAcl) -or ($_.Exception -isnot [System.UnauthorizedAccessException])) {
      throw
    }

    try {
      return Copy-ItemWithTemporaryWriteAccess -Source $Source -Destination $Destination
    }
    catch {
      return Copy-ItemWithSystemTask -Source $Source -Destination $Destination
    }
  }
}
