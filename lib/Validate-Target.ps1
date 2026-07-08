function Get-ApplicationIdFromGradle {
  param([string]$BuildGradlePath)
  $content = Get-Content -Raw $BuildGradlePath
  if ($content -match 'applicationId\s+"([^"]+)"') { return $Matches[1] }
  if ($content -match 'applicationId\s*=\s*"([^"]+)"') { return $Matches[1] }
  throw "Could not read applicationId from $BuildGradlePath"
}

function Get-BundleIdFromPbxproj {
  param([string]$PbxprojPath)
  $matches = Select-String -Path $PbxprojPath -Pattern 'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);' -AllMatches
  foreach ($m in $matches.Matches) {
    $id = $m.Groups[1].Value.Trim()
    if ($id -notmatch 'RunnerTests' -and $id -ne '$(PRODUCT_BUNDLE_IDENTIFIER)') {
      return $id
    }
  }
  throw "Could not read PRODUCT_BUNDLE_IDENTIFIER from $PbxprojPath"
}

function Test-IosReleaseManualSigning {
  param([string]$PbxprojPath)
  $content = Get-Content -Raw $PbxprojPath
  return $content -match 'CODE_SIGN_STYLE = Manual'
}

function Get-GitHubRepoFromRemote {
  param([string]$TargetPath)
  Push-Location $TargetPath
  try {
    $url = git remote get-url origin 2>$null
    if (-not $url) { throw 'No git remote origin' }
    if ($url -match 'github\.com[:/](.+?)(?:\.git)?$') {
      return $Matches[1]
    }
    throw "Remote is not GitHub: $url"
  } finally { Pop-Location }
}

function Test-PlaceholderGitHubRepo {
  param([string]$Repo)
  if ([string]::IsNullOrWhiteSpace($Repo)) { return $true }
  return $Repo -eq 'owner/repo'
}

function Resolve-GitHubRepo {
  param(
    [string]$ConfigRepo,
    [Parameter(Mandatory)][string]$DetectedRepo
  )
  if (Test-PlaceholderGitHubRepo -Repo $ConfigRepo) {
    if ($ConfigRepo) {
      Write-Warning "githubRepo is placeholder '$ConfigRepo'; using git remote: $DetectedRepo"
    }
    return $DetectedRepo
  }
  return $ConfigRepo
}

function Test-GhAuthenticated {
  gh auth status 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'gh CLI not authenticated. Run: gh auth login'
  }
}

function Validate-InstallTarget {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [ValidateSet('Android', 'iOS', 'Both')]
    [string]$Platform = 'Both'
  )

  $resolved = Resolve-Path $TargetPath -ErrorAction Stop
  $pubspec = Join-Path $resolved 'pubspec.yaml'
  if (-not (Test-Path $pubspec)) { throw 'Not a Flutter project: pubspec.yaml missing' }

  Test-GhAuthenticated
  $githubRepo = Get-GitHubRepoFromRemote -TargetPath $resolved

  $flutterHint = '3.41.5'
  $pubContent = Get-Content -Raw $pubspec
  if ($pubContent -match 'flutter:\s*">=([0-9.]+)"') {
    $flutterHint = $Matches[1]
  }

  $packageName = ''
  $bundleId = ''
  $warnSigning = $false
  $warnIosSigning = $false
  $warnIosFastlane = $false

  if ($Platform -in 'Android', 'Both') {
    $android = Join-Path $resolved 'android'
    $gradle = Join-Path $resolved 'android/app/build.gradle'
    $gradleKts = Join-Path $resolved 'android/app/build.gradle.kts'
    if (-not (Test-Path $android)) { throw 'android/ directory missing' }
    if (-not (Test-Path $gradle) -and -not (Test-Path $gradleKts)) {
      throw 'android/app/build.gradle or build.gradle.kts missing'
    }
    $gradlePath = if (Test-Path $gradle) { $gradle } else { $gradleKts }
    $packageName = Get-ApplicationIdFromGradle -BuildGradlePath $gradlePath
    $warnSigning = -not (Select-String -Path $gradlePath -Pattern 'signingConfigs' -Quiet)
  }

  if ($Platform -in 'iOS', 'Both') {
    $ios = Join-Path $resolved 'ios'
    $pbxproj = Join-Path $resolved 'ios/Runner.xcodeproj/project.pbxproj'
    if (-not (Test-Path $ios)) { throw 'ios/ directory missing' }
    if (-not (Test-Path $pbxproj)) { throw 'ios/Runner.xcodeproj/project.pbxproj missing' }
    $bundleId = Get-BundleIdFromPbxproj -PbxprojPath $pbxproj
    if (-not $packageName) { $packageName = $bundleId }
    $warnIosSigning = -not (Test-IosReleaseManualSigning -PbxprojPath $pbxproj)
    $warnIosFastlane = -not (Test-Path (Join-Path $resolved 'ios/fastlane/Fastfile'))
  }

  if (-not $packageName -and $bundleId) { $packageName = $bundleId }

  [PSCustomObject]@{
    TargetPath      = $resolved.Path
    PackageName     = $packageName
    BundleId        = $(if ($bundleId) { $bundleId } else { $packageName })
    GitHubRepo      = $githubRepo
    FlutterHint     = $flutterHint
    WarnSigning     = $warnSigning
    WarnIosSigning  = $warnIosSigning
    WarnIosFastlane = $warnIosFastlane
  }
}
