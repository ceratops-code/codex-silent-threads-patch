Set-StrictMode -Version Latest

function Test-HasProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$InputObject,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Add-OrSetNoteProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$InputObject,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [AllowNull()]
    [object]$Value
  )

  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) {
    Add-Member -InputObject $InputObject -NotePropertyName $Name -NotePropertyValue $Value
    return
  }

  $property.Value = $Value
}

function New-PlainObject {
  return New-Object psobject
}

function Align-4 {
  param(
    [Parameter(Mandatory = $true)]
    [int]$Value
  )

  return [int]([Math]::Ceiling($Value / 4.0) * 4)
}

function Get-ByteSlice {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Bytes,

    [Parameter(Mandatory = $true)]
    [int]$Offset,

    [Parameter(Mandatory = $true)]
    [int]$Length
  )

  $slice = New-Object byte[] $Length
  [Buffer]::BlockCopy($Bytes, $Offset, $slice, 0, $Length)
  return ,$slice
}

function New-AsarIntegrity {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [byte[]]$Content,

    [int]$BlockSize = 4194304
  )

  $hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fullHash = [BitConverter]::ToString($hasher.ComputeHash($Content)).Replace('-', '').ToLowerInvariant()
    $blocks = @()

    for ($index = 0; $index -lt $Content.Length; $index += $BlockSize) {
      $count = [Math]::Min($BlockSize, $Content.Length - $index)
      $block = Get-ByteSlice -Bytes $Content -Offset $index -Length $count
      $blocks += [BitConverter]::ToString($hasher.ComputeHash($block)).Replace('-', '').ToLowerInvariant()
    }

    return [pscustomobject]@{
      algorithm = 'SHA256'
      hash      = $fullHash
      blockSize = $BlockSize
      blocks    = $blocks
    }
  }
  finally {
    $hasher.Dispose()
  }
}

function New-FileEntryObject {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [byte[]]$Content
  )

  return [pscustomobject]@{
    size      = $Content.Length
    offset    = '0'
    integrity = (New-AsarIntegrity -Content $Content)
  }
}

function Ensure-DirectoryFilesNode {
  param(
    [Parameter(Mandatory = $true)]
    [object]$ParentFilesNode,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $existing = $ParentFilesNode.PSObject.Properties[$Name]
  if ($null -ne $existing) {
    return $existing.Value.files
  }

  $directoryEntry = [pscustomobject]@{
    files = (New-PlainObject)
  }

  Add-Member -InputObject $ParentFilesNode -NotePropertyName $Name -NotePropertyValue $directoryEntry
  return $directoryEntry.files
}

function New-AsarHeaderFromFileMap {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Files
  )

  $root = [pscustomobject]@{
    files = (New-PlainObject)
  }

  foreach ($path in ($Files.Keys | Sort-Object)) {
    $segments = $path -split '[\\/]'
    if ($segments.Count -eq 0) {
      continue
    }

    $cursor = $root.files
    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
      $cursor = Ensure-DirectoryFilesNode -ParentFilesNode $cursor -Name $segments[$index]
    }

    $leaf = $segments[$segments.Count - 1]
    $value = $Files[$path]
    $content =
      if ($value -is [byte[]]) {
        $value
      }
      else {
        [System.Text.Encoding]::UTF8.GetBytes([string]$value)
      }

    Add-Member -InputObject $cursor -NotePropertyName $leaf -NotePropertyValue (New-FileEntryObject -Content $content)
  }

  return $root
}

function Get-AsarFileEntries {
  param(
    [Parameter(Mandatory = $true)]
    [object]$FilesNode,

    [string]$Prefix = ''
  )

  $results = New-Object 'System.Collections.Generic.List[object]'

  function Add-AsarEntries {
    param(
      [Parameter(Mandatory = $true)]
      [object]$Node,

      [string]$NodePrefix = ''
    )

    foreach ($property in $Node.PSObject.Properties) {
      $entryPath =
        if ([string]::IsNullOrEmpty($NodePrefix)) {
          $property.Name
        }
        else {
          '{0}/{1}' -f $NodePrefix, $property.Name
        }

      $entry = $property.Value

      if (Test-HasProperty -InputObject $entry -Name 'files') {
        Add-AsarEntries -Node $entry.files -NodePrefix $entryPath
        continue
      }

      if ((Test-HasProperty -InputObject $entry -Name 'size') -and (Test-HasProperty -InputObject $entry -Name 'offset')) {
        $results.Add([pscustomobject]@{
          Path           = $entryPath
          Entry          = $entry
          OriginalOffset = [int]$entry.offset
          OriginalSize   = [int]$entry.size
        })
      }
    }
  }

  Add-AsarEntries -Node $FilesNode -NodePrefix $Prefix
  return $results.ToArray()
}

