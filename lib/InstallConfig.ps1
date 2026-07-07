function New-InstallConfig {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [Parameter(Mandatory)][string]$PackageName,
    [Parameter(Mandatory)][string]$FlutterVersion,
    [Parameter(Mandatory)][string]$GitHubEnvironment,
    [Parameter(Mandatory)][string]$PlayStoreTrack,
    [Parameter(Mandatory)][string]$GitHubRepo,
    [string[]]$DartDefineKeys = @(),
    [string]$KeystorePath = '',
    [string]$KeyAlias = '',
    [string]$KeyPassword = '',
    [string]$StorePassword = '',
    [string]$ServiceAccountJsonPath = '',
    [hashtable]$DartDefineValues = @{}
  )

  [PSCustomObject]@{
    TargetPath             = (Resolve-Path $TargetPath).Path
    PackageName            = $PackageName
    FlutterVersion         = $FlutterVersion
    GitHubEnvironment      = $GitHubEnvironment
    PlayStoreTrack         = $PlayStoreTrack
    GitHubRepo             = $GitHubRepo
    DartDefineKeys         = @($DartDefineKeys)
    KeystorePath           = $KeystorePath
    KeyAlias               = $KeyAlias
    KeyPassword            = $KeyPassword
    StorePassword          = $StorePassword
    ServiceAccountJsonPath = $ServiceAccountJsonPath
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
    '          {0}: ${{ secrets.{0} }}' -f $_
  }) -join "`n"

  $argLines = [System.Collections.Generic.List[string]]::new()
  $jsonPairs = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $Keys.Count; $i++) {
    $key = $Keys[$i]
    $var = "v$i"
    $suffix = if ($i -lt $Keys.Count - 1) { ' \' } else { '' }
    $argLines.Add(('            --arg {0} "${{{1}}}"{2}' -f $var, $key, $suffix))
    $jsonPairs.Add(('{0}: ${1}' -f $key, "`$$var"))
  }

  $dartStep = @"
      - name: Create dart_defines.json
        env:
$envBlock
        run: |
          jq -n \
$($argLines -join "`n")
            '{$($jsonPairs -join ', ')}' \
            > dart_defines.json
"@

  return @{
    DartDefinesStep  = $dartStep
    TestCommand      = 'flutter test --dart-define-from-file=dart_defines.json'
    BuildDefineFlags = "`n            --dart-define-from-file=dart_defines.json"
  }
}
