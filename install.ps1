#!/usr/bin/env pwsh
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$TargetPath,
  [ValidateSet('Android', 'iOS', 'Both')]
  [string]$Platform = 'Both',
  [string]$ConfigFile,
  [switch]$Force,
  [switch]$UpdateSecrets,
  [switch]$SkipSecrets,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$InstallerRoot = $PSScriptRoot

. (Join-Path $InstallerRoot 'lib/InstallConfig.ps1')
. (Join-Path $InstallerRoot 'lib/Render-Template.ps1')
. (Join-Path $InstallerRoot 'lib/Validate-Target.ps1')
. (Join-Path $InstallerRoot 'lib/Read-Config.ps1')
. (Join-Path $InstallerRoot 'lib/Scaffold-Files.ps1')
. (Join-Path $InstallerRoot 'lib/Set-GhSecrets.ps1')

Write-Host '=== Flutter CI/CD Installer ===' -ForegroundColor Cyan

$targetInfo = Validate-InstallTarget -TargetPath $TargetPath -Platform $Platform
if ($targetInfo.WarnSigning) {
  Write-Warning 'android/app/build.gradle may be missing release signingConfigs.'
}
if ($targetInfo.WarnIosSigning) {
  Write-Warning 'iOS Release may still use automatic signing. Configure manual signing in Xcode.'
}
if ($targetInfo.WarnIosFastlane) {
  Write-Warning 'ios/fastlane/ not found yet (expected on first install).'
}

$useDefaults = $WhatIf -and -not $ConfigFile
$config = Read-InstallConfig -TargetInfo $targetInfo -ConfigFile $ConfigFile `
  -Platform $Platform -SkipSecrets:$SkipSecrets -UseDefaults:$useDefaults

$null = Invoke-ScaffoldFiles -Config $config -InstallerRoot $InstallerRoot -Force:$Force -WhatIf:$WhatIf

if (-not $SkipSecrets) {
  $setSecrets = $UpdateSecrets
  if (-not $UpdateSecrets -and -not $WhatIf) {
    $answer = Read-Host 'Set GitHub secrets now? [Y/n]'
    $setSecrets = ($answer -ne 'n' -and $answer -ne 'N')
  }
  if ($setSecrets -or $WhatIf) {
    $secretNames = Invoke-SetGhSecrets -Config $config -WhatIf:$WhatIf
    Write-Host "Secrets configured: $($secretNames -join ', ')"
  }
}

Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Green
Write-Host "1. Commit scaffolded files in: $($config.TargetPath)"
if ($config.Platform -in 'Android', 'Both') {
  Write-Host '2. Android: git tag android-v1.0.0+1; git push origin android-v1.0.0+1'
}
if ($config.Platform -in 'iOS', 'Both') {
  Write-Host '3. iOS: run fastlane match appstore on Mac, configure Xcode Release signing'
  Write-Host '4. iOS: git tag ios-v1.0.0+1; git push origin ios-v1.0.0+1'
}
Write-Host "Actions: https://github.com/$($config.GitHubRepo)/actions"
