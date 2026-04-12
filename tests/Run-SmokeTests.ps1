Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'src\CodexDesktopPatcher.psd1') -Force

function Assert-True {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Convert-ToLegacyTemplateLiteralSource {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text
  )

  $escaped = $Text.TrimEnd().Replace('`', '\`')
  return ($escaped -replace "`r?`n", "\r`n") + "\r`n"
}

$tempRoot = Join-Path $env:TEMP ('codex-silent-threads-patch-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
  $fixturePath = Join-Path $tempRoot 'fixture.asar'
  $patchedPath = Join-Path $tempRoot 'patched.asar'
  $patchedAgainPath = Join-Path $tempRoot 'patched-again.asar'

  $legacyTemplate = @'
Response MUST end with a remark-directive block.

## Responding

- Answer the user normally and concisely. Explain what you found, what you did, and what the user should focus on now.
- Automations: use the memory file at `$CODEX_HOME/automations/<automation_id>/memory.md` (create it if missing).
  - Read it first (if present) to avoid repeating recent work, especially for "changes since last run" tasks.
  - Memory is important: some tasks must build on prior work, and others must avoid duplicating prior focus.
  - Before returning the directive, write a concise summary of what you did/decided plus the current run time.
  - Use the `Automation ID:` value provided in the message to locate/update this file.
- REQUIRED: End with a valid remark-directive block on its own line (not inline).
  - Always include an inbox item directive:
    `::inbox-item{title="Sample title" summary="Place description here"}`

## Choosing return value

- For recurring/bg threads (e.g., "pull datadog logs and fix any new bugs", "address the PR comments"):
  - Always return `::inbox-item{...}` with the title/summary the user should see.

## Guidelines

- Directives MUST be on their own line.
- Output exactly ONE inbox-item directive.
'@

  $mainSource = 'var ie=`' + (Convert-ToLegacyTemplateLiteralSource -Text $legacyTemplate) + '`;const afterTemplate=42;'
  $appContextSource = @'
const automationGuidance = `- When helpful, include clear output expectations.
- Automations should always open an inbox item.
- Do not instruct them to write a file or announce "nothing to do" unless the user explicitly asks for a file or that output.`;
'@

  Write-AsarArchiveFromMap -Files @{
    '.vite/build/main-test.js'         = $mainSource
    '.vite/build/product-name-test.js' = $appContextSource
    '.vite/build/worker.js'            = $appContextSource
    'webview/index.html'               = '<html><body>ok</body></html>'
  } -Path $fixturePath

  $patchResult = Write-CodexPatchedAsar -InputAsarPath $fixturePath -OutputAsarPath $patchedPath
  Assert-True -Condition ($patchResult.Status -eq 'Patched') -Message 'Expected the fixture archive to be patched.'

  $patchedArchive = Read-AsarArchive -Path $patchedPath
  $patchedMain = [System.Text.Encoding]::UTF8.GetString((Get-AsarFileContent -Archive $patchedArchive -Path '.vite/build/main-test.js'))
  $patchedProduct = [System.Text.Encoding]::UTF8.GetString((Get-AsarFileContent -Archive $patchedArchive -Path '.vite/build/product-name-test.js'))
  $patchedWorker = [System.Text.Encoding]::UTF8.GetString((Get-AsarFileContent -Archive $patchedArchive -Path '.vite/build/worker.js'))
  $patchedHtml = [System.Text.Encoding]::UTF8.GetString((Get-AsarFileContent -Archive $patchedArchive -Path 'webview/index.html'))

  Assert-True -Condition ($patchedMain.Contains('Return a remark directive only when the active automation prompt or applicable AGENTS requires user-visible output.')) -Message 'The patched template anchor was not found.'
  Assert-True -Condition (-not $patchedMain.Contains('Output exactly ONE inbox-item directive.')) -Message 'The forced inbox directive text was not removed.'
  Assert-True -Condition (-not $patchedMain.Contains('use the memory file at `$CODEX_HOME/automations/<automation_id>/memory.md`')) -Message 'The forced memory instruction was not removed.'
  Assert-True -Condition ($patchedProduct.Contains('Follow prompt/AGENTS for user-visible output.')) -Message 'The product bundle automation app-context guidance was not patched.'
  Assert-True -Condition ($patchedWorker.Contains('Follow prompt/AGENTS for user-visible output.')) -Message 'The worker bundle automation app-context guidance was not patched.'
  Assert-True -Condition (-not $patchedProduct.Contains('Automations should always open an inbox item.')) -Message 'The product bundle still forces an inbox item.'
  Assert-True -Condition (-not $patchedWorker.Contains('Automations should always open an inbox item.')) -Message 'The worker bundle still forces an inbox item.'
  Assert-True -Condition ($patchedHtml -eq '<html><body>ok</body></html>') -Message ("Unrelated archive contents changed unexpectedly. Actual: [{0}]" -f $patchedHtml)

  $secondResult = Write-CodexPatchedAsar -InputAsarPath $patchedPath -OutputAsarPath $patchedAgainPath
  Assert-True -Condition ($secondResult.Status -eq 'AlreadyPatched') -Message 'Expected a second patch pass to be idempotent.'

  Write-Output 'Smoke tests passed.'
}
finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
