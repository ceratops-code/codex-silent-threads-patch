[CmdletBinding()]
param(
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\psscriptanalyzer.sarif')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$resolvedOutputPath =
  if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
  }
  else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
  }

Import-Module PSScriptAnalyzer -ErrorAction Stop

$module = Get-Module -Name PSScriptAnalyzer | Select-Object -First 1
$files = @(
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter *.ps1 -File
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Filter *.psm1 -File
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Filter *.psd1 -File
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter *.ps1 -File
)

$findings = @(
  foreach ($file in $files) {
    Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settingsPath
  }
)

$rules = @(
  foreach ($ruleName in @($findings | ForEach-Object { $_.RuleName } | Sort-Object -Unique)) {
    [ordered]@{
      id               = $ruleName
      shortDescription = @{
        text = $ruleName
      }
    }
  }
)

$results = @(
  foreach ($finding in $findings) {
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $finding.ScriptPath).Replace('\', '/')
    $level =
      switch ([string]$finding.Severity) {
        'Error' { 'error' }
        'Warning' { 'warning' }
        default { 'note' }
      }

    $region = [ordered]@{
      startLine = [int]$finding.Line
    }

    if ($finding.PSObject.Properties['Column'] -and $finding.Column) {
      $region.startColumn = [int]$finding.Column
    }

    [ordered]@{
      ruleId   = $finding.RuleName
      level    = $level
      message  = @{
        text = $finding.Message
      }
      locations = @(
        @{
          physicalLocation = @{
            artifactLocation = @{
              uri       = $relativePath
              uriBaseId = '%SRCROOT%'
            }
            region = $region
          }
        }
      )
    }
  }
)

$sarif = [ordered]@{
  version = '2.1.0'
  '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
  runs = @(
    [ordered]@{
      tool = @{
        driver = @{
          name            = 'PSScriptAnalyzer'
          informationUri  = 'https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview'
          semanticVersion = [string]$module.Version
          rules           = $rules
        }
      }
      originalUriBaseIds = @{
        '%SRCROOT%' = @{
          uri = ('file:///{0}/' -f ($repoRoot.Replace('\', '/').TrimStart('/')))
        }
      }
      results = $results
    }
  )
}

$outputDirectory = Split-Path -Parent $resolvedOutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

[System.IO.File]::WriteAllText(
  $resolvedOutputPath,
  ($sarif | ConvertTo-Json -Depth 100),
  (New-Object System.Text.UTF8Encoding($false))
)
Write-Output $resolvedOutputPath
