. "$PSScriptRoot/../lib/Update-IosPodfile.ps1"

Describe 'Get-IosPodfilePlatformVersion' {
  It 'reads platform version from Podfile' {
    $pod = @"
platform :ios, '15.0'
target 'Runner' do
end
"@
    Get-IosPodfilePlatformVersion -PodfileContent $pod | Should Be '15.0'
  }

  It 'falls back to 15.0 when platform line is missing' {
    Get-IosPodfilePlatformVersion -PodfileContent "target 'Runner' do`nend" | Should Be '15.0'
  }
}

Describe 'Update-IosPodfile' {
  It 'injects deployment target into existing post_install' {
    $root = Join-Path $TestDrive 'proj'
    $ios = Join-Path $root 'ios'
    New-Item -ItemType Directory -Force -Path $ios | Out-Null
    $podfile = @"
platform :ios, '15.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
"@
    Set-Content -Path (Join-Path $ios 'Podfile') -Value $podfile -NoNewline

    Update-IosPodfile -TargetPath $root | Should Not BeNullOrEmpty
  }

  It 'is idempotent on second run' {
    $root = Join-Path $TestDrive 'proj2'
    $ios = Join-Path $root 'ios'
    New-Item -ItemType Directory -Force -Path $ios | Out-Null
    $podfile = @"
platform :ios, '15.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
"@
    Set-Content -Path (Join-Path $ios 'Podfile') -Value $podfile -NoNewline

    Update-IosPodfile -TargetPath $root | Out-Null
    $afterFirst = Get-Content -Raw (Join-Path $ios 'Podfile')
    Update-IosPodfile -TargetPath $root | Out-Null
    $afterSecond = Get-Content -Raw (Join-Path $ios 'Podfile')

    $afterSecond | Should Be $afterFirst
    ($afterSecond | Select-String -Pattern 'IPHONEOS_DEPLOYMENT_TARGET' -AllMatches).Matches.Count | Should Be 1
  }

  It 'uses the Podfile platform version in the patch' {
    $root = Join-Path $TestDrive 'proj3'
    $ios = Join-Path $root 'ios'
    New-Item -ItemType Directory -Force -Path $ios | Out-Null
    $podfile = @"
platform :ios, '16.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
"@
    Set-Content -Path (Join-Path $ios 'Podfile') -Value $podfile -NoNewline

    Update-IosPodfile -TargetPath $root | Out-Null
    $patched = Get-Content -Raw (Join-Path $ios 'Podfile')
    $patched | Should Match "IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'"
  }
}
