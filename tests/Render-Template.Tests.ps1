. "$PSScriptRoot/../lib/Render-Template.ps1"
. "$PSScriptRoot/../lib/InstallConfig.ps1"

Describe 'Expand-Template' {
  It 'replaces placeholders' {
    $tpl = Join-Path $TestDrive 't.tpl'
    Set-Content $tpl '{{NAME}}-{{VER}}'
    $out = Expand-Template -TemplatePath $tpl -Placeholders @{
      NAME = 'com.app'
      VER  = '1.0.0'
    }
    $out.TrimEnd() | Should Be 'com.app-1.0.0'
  }
}

Describe 'Get-DartDefinesWorkflowBlocks' {
  It 'returns empty blocks when no keys' {
    $b = Get-DartDefinesWorkflowBlocks -Keys @()
    $b.DartDefinesStep | Should Be ''
    $b.TestCommand | Should Be 'flutter test'
  }

  It 'generates jq block for two keys' {
    $b = Get-DartDefinesWorkflowBlocks -Keys @('SUPABASE_URL', 'SUPABASE_ANON_KEY')
    $b.DartDefinesStep | Should Match 'SUPABASE_URL'
    $b.DartDefinesStep | Should Match 'dart_defines.json'
    $b.TestCommand | Should Match 'dart-define-from-file'
  }
}

Describe 'Get-IosDartDefinesWorkflowBlocks' {
  It 'omits dart defines when no keys' {
    $b = Get-IosDartDefinesWorkflowBlocks -Keys @()
    $b.DartDefinesStep | Should Be ''
  }

  It 'includes dart defines step with secret validation' {
    $b = Get-IosDartDefinesWorkflowBlocks -Keys @('SUPABASE_URL')
    $b.DartDefinesStep | Should Match 'dart_defines.json'
    $b.DartDefinesStep | Should Match 'Secret SUPABASE_URL is empty'
  }

  It 'does not include config-only flutter build in workflow' {
    $b = Get-IosDartDefinesWorkflowBlocks -Keys @('SUPABASE_URL')
    $b.DartDefinesStep | Should Not Match 'config-only'
  }
}

Describe 'Android workflow template' {
  It 'uses android-v tag prefix' {
    $tpl = Join-Path $PSScriptRoot '../templates/android/workflow/deploy-android.yml.tpl'
    $content = Get-Content -Raw $tpl
    $content | Should Match "android-v\*"
    $content | Should Match 'refs/tags/android-v'
  }
}

Describe 'New-InstallConfig' {
  It 'defaults InHouse to false' {
    $cfg = New-InstallConfig `
      -TargetPath $TestDrive `
      -PackageName 'com.example.app' `
      -FlutterVersion '3.41.5' `
      -GitHubEnvironment 'production' `
      -PlayStoreTrack 'internal' `
      -GitHubRepo 'owner/repo'
    $cfg.InHouse | Should Be $false
  }
}

Describe 'iOS Fastfile template' {
  It 'uses configurable in_house placeholder' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/fastlane/Fastfile.tpl'
    $content = Get-Content -Raw $tpl
    $content | Should Match 'in_house: \{\{IN_HOUSE\}\}'
  }

  It 'renders in_house from config' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/fastlane/Fastfile.tpl'
    $out = Expand-Template -TemplatePath $tpl -Placeholders @{
      BUNDLE_ID     = 'com.example.app'
      MATCH_GIT_URL = 'https://github.com/owner/ios-certificates.git'
      IN_HOUSE      = 'false'
    }
    $out | Should Match 'in_house: false'
  }

  It 'renders in_house true for enterprise accounts' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/fastlane/Fastfile.tpl'
    $out = Expand-Template -TemplatePath $tpl -Placeholders @{
      BUNDLE_ID     = 'com.example.app'
      MATCH_GIT_URL = 'https://github.com/owner/ios-certificates.git'
      IN_HOUSE      = 'true'
    }
    $out | Should Match 'in_house: true'
  }

  It 'compiles dart defines before archive' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/fastlane/Fastfile.tpl'
    $content = Get-Content -Raw $tpl
    $content | Should Match 'flutter build ios --release --no-codesign'
    $content | Should Match 'dart-define-from-file'
    $content | Should Match 'DART_DEFINES missing'
  }
}

Describe 'iOS workflow template' {
  It 'installs flutterfire_cli' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/workflow/deploy-ios.yml.tpl'
    $content = Get-Content -Raw $tpl
    $content | Should Match 'flutterfire_cli'
    $content | Should Match 'Install FlutterFire CLI'
  }

  It 'uses ios-v tag prefix' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/workflow/deploy-ios.yml.tpl'
    $content = Get-Content -Raw $tpl
    $content | Should Match "ios-v\*"
    $content | Should Match 'refs/tags/ios-v'
  }

  It 'does not use config-only flutter build in workflow' {
    $tpl = Join-Path $PSScriptRoot '../templates/ios/workflow/deploy-ios.yml.tpl'
    $content = Get-Content -Raw $tpl
    $content | Should Not Match 'config-only'
  }
}
