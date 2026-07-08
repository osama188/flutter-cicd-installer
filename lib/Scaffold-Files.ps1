function Add-GitignoreLines {
  param([string]$GitignorePath, [string[]]$Lines)
  $existing = if (Test-Path $GitignorePath) { Get-Content $GitignorePath } else { @() }
  $toAdd = $Lines | Where-Object { $existing -notcontains $_ }
  if ($toAdd.Count -gt 0) {
    Add-Content -Path $GitignorePath -Value ("`n" + ($toAdd -join "`n"))
  }
}

function Write-ScaffoldFile {
  param(
    [string]$Content,
    [string]$Destination,
    [switch]$Force,
    [switch]$WhatIf
  )
  if ((Test-Path $Destination) -and -not $Force) {
    Write-Host "Skip (exists): $Destination"
    return $null
  }
  if ($WhatIf) {
    Write-Host "Would write: $Destination"
    return $Destination
  }
  $dir = Split-Path $Destination -Parent
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Set-Content -Path $Destination -Value $Content -NoNewline
  Write-Host "Wrote: $Destination"
  return $Destination
}

function Invoke-ScaffoldAndroidFiles {
  param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$InstallerRoot,
    [switch]$Force,
    [switch]$WhatIf
  )

  $dart = Get-DartDefinesWorkflowBlocks -Keys $Config.DartDefineKeys
  $placeholders = @{
    FLUTTER_VERSION    = $Config.FlutterVersion
    GITHUB_ENV         = $Config.GitHubEnvironment
    PACKAGE_NAME       = $Config.PackageName
    PLAY_STORE_TRACK   = $Config.PlayStoreTrack
    DART_DEFINES_STEP  = $dart.DartDefinesStep
    TEST_COMMAND       = $dart.TestCommand
    BUILD_DEFINE_FLAGS = $dart.BuildDefineFlags
  }

  $written = @()
  $tplRoot = Join-Path $InstallerRoot 'templates'
  $target  = $Config.TargetPath

  $workflowTpl = Join-Path $tplRoot 'android/workflow/deploy-android.yml.tpl'
  $workflowOut = Join-Path $target '.github/workflows/deploy-android.yml'
  $wf = Expand-Template -TemplatePath $workflowTpl -Placeholders $placeholders
  $written += Write-ScaffoldFile -Content $wf -Destination $workflowOut -Force:$Force -WhatIf:$WhatIf

  $fastlaneFiles = @(
    @{ Src = 'android/fastlane/Appfile.tpl';  Dst = 'android/fastlane/Appfile';  IsTemplate = $true }
    @{ Src = 'android/fastlane/Fastfile.tpl'; Dst = 'android/fastlane/Fastfile'; IsTemplate = $true }
    @{ Src = 'android/fastlane/Gemfile';      Dst = 'android/Gemfile';           IsTemplate = $false }
  )

  foreach ($entry in $fastlaneFiles) {
    $src = Join-Path $tplRoot $entry.Src
    $dst = Join-Path $target $entry.Dst
    if ($entry.IsTemplate) {
      $ph = @{
        PACKAGE_NAME     = $Config.PackageName
        PLAY_STORE_TRACK = $Config.PlayStoreTrack
      }
      $content = Expand-Template -TemplatePath $src -Placeholders $ph
    } else {
      $content = Get-Content -Raw $src
    }
    $written += Write-ScaffoldFile -Content $content -Destination $dst -Force:$Force -WhatIf:$WhatIf
  }

  if (-not $WhatIf) {
    Add-GitignoreLines -GitignorePath (Join-Path $target '.gitignore') -Lines @(
      'android/fastlane/secrets/'
    )
    $androidDir = Join-Path $target 'android'
    if (Get-Command bundle -ErrorAction SilentlyContinue) {
      Push-Location $androidDir
      try {
        bundle lock --add-platform x86_64-linux 2>$null
      } finally {
        Pop-Location
      }
    } else {
      Write-Warning 'bundle not found; run bundle lock --add-platform x86_64-linux in android/ manually'
    }
  }

  return $written | Where-Object { $_ }
}

