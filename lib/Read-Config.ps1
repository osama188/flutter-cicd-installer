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
    [ValidateSet('Android', 'iOS', 'Both')]
    [string]$Platform = 'Both',
    [switch]$SkipSecrets,
    [switch]$UseDefaults
  )

  if ($UseDefaults) {
    return New-InstallConfig `
      -TargetPath $TargetInfo.TargetPath `
      -PackageName $TargetInfo.PackageName `
      -BundleId $TargetInfo.BundleId `
      -FlutterVersion $TargetInfo.FlutterHint `
      -GitHubEnvironment 'production' `
      -PlayStoreTrack 'internal' `
      -GitHubRepo $TargetInfo.GitHubRepo `
      -Platform $Platform `
      -MatchGitUrl 'https://github.com/owner/ios-certificates.git' `
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
    $cfgPlatform = if ($json.platform) { $json.platform } else { $Platform }
    $android = $json.android
    $ios = $json.ios
    return New-InstallConfig `
      -TargetPath $TargetInfo.TargetPath `
      -PackageName ($(if ($json.packageName) { $json.packageName } else { $TargetInfo.PackageName })) `
      -BundleId ($(if ($json.bundleId) { $json.bundleId } else { $TargetInfo.BundleId })) `
      -FlutterVersion $json.flutterVersion `
      -GitHubEnvironment $json.githubEnvironment `
      -PlayStoreTrack $json.playStoreTrack `
      -GitHubRepo ($(if ($json.githubRepo) { $json.githubRepo } else { $TargetInfo.GitHubRepo })) `
      -Platform $cfgPlatform `
      -MatchGitUrl ([string]$json.matchGitUrl) `
      -DartDefineKeys $keys `
      -KeystorePath ([string]$android.keystorePath) `
      -KeyAlias ([string]$android.keyAlias) `
      -KeyPassword ([string]$android.keyPassword) `
      -StorePassword ([string]$android.storePassword) `
      -ServiceAccountJsonPath ([string]$android.serviceAccountJsonPath) `
      -AscKeyId ([string]$ios.ascKeyId) `
      -AscIssuerId ([string]$ios.ascIssuerId) `
      -AscKeyPath ([string]$ios.ascKeyPath) `
      -MatchPassword ([string]$ios.matchPassword) `
      -MatchGitUsername ([string]$ios.matchGitUsername) `
      -MatchGitPat ([string]$ios.matchGitPat) `
      -DartDefineValues $dartValues
  }

  $cfgPlatform = $Platform
  $platformInput = Read-Host "Platform [Both] (Android/iOS/Both)"
  if (-not [string]::IsNullOrWhiteSpace($platformInput)) { $cfgPlatform = $platformInput }

  $packageName = Read-Host "Package name [$($TargetInfo.PackageName)]"
  if ([string]::IsNullOrWhiteSpace($packageName)) { $packageName = $TargetInfo.PackageName }

  $bundleId = Read-Host "Bundle ID [$($TargetInfo.BundleId)]"
  if ([string]::IsNullOrWhiteSpace($bundleId)) { $bundleId = $TargetInfo.BundleId }

  $flutterVer = Read-Host "Flutter version [$($TargetInfo.FlutterHint)]"
  if ([string]::IsNullOrWhiteSpace($flutterVer)) { $flutterVer = $TargetInfo.FlutterHint }

  $ghEnv = Read-Host 'GitHub environment [production]'
  if ([string]::IsNullOrWhiteSpace($ghEnv)) { $ghEnv = 'production' }

  $track = Read-Host 'Play Store track [internal]'
  if ([string]::IsNullOrWhiteSpace($track)) { $track = 'internal' }

  $matchUrl = ''
  if ($cfgPlatform -in 'iOS', 'Both') {
    $matchUrl = Read-Host 'Match certs repo URL (https://github.com/owner/ios-certificates.git)'
  }

  $keysInput = Read-Host 'Dart-define keys (comma-separated; - for none) [SUPABASE_URL,SUPABASE_ANON_KEY]'
  if ([string]::IsNullOrWhiteSpace($keysInput)) {
    $keys = @('SUPABASE_URL', 'SUPABASE_ANON_KEY')
  } elseif ($keysInput.Trim() -eq '-') {
    $keys = @()
  } else {
    $keys = $keysInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }

  $keystore = ''; $saJson = ''; $alias = ''; $keyPassPlain = ''; $storePassPlain = ''
  $ascKeyId = ''; $ascIssuerId = ''; $ascKeyPath = ''
  $matchPassword = ''; $matchGitUser = ''; $matchGitPat = ''
  $dartValues = @{}

  if (-not $SkipSecrets) {
    if ($cfgPlatform -in 'Android', 'Both') {
      $keystore = Read-Host 'Keystore path (.jks)'
      $saJson = Read-Host 'Service account JSON path'
      $alias = Read-Host 'Key alias'
      $keyPassPlain = ConvertTo-PlainSecureString -Secure (Read-Host 'Key password' -AsSecureString)
      $storePassPlain = ConvertTo-PlainSecureString -Secure (Read-Host 'Store password' -AsSecureString)
    }
    if ($cfgPlatform -in 'iOS', 'Both') {
      $ascKeyId = Read-Host 'ASC Key ID'
      $ascIssuerId = Read-Host 'ASC Issuer ID'
      $ascKeyPath = Read-Host 'ASC .p8 file path'
      $matchPassword = ConvertTo-PlainSecureString -Secure (Read-Host 'Match password' -AsSecureString)
      $matchGitUser = Read-Host 'GitHub username for Match repo'
      $matchGitPat = ConvertTo-PlainSecureString -Secure (Read-Host 'GitHub PAT for Match repo' -AsSecureString)
    }
    foreach ($k in $keys) {
      $dartValues[$k] = ConvertTo-PlainSecureString -Secure (
        Read-Host "Value for secret $k" -AsSecureString)
    }
  }

  New-InstallConfig `
    -TargetPath $TargetInfo.TargetPath `
    -PackageName $packageName `
    -BundleId $bundleId `
    -FlutterVersion $flutterVer `
    -GitHubEnvironment $ghEnv `
    -PlayStoreTrack $track `
    -GitHubRepo $TargetInfo.GitHubRepo `
    -Platform $cfgPlatform `
    -MatchGitUrl $matchUrl `
    -DartDefineKeys $keys `
    -KeystorePath $keystore `
    -KeyAlias $alias `
    -KeyPassword $keyPassPlain `
    -StorePassword $storePassPlain `
    -ServiceAccountJsonPath $saJson `
    -AscKeyId $ascKeyId `
    -AscIssuerId $ascIssuerId `
    -AscKeyPath $ascKeyPath `
    -MatchPassword $matchPassword `
    -MatchGitUsername $matchGitUser `
    -MatchGitPat $matchGitPat `
    -DartDefineValues $dartValues
}
