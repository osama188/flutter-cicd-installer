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