function Invoke-ScaffoldIosFiles {
  param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$InstallerRoot,
    [switch]$Force,
    [switch]$WhatIf
  )

  $iosDart = Get-IosDartDefinesWorkflowBlocks -Keys $Config.DartDefineKeys
  $placeholders = @{
    BUNDLE_ID         = $Config.BundleId
    FLUTTER_VERSION   = $Config.FlutterVersion
    GITHUB_ENV        = $Config.GitHubEnvironment
    MATCH_GIT_URL     = $Config.MatchGitUrl
    DART_DEFINES_STEP = $iosDart.DartDefinesStep
    BUILD_IOS_COMMAND = $iosDart.BuildIosCommand
  }

  $written = @()
  $tplRoot = Join-Path $InstallerRoot 'templates'
  $target  = $Config.TargetPath

  $workflowTpl = Join-Path $tplRoot 'ios/workflow/deploy-ios.yml.tpl'
  $workflowOut = Join-Path $target '.github/workflows/deploy-ios.yml'
  $wf = Expand-Template -TemplatePath $workflowTpl -Placeholders $placeholders
  $written += Write-ScaffoldFile -Content $wf -Destination $workflowOut -Force:$Force -WhatIf:$WhatIf

  $fastlaneFiles = @(
    @{ Src = 'ios/fastlane/Appfile.tpl';    Dst = 'ios/fastlane/Appfile';    IsTemplate = $true }
    @{ Src = 'ios/fastlane/Matchfile.tpl';  Dst = 'ios/fastlane/Matchfile';  IsTemplate = $true }
    @{ Src = 'ios/fastlane/Fastfile.tpl';   Dst = 'ios/fastlane/Fastfile';   IsTemplate = $true }
    @{ Src = 'ios/fastlane/Gemfile';        Dst = 'ios/Gemfile';             IsTemplate = $false }
  )

  foreach ($entry in $fastlaneFiles) {
    $src = Join-Path $tplRoot $entry.Src
    $dst = Join-Path $target $entry.Dst
    if ($entry.IsTemplate) {
      $ph = @{
        BUNDLE_ID     = $Config.BundleId
        MATCH_GIT_URL = $Config.MatchGitUrl
        IN_HOUSE      = $Config.InHouse.ToString().ToLower()
      }
      $content = Expand-Template -TemplatePath $src -Placeholders $ph
    } else {
      $content = Get-Content -Raw $src
    }
    $written += Write-ScaffoldFile -Content $content -Destination $dst -Force:$Force -WhatIf:$WhatIf
  }

  if (-not $WhatIf) {
    Add-GitignoreLines -GitignorePath (Join-Path $target '.gitignore') -Lines @(
      'ios/fastlane/secrets/'
    )
    . (Join-Path $InstallerRoot 'lib/Update-IosPodfile.ps1')
    Update-IosPodfile -TargetPath $target
  } else {
    . (Join-Path $InstallerRoot 'lib/Update-IosPodfile.ps1')
    Update-IosPodfile -TargetPath $target -WhatIf
  }

  return $written | Where-Object { $_ }
}

function Invoke-ScaffoldFiles {
  param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$InstallerRoot,
    [switch]$Force,
    [switch]$WhatIf
  )

  . (Join-Path $InstallerRoot 'lib/Render-Template.ps1')
  . (Join-Path $InstallerRoot 'lib/InstallConfig.ps1')

  $written = @()
  if ($Config.Platform -in 'Android', 'Both') {
    $written += Invoke-ScaffoldAndroidFiles -Config $Config -InstallerRoot $InstallerRoot `
      -Force:$Force -WhatIf:$WhatIf
  }
  if ($Config.Platform -in 'iOS', 'Both') {
    $written += Invoke-ScaffoldIosFiles -Config $Config -InstallerRoot $InstallerRoot `
      -Force:$Force -WhatIf:$WhatIf
  }

  if (-not $WhatIf) {
    Add-GitignoreLines -GitignorePath (Join-Path $Config.TargetPath '.gitignore') -Lines @(
      'dart_defines.json'
    )
  }

  return $written | Where-Object { $_ }
}
