Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

Import-Module PSScriptAnalyzer -ErrorAction Stop

$files = @(
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter *.ps1 -File
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Filter *.psm1 -File
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Filter *.psd1 -File
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter *.ps1 -File
)

$results = foreach ($file in $files) {
  Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settingsPath
}

if ($results) {
  $results |
    Sort-Object Severity, ScriptName, Line, RuleName |
    Select-Object RuleName, Severity, ScriptName, Line, Message |
    Format-Table -AutoSize
  throw 'PSScriptAnalyzer found issues.'
}

Write-Output 'Lint passed.'
