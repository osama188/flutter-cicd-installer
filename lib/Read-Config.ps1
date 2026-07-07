function ConvertTo-PlainSecureString {
  param([Security.SecureString]$Secure)
  if (-not $Secure) { return '' }
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Read-InstallConfig {
  param(
    [Parameter(Mandatory)]$TargetInfo,
    [string]$ConfigFile,
    [switch]$SkipSecrets,
    [switch]$UseDefaults
  )

  if ($UseDefaults) {
    return New-InstallConfig `
      -TargetPath $TargetInfo.TargetPath `
      -PackageName $TargetInfo.PackageName `
      -FlutterVersion $TargetInfo.FlutterHint `
      -GitHubEnvironment 'production' `
      -PlayStoreTrack 'internal' `
      -GitHubRepo $TargetInfo.GitHubRepo `
      -DartDefineKeys @('SUPABASE_URL', 'SUPABASE_ANON_KEY')
  }

  if ($ConfigFile) {
    $json = Get-Content -Raw $ConfigFile | ConvertFrom-Json
    $keys = @($json.dartDefineKeys)
    $dartValues = @{}
    if ($json.dartDefineValues) {
      $json.dartDefineValues.PSObject.Properties | ForEach-Object {
        $dartValues[$_.Name] = [string]$_.Value
      }
    }
    return New-InstallConfig `
      -TargetPath $TargetInfo.TargetPath `
      -PackageName ($(if ($json.packageName) { $json.packageName } else { $TargetInfo.PackageName })) `
      -FlutterVersion $json.flutterVersion `
      -GitHubEnvironment $json.githubEnvironment `
      -PlayStoreTrack $json.playStoreTrack `
      -GitHubRepo ($(if ($json.githubRepo) { $json.githubRepo } else { $TargetInfo.GitHubRepo })) `
      -DartDefineKeys $keys `
      -KeystorePath ([string]$json.keystorePath) `
      -KeyAlias ([string]$json.keyAlias) `
      -KeyPassword ([string]$json.keyPassword) `
      -StorePassword ([string]$json.storePassword) `
      -ServiceAccountJsonPath ([string]$json.serviceAccountJsonPath) `
      -DartDefineValues $dartValues
  }

  $packageName = Read-Host "Package name [$($TargetInfo.PackageName)]"
  if ([string]::IsNullOrWhiteSpace($packageName)) { $packageName = $TargetInfo.PackageName }

  $flutterVer = Read-Host "Flutter version [$($TargetInfo.FlutterHint)]"
  if ([string]::IsNullOrWhiteSpace($flutterVer)) { $flutterVer = $TargetInfo.FlutterHint }

  $ghEnv = Read-Host 'GitHub environment [production]'
  if ([string]::IsNullOrWhiteSpace($ghEnv)) { $ghEnv = 'production' }

  $track = Read-Host 'Play Store track [internal]'
  if ([string]::IsNullOrWhiteSpace($track)) { $track = 'internal' }

  $keysInput = Read-Host 'Dart-define keys (comma-separated; - for none) [SUPABASE_URL,SUPABASE_ANON_KEY]'
  if ([string]::IsNullOrWhiteSpace($keysInput)) {
    $keys = @('SUPABASE_URL', 'SUPABASE_ANON_KEY')
  } elseif ($keysInput.Trim() -eq '-') {
    $keys = @()
  } else {
    $keys = $keysInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }

  $keystore = ''
  $saJson = ''
  $alias = ''
  $keyPassPlain = ''
  $storePassPlain = ''
  $dartValues = @{}

  if (-not $SkipSecrets) {
    $keystore = Read-Host 'Keystore path (.jks)'
    $saJson = Read-Host 'Service account JSON path'
    $alias = Read-Host 'Key alias'
    $keyPassPlain = ConvertTo-PlainSecureString -Secure (Read-Host 'Key password' -AsSecureString)
    $storePassPlain = ConvertTo-PlainSecureString -Secure (Read-Host 'Store password' -AsSecureString)
    foreach ($k in $keys) {
      $dartValues[$k] = ConvertTo-PlainSecureString -Secure (
        Read-Host "Value for secret $k" -AsSecureString)
    }
  }

  New-InstallConfig `
    -TargetPath $TargetInfo.TargetPath `
    -PackageName $packageName `
    -FlutterVersion $flutterVer `
    -GitHubEnvironment $ghEnv `
    -PlayStoreTrack $track `
    -GitHubRepo $TargetInfo.GitHubRepo `
    -DartDefineKeys $keys `
    -KeystorePath $keystore `
    -KeyAlias $alias `
    -KeyPassword $keyPassPlain `
    -StorePassword $storePassPlain `
    -ServiceAccountJsonPath $saJson `
    -DartDefineValues $dartValues
}
