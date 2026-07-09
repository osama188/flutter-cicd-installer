function New-InstallConfig {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [Parameter(Mandatory)][string]$PackageName,
    [Parameter(Mandatory)][string]$FlutterVersion,
    [Parameter(Mandatory)][string]$GitHubEnvironment,
    [Parameter(Mandatory)][string]$PlayStoreTrack,
    [Parameter(Mandatory)][string]$GitHubRepo,
    [ValidateSet('Android', 'iOS', 'Both')]
    [string]$Platform = 'Both',
    [string[]]$DartDefineKeys = @(),
    [string]$BundleId = '',
    [string]$MatchGitUrl = '',
    [string]$KeystorePath = '',
    [string]$KeyAlias = '',
    [string]$KeyPassword = '',
    [string]$StorePassword = '',
    [string]$ServiceAccountJsonPath = '',
    [string]$AscKeyId = '',
    [string]$AscIssuerId = '',
    [string]$AscKeyPath = '',
    [string]$MatchPassword = '',
    [string]$MatchGitUsername = '',
    [string]$MatchGitPat = '',
    [bool]$InHouse = $false,
    [hashtable]$DartDefineValues = @{}
  )

  [PSCustomObject]@{
    TargetPath             = (Resolve-Path $TargetPath).Path
    PackageName            = $PackageName
    BundleId               = $(if ($BundleId) { $BundleId } else { $PackageName })
    FlutterVersion         = $FlutterVersion
    GitHubEnvironment      = $GitHubEnvironment
    PlayStoreTrack         = $PlayStoreTrack
    GitHubRepo             = $GitHubRepo
    Platform               = $Platform
    DartDefineKeys         = @($DartDefineKeys)
    MatchGitUrl            = $MatchGitUrl
    KeystorePath           = $KeystorePath
    KeyAlias               = $KeyAlias
    KeyPassword            = $KeyPassword
    StorePassword          = $StorePassword
    ServiceAccountJsonPath = $ServiceAccountJsonPath
    AscKeyId               = $AscKeyId
    AscIssuerId            = $AscIssuerId
    AscKeyPath             = $AscKeyPath
    MatchPassword          = $MatchPassword
    MatchGitUsername       = $MatchGitUsername
    MatchGitPat            = $MatchGitPat
    InHouse                = $InHouse
    DartDefineValues       = $DartDefineValues
  }
}

function Get-DartDefinesWorkflowBlocks {
  param([string[]]$Keys)

  if ($Keys.Count -eq 0) {
    return @{
      DartDefinesStep  = ''
      TestCommand      = 'flutter test'
      BuildDefineFlags = ''
    }
  }

  $envBlock = ($Keys | ForEach-Object {
    "          $_`: `${{ secrets.$_ }}"
  }) -join "`n"

  $argLines = [System.Collections.Generic.List[string]]::new()
  $jsonPairs = [System.Collections.Generic.List[string]]::new()
  foreach ($key in $Keys) {
    $argLines.Add("            --arg $key ""`${$key}"" \")
    $jsonPairs.Add(('{0}: {1}' -f $key, ('$' + $key)))
  }

  $jsonFilter = "'{$($jsonPairs -join ', ')}' \"

  $dartStep = @(
    '      - name: Create dart_defines.json'
    '        env:'
    $envBlock
    '        run: |'
    '          jq -n \'
    $argLines
    "            $jsonFilter"
    '            > dart_defines.json'
  ) -join "`n"

  return @{
    DartDefinesStep  = $dartStep
    TestCommand      = 'flutter test --dart-define-from-file=dart_defines.json'
    BuildDefineFlags = " \`n            --dart-define-from-file=dart_defines.json"
  }
}

function Get-IosDartDefinesWorkflowBlocks {
  param([string[]]$Keys)

  if ($Keys.Count -eq 0) {
    return @{
      DartDefinesStep = ''
    }
  }

  $dart = Get-DartDefinesWorkflowBlocks -Keys $Keys
  $validationLines = ($Keys | ForEach-Object {
    '          if [ -z "${{{0}:-}}" ]; then echo "Secret {0} is empty"; exit 1; fi' -f $_
  }) -join "`n"

  $dartStep = $dart.DartDefinesStep -replace (
    '(        run: \|)\r?\n'
  ), "`$1`n          set -euo pipefail`n$validationLines`n"

  return @{
    DartDefinesStep = $dartStep
  }
}