function Read-AsarArchive {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $headerJsonLength = [BitConverter]::ToInt32($bytes, 12)
  $alignedHeaderLength = [BitConverter]::ToInt32($bytes, 8)
  $dataOffset = 12 + $alignedHeaderLength
  $headerJson = [System.Text.Encoding]::UTF8.GetString($bytes, 16, $headerJsonLength)
  $header = $headerJson | ConvertFrom-Json

  return [pscustomobject]@{
    Path                = $Path
    Bytes               = $bytes
    Header              = $header
    HeaderJson          = $headerJson
    HeaderJsonLength    = $headerJsonLength
    AlignedHeaderLength = $alignedHeaderLength
    DataOffset          = $dataOffset
  }
}

function Get-AsarFileContent {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Archive,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $match = Get-AsarFileEntries -FilesNode $Archive.Header.files | Where-Object { $_.Path -eq $Path } | Select-Object -First 1
  if ($null -eq $match) {
    throw "Archive entry not found: $Path"
  }

  $offset = [int]$match.Entry.offset
  $length = [int]$match.Entry.size
  return Get-ByteSlice -Bytes $Archive.Bytes -Offset ($Archive.DataOffset + $offset) -Length $length
}

function Write-AsarArchive {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Header,

    [Parameter(Mandatory = $true)]
    [System.Collections.IEnumerable]$FilePayloads,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $headerJson = ConvertTo-Json -InputObject $Header -Compress -Depth 100
  $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerJson)
  $headerJsonLength = $headerBytes.Length
  $headerPayloadLength = Align-4 -Value ($headerJsonLength + 4)
  $headerPickleLength = $headerPayloadLength + 4

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }

  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $writer = New-Object System.IO.BinaryWriter($stream)

  try {
    $writer.Write([int]4)
    $writer.Write([int]$headerPickleLength)
    $writer.Write([int]$headerPayloadLength)
    $writer.Write([int]$headerJsonLength)
    $writer.Write($headerBytes)

    $paddingLength = $headerPayloadLength - 4 - $headerJsonLength
    if ($paddingLength -gt 0) {
      $writer.Write((New-Object byte[] $paddingLength))
    }

    foreach ($payload in $FilePayloads) {
      $writer.Write([byte[]]$payload)
    }
  }
  finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Write-AsarArchiveFromMap {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Files,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $header = New-AsarHeaderFromFileMap -Files $Files
  $entries = Get-AsarFileEntries -FilesNode $header.files
  $payloads = @()
  $currentOffset = 0

  foreach ($entryInfo in $entries) {
    $value = $Files[$entryInfo.Path]
    $content =
      if ($value -is [byte[]]) {
        [byte[]]$value
      }
      else {
        [System.Text.Encoding]::UTF8.GetBytes([string]$value)
      }

    $entryInfo.Entry.size = $content.Length
    $entryInfo.Entry.offset = [string]$currentOffset
    $entryInfo.Entry.integrity = New-AsarIntegrity -Content $content
    $payloads += ,$content
    $currentOffset += $content.Length
  }

  Write-AsarArchive -Header $header -FilePayloads $payloads -Path $Path
}

function Find-UnescapedBacktickBackward {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [int]$StartIndex
  )

  for ($index = $StartIndex; $index -ge 0; $index--) {
    if ($Text[$index] -ne '`') {
      continue
    }

    $slashes = 0
    for ($probe = $index - 1; $probe -ge 0 -and $Text[$probe] -eq '\'; $probe--) {
      $slashes++
    }

    if (($slashes % 2) -eq 0) {
      return $index
    }
  }

  return -1
}

