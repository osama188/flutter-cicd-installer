function Get-ApplicationIdFromGradle {
  param([string]$BuildGradlePath)
  $content = Get-Content -Raw $BuildGradlePath
  if ($content -match 'applicationId\s+"([^"]+)"') { return $Matches[1] }
  if ($content -match 'applicationId\s*=\s*"([^"]+)"') { return $Matches[1] }
  throw "Could not read applicationId from $BuildGradlePath"
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

function Test-GhAuthenticated {
  gh auth status 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'gh CLI not authenticated. Run: gh auth login'
  }
}

function Validate-InstallTarget {
  param([Parameter(Mandatory)][string]$TargetPath)

  $resolved = Resolve-Path $TargetPath -ErrorAction Stop
  $pubspec = Join-Path $resolved 'pubspec.yaml'
  $android = Join-Path $resolved 'android'
  $gradle  = Join-Path $resolved 'android/app/build.gradle'
  $gradleKts = Join-Path $resolved 'android/app/build.gradle.kts'

  if (-not (Test-Path $pubspec)) { throw 'Not a Flutter project: pubspec.yaml missing' }
  if (-not (Test-Path $android)) { throw 'android/ directory missing' }
  if (-not (Test-Path $gradle) -and -not (Test-Path $gradleKts)) {
    throw 'android/app/build.gradle or build.gradle.kts missing'
  }

  Test-GhAuthenticated
  $gradlePath = if (Test-Path $gradle) { $gradle } else { $gradleKts }
  $packageName = Get-ApplicationIdFromGradle -BuildGradlePath $gradlePath
  $githubRepo  = Get-GitHubRepoFromRemote -TargetPath $resolved

  $flutterHint = '3.41.5'
  $pubContent = Get-Content -Raw $pubspec
  if ($pubContent -match 'flutter:\s*">=([0-9.]+)"') {
    $flutterHint = $Matches[1]
  }

  $warnSigning = -not (Select-String -Path $gradlePath -Pattern 'signingConfigs' -Quiet)

  [PSCustomObject]@{
    TargetPath  = $resolved.Path
    PackageName = $packageName
    GitHubRepo  = $githubRepo
    FlutterHint = $flutterHint
    WarnSigning = $warnSigning
  }
}
