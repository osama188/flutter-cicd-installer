function Ensure-GhEnvironment {
  param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Environment
  )
  $owner, $name = $Repo.Split('/')
  gh api "repos/$owner/$name/environments/$Environment" 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    gh api --method PUT "repos/$owner/$name/environments/$Environment" -f wait_timer=0 | Out-Null
  }
}

function Set-GhSecret {
  param(
    [string]$Name,
    [string]$Value,
    [string]$Repo,
    [string]$Environment,
    [switch]$WhatIf
  )
  if ($WhatIf) {
    Write-Host "Would set secret: $Name (env: $Environment)"
    return
  }
  gh secret set $Name --env $Environment --repo $Repo --body $Value | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set secret: $Name"
  }
  Write-Host "Set secret: $Name"
}

function Invoke-SetGhSecrets {
  param(
    [Parameter(Mandatory)]$Config,
    [switch]$WhatIf
  )

  if (-not $WhatIf) {
    if (-not (Test-Path $Config.KeystorePath)) {
      throw "Keystore not found: $($Config.KeystorePath)"
    }
    if (-not (Test-Path $Config.ServiceAccountJsonPath)) {
      throw "Service account JSON not found: $($Config.ServiceAccountJsonPath)"
    }
  }

  if (-not $WhatIf) {
    $sa = Get-Content -Raw $Config.ServiceAccountJsonPath | ConvertFrom-Json
    if ($sa.type -ne 'service_account') { throw 'Invalid service account JSON' }
  }

  Ensure-GhEnvironment -Repo $Config.GitHubRepo -Environment $Config.GitHubEnvironment

  $keystoreB64 = ''
  $jsonB64 = ''
  if (-not $WhatIf) {
    $keystoreB64 = [Convert]::ToBase64String(
      [IO.File]::ReadAllBytes((Resolve-Path $Config.KeystorePath)))
    $jsonB64 = [Convert]::ToBase64String(
      [IO.File]::ReadAllBytes((Resolve-Path $Config.ServiceAccountJsonPath)))
  }

  $set = [System.Collections.Generic.List[string]]::new()
  $set.Add('KEYSTORE_BASE64')
  $set.Add('KEY_ALIAS')
  $set.Add('KEY_PASSWORD')
  $set.Add('STORE_PASSWORD')
  $set.Add('PLAY_STORE_JSON_KEY_BASE64')

  Set-GhSecret -Name KEYSTORE_BASE64 -Value $keystoreB64 -Repo $Config.GitHubRepo `
    -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
  Set-GhSecret -Name KEY_ALIAS -Value $Config.KeyAlias -Repo $Config.GitHubRepo `
    -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
  Set-GhSecret -Name KEY_PASSWORD -Value $Config.KeyPassword -Repo $Config.GitHubRepo `
    -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
  Set-GhSecret -Name STORE_PASSWORD -Value $Config.StorePassword -Repo $Config.GitHubRepo `
    -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
  Set-GhSecret -Name PLAY_STORE_JSON_KEY_BASE64 -Value $jsonB64 -Repo $Config.GitHubRepo `
    -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf

  foreach ($key in $Config.DartDefineKeys) {
    $val = $Config.DartDefineValues[$key]
    if (-not $WhatIf -and [string]::IsNullOrWhiteSpace($val)) {
      throw "Missing value for dart-define secret: $key"
    }
    Set-GhSecret -Name $key -Value $val -Repo $Config.GitHubRepo `
      -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
    $set.Add($key)
  }

  return @($set)
}