function Find-UnescapedBacktickForward {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [int]$StartIndex
  )

  for ($index = $StartIndex; $index -lt $Text.Length; $index++) {
    if ($Text[$index] -ne '`') {
      continue
    }

    $slashes = 0
    for ($probe = $index - 1; $probe -ge 0 -and $Text[$probe] -eq '\'; $probe--) {
      $slashes++
    }

    if (($slashes % 2) -eq 0) {
      return $index
    }
  }

  return -1
}

function New-PatchedAutomationTemplateSource {
  $template = @'
Response must follow the active automation prompt and applicable AGENTS instructions.

## Responding

- Answer the user normally and concisely. Explain what you found, what you did, and what matters now.
- For automations, treat the active automation prompt and applicable AGENTS files as the source of truth for memory handling, user-visible output, completion gates, and conflict reporting.
- Do not read or write `$CODEX_HOME/automations/<automation_id>/memory.md` unless those instructions explicitly require it.
- Return a remark directive only when the active automation prompt or applicable AGENTS requires user-visible output.
  - If output is required, emit a single valid directive on its own line.
  - If policy says the run should stay silent, do not force an inbox item.

## Guidelines

- Directives must be on their own line.
- Do not use invalid remark-directive formatting.
- Do not place commas between directive arguments.
- When referring to files, use full absolute filesystem links in Markdown (not relative paths).
- Try not to ask the user for more input if the answer can be inferred.
- If a PR is opened by the automation, add the `codex-automation` label when available alongside the normal `codex` label.
- When an inbox item is required, keep the copy glanceable and specific.
  - Title: short state + object.
  - Summary: what the user should do or know next.
'@

  $escaped = $template.TrimEnd().Replace('`', '\`')
  return ($escaped -replace "`r?`n", "\r`n") + "\r`n"
}

function Update-CodexAutomationDeveloperInstructions {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceText
  )

  $patchedAnchor = 'Return a remark directive only when the active automation prompt or applicable AGENTS requires user-visible output.'
  if ($SourceText.Contains($patchedAnchor)) {
    return [pscustomobject]@{
      Status = 'AlreadyPatched'
      Text   = $SourceText
    }
  }

  $legacyAnchor = 'Response MUST end with a remark-directive block.'
  $anchorIndex = $SourceText.IndexOf($legacyAnchor)
  if ($anchorIndex -lt 0) {
    throw 'The expected Codex automation developer-instruction template was not found. This Codex build likely needs a new patch rule.'
  }

  $openBacktick = Find-UnescapedBacktickBackward -Text $SourceText -StartIndex $anchorIndex
  if ($openBacktick -lt 0) {
    throw 'Could not locate the opening template literal for the Codex automation instruction block.'
  }

  $closeBacktick = Find-UnescapedBacktickForward -Text $SourceText -StartIndex ($anchorIndex + $legacyAnchor.Length)
  if ($closeBacktick -lt 0) {
    throw 'Could not locate the closing template literal for the Codex automation instruction block.'
  }

  $replacement = New-PatchedAutomationTemplateSource
  $suffix = $SourceText.Substring($closeBacktick)
  $paddingLength = $SourceText.Length - (($openBacktick + 1) + $replacement.Length + $suffix.Length)

  if ($paddingLength -lt 0) {
    $updatedText = $SourceText.Substring(0, $openBacktick + 1) + $replacement + $suffix
  }
  else {
    $updatedText = $SourceText.Substring(0, $openBacktick + 1) + $replacement + (' ' * $paddingLength) + $suffix
  }

  return [pscustomobject]@{
    Status          = 'Patched'
    Text            = $updatedText
    PreservedLength = ($paddingLength -ge 0)
  }
}

