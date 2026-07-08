function Get-IosPodfilePlatformVersion {
  param([string]$PodfileContent)

  if ($PodfileContent -match "platform\s+:ios,\s*'([^']+)'") {
    return $Matches[1]
  }
  return '15.0'
}

function Get-IosPodfileDeploymentTargetPatch {
  param([string]$PlatformVersion)

  @"
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '$PlatformVersion'
    end
"@
}

function Update-IosPodfile {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [switch]$WhatIf
  )

  $podfilePath = Join-Path $TargetPath 'ios/Podfile'
  if (-not (Test-Path $podfilePath)) {
    Write-Warning 'ios/Podfile not found; skipping deployment target patch'
    return $null
  }

  $content = Get-Content -Raw $podfilePath
  if ($content -match 'IPHONEOS_DEPLOYMENT_TARGET') {
    Write-Host "Skip (already patched): $podfilePath"
    return $podfilePath
  }

  $version = Get-IosPodfilePlatformVersion -PodfileContent $content
  $patch = Get-IosPodfileDeploymentTargetPatch -PlatformVersion $version

  if ($content -match 'post_install\s+do\s+\|installer\|') {
    if ($content -match 'flutter_additional_ios_build_settings\(target\)') {
      $newContent = $content -replace (
        '(flutter_additional_ios_build_settings\(target\))'
      ), "`$1`n$patch"
    } else {
      $newContent = $content -replace (
        '(installer\.pods_project\.targets\.each do \|target\|)'
      ), "`$1`n    flutter_additional_ios_build_settings(target)`n$patch"
    }
  } else {
    $newContent = $content.TrimEnd() + @"

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
$patch
  end
end
"@
  }

  if ($WhatIf) {
    Write-Host "Would patch Podfile deployment targets: $podfilePath"
    return $podfilePath
  }

  Set-Content -Path $podfilePath -Value $newContent -NoNewline
  Write-Host "Patched Podfile deployment targets: $podfilePath"
  return $podfilePath
}