function Write-UpdatedAsarFromArchive {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Archive,

    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [Parameter(Mandatory = $true)]
    [byte[]]$ReplacementContent,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
  )

  $entries = Get-AsarFileEntries -FilesNode $Archive.Header.files
  $currentOffset = 0

  foreach ($entryInfo in $entries) {
    $contentLength =
      if ($entryInfo.Path -eq $TargetPath) {
        $ReplacementContent.Length
      }
      else {
        $entryInfo.OriginalSize
      }

    $entryInfo.Entry.size = $contentLength
    $entryInfo.Entry.offset = [string]$currentOffset

    if ((Test-HasProperty -InputObject $entryInfo.Entry -Name 'integrity') -and ($entryInfo.Path -eq $TargetPath)) {
      $entryInfo.Entry.integrity = New-AsarIntegrity -Content $ReplacementContent
    }

    $currentOffset += $contentLength
  }

  $headerJson = ConvertTo-Json -InputObject $Archive.Header -Compress -Depth 100
  $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerJson)
  $headerJsonLength = $headerBytes.Length
  $headerPayloadLength = Align-4 -Value ($headerJsonLength + 4)
  $headerPickleLength = $headerPayloadLength + 4
  $paddingLength = $headerPayloadLength - 4 - $headerJsonLength

  $directory = Split-Path -Parent $OutputPath
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }

  $stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $writer = New-Object System.IO.BinaryWriter($stream)

  try {
    $writer.Write([int]4)
    $writer.Write([int]$headerPickleLength)
    $writer.Write([int]$headerPayloadLength)
    $writer.Write([int]$headerJsonLength)
    $writer.Write($headerBytes)

    if ($paddingLength -gt 0) {
      $writer.Write((New-Object byte[] $paddingLength))
    }

    foreach ($entryInfo in $entries) {
      $content =
        if ($entryInfo.Path -eq $TargetPath) {
          $ReplacementContent
        }
        else {
          Get-ByteSlice -Bytes $Archive.Bytes -Offset ($Archive.DataOffset + $entryInfo.OriginalOffset) -Length $entryInfo.OriginalSize
        }

      if ($content.Length -gt 0) {
        $writer.Write([byte[]]$content)
      }
    }
  }
  finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Write-CodexPatchedAsar {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InputAsarPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputAsarPath
  )

  $archive = Read-AsarArchive -Path $InputAsarPath
  $entries = Get-AsarFileEntries -FilesNode $archive.Header.files
  $targetEntry = $null
  $targetText = $null

  foreach ($entryInfo in $entries | Where-Object { $_.Path -like '.vite/build/main-*.js' }) {
    $contentBytes = Get-ByteSlice -Bytes $archive.Bytes -Offset ($archive.DataOffset + [int]$entryInfo.Entry.offset) -Length ([int]$entryInfo.Entry.size)
    $candidateText = [System.Text.Encoding]::UTF8.GetString($contentBytes)

    if ($candidateText.Contains('Response MUST end with a remark-directive block.') -or $candidateText.Contains('Return a remark directive only when the active automation prompt or applicable AGENTS requires user-visible output.')) {
      $targetEntry = $entryInfo
      $targetText = $candidateText
      break
    }
  }

  if ($null -eq $targetEntry) {
    throw 'Could not find the Codex main bundle containing the automation developer-instruction template.'
  }

  $patchResult = Update-CodexAutomationDeveloperInstructions -SourceText $targetText

  if ($patchResult.Status -eq 'AlreadyPatched') {
    if ([System.IO.Path]::GetFullPath($InputAsarPath) -ne [System.IO.Path]::GetFullPath($OutputAsarPath)) {
      Copy-Item -LiteralPath $InputAsarPath -Destination $OutputAsarPath -Force
    }

    return [pscustomobject]@{
      Status         = 'AlreadyPatched'
      BundlePath     = $targetEntry.Path
      InputAsarPath  = $InputAsarPath
      OutputAsarPath = $OutputAsarPath
    }
  }

  $replacementBytes = [System.Text.Encoding]::UTF8.GetBytes($patchResult.Text)
  $fastPathUsed = $false

  if ($replacementBytes.Length -eq $targetEntry.OriginalSize) {
    $targetEntry.Entry.integrity = New-AsarIntegrity -Content $replacementBytes
    $updatedHeaderJson = ConvertTo-Json -InputObject $archive.Header -Compress -Depth 100
    $updatedHeaderBytes = [System.Text.Encoding]::UTF8.GetBytes($updatedHeaderJson)

    if ($updatedHeaderBytes.Length -eq $archive.HeaderJsonLength) {
      $updatedArchiveBytes = New-Object byte[] $archive.Bytes.Length
      [Buffer]::BlockCopy($archive.Bytes, 0, $updatedArchiveBytes, 0, $archive.Bytes.Length)
      [Buffer]::BlockCopy($updatedHeaderBytes, 0, $updatedArchiveBytes, 16, $updatedHeaderBytes.Length)
      [Buffer]::BlockCopy($replacementBytes, 0, $updatedArchiveBytes, ($archive.DataOffset + $targetEntry.OriginalOffset), $replacementBytes.Length)
      [System.IO.File]::WriteAllBytes($OutputAsarPath, $updatedArchiveBytes)
      $fastPathUsed = $true
    }
  }

  if (-not $fastPathUsed) {
    Write-UpdatedAsarFromArchive -Archive $archive -TargetPath $targetEntry.Path -ReplacementContent $replacementBytes -OutputPath $OutputAsarPath
  }

  return [pscustomobject]@{
    Status         = 'Patched'
    BundlePath     = $targetEntry.Path
    InputAsarPath  = $InputAsarPath
    OutputAsarPath = $OutputAsarPath
    FastPathUsed   = $fastPathUsed
  }
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CodexInstallRoot {
  param(
    [string]$WindowsAppsPath = (Join-Path $env:ProgramFiles 'WindowsApps')
  )

  try {
    $roots = Get-ChildItem -LiteralPath $WindowsAppsPath -Directory -Filter 'OpenAI.Codex_*' -ErrorAction Stop | Sort-Object Name -Descending
  }
  catch {
    throw "Unable to enumerate '$WindowsAppsPath'. Run the patcher from an elevated PowerShell session."
  }

  if (-not $roots) {
    throw "No OpenAI.Codex package was found under '$WindowsAppsPath'."
  }

  return $roots[0].FullName
}

function Get-CodexAppAsarPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  $path = Join-Path $InstallRoot 'app\resources\app.asar'
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Codex app.asar was not found at '$path'."
  }

  return $path
}

function Backup-CodexAppAsar {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AsarPath,

    [string]$BackupDirectory = (Join-Path $env:USERPROFILE '.codex\backups')
  )

  if (-not (Test-Path -LiteralPath $BackupDirectory)) {
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
  }

  $installRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $AsarPath))
  $packageName = Split-Path -Leaf $installRoot
  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupPath = Join-Path $BackupDirectory ("{0}.app.asar.{1}.bak" -f $packageName, $timestamp)

  Copy-Item -LiteralPath $AsarPath -Destination $backupPath -Force
  return $backupPath
}

function Restore-CodexAppAsar {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AsarPath,

    [string]$BackupPath,

    [string]$BackupDirectory = (Join-Path $env:USERPROFILE '.codex\backups')
  )

  if (-not $BackupPath) {
    $backupPath = Get-ChildItem -LiteralPath $BackupDirectory -Filter '*.bak' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }
  }

  if (-not $backupPath) {
    throw "No backup file was found in '$BackupDirectory'."
  }

  Copy-Item -LiteralPath $backupPath -Destination $AsarPath -Force
  return $backupPath
}

function Register-CodexAutopatchTask {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PatchScriptPath,

    [string]$TaskName = 'Codex Desktop Autopatch'
  )

  if (-not (Test-IsAdministrator)) {
    throw 'Register-CodexAutopatchTask must be run from an elevated PowerShell session.'
  }

  $patchScriptFullPath = [System.IO.Path]::GetFullPath($PatchScriptPath)
  $argument = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -StopCodex' -f $patchScriptFullPath
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

  $dailyTrigger = New-ScheduledTaskTrigger -Daily -At 12:00AM -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)
  $triggers = @(
    (New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -AtLogOn),
    $dailyTrigger
  )

  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType InteractiveToken -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
  return $TaskName
}

function Unregister-CodexAutopatchTask {
  param(
    [string]$TaskName = 'Codex Desktop Autopatch'
  )

  if (-not (Test-IsAdministrator)) {
    throw 'Unregister-CodexAutopatchTask must be run from an elevated PowerShell session.'
  }

  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Export-ModuleMember -Function @(
  'Backup-CodexAppAsar',
  'Get-AsarFileContent',
  'Get-CodexAppAsarPath',
  'Get-CodexInstallRoot',
  'Read-AsarArchive',
  'Register-CodexAutopatchTask',
  'Restore-CodexAppAsar',
  'Unregister-CodexAutopatchTask',
  'Write-AsarArchiveFromMap',
  'Write-CodexPatchedAsar'
)
