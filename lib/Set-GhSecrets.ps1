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

function Set-DartDefineGhSecrets {
  param(
    [Parameter(Mandatory)]$Config,
    [switch]$WhatIf,
    [System.Collections.Generic.List[string]]$Names
  )

  foreach ($key in $Config.DartDefineKeys) {
    $val = $Config.DartDefineValues[$key]
    if (-not $WhatIf -and [string]::IsNullOrWhiteSpace($val)) {
      throw "Missing value for dart-define secret: $key"
    }
    Set-GhSecret -Name $key -Value $val -Repo $Config.GitHubRepo `
      -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
    if (-not $Names.Contains($key)) { $Names.Add($key) }
  }
}

function Invoke-SetAndroidGhSecrets {
  param(
    [Parameter(Mandatory)]$Config,
    [switch]$WhatIf,
    [switch]$IncludeDartDefines
  )

  if (-not $WhatIf) {
    if (-not (Test-Path $Config.KeystorePath)) {
      throw "Keystore not found: $($Config.KeystorePath)"
    }
    if (-not (Test-Path $Config.ServiceAccountJsonPath)) {
      throw "Service account JSON not found: $($Config.ServiceAccountJsonPath)"
    }
    $sa = Get-Content -Raw $Config.ServiceAccountJsonPath | ConvertFrom-Json
    if ($sa.type -ne 'service_account') { throw 'Invalid service account JSON' }
  }

  $keystoreB64 = ''
  $jsonB64 = ''
  if (-not $WhatIf) {
    $keystoreB64 = [Convert]::ToBase64String(
      [IO.File]::ReadAllBytes((Resolve-Path $Config.KeystorePath)))
    $jsonB64 = [Convert]::ToBase64String(
      [IO.File]::ReadAllBytes((Resolve-Path $Config.ServiceAccountJsonPath)))
  }

  $names = [System.Collections.Generic.List[string]]::new()
  foreach ($pair in @(
    @{ N = 'KEYSTORE_BASE64'; V = $keystoreB64 },
    @{ N = 'KEY_ALIAS'; V = $Config.KeyAlias },
    @{ N = 'KEY_PASSWORD'; V = $Config.KeyPassword },
    @{ N = 'STORE_PASSWORD'; V = $Config.StorePassword },
    @{ N = 'PLAY_STORE_JSON_KEY_BASE64'; V = $jsonB64 }
  )) {
    Set-GhSecret -Name $pair.N -Value $pair.V -Repo $Config.GitHubRepo `
      -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
    $names.Add($pair.N)
  }

  if ($IncludeDartDefines) {
    Set-DartDefineGhSecrets -Config $Config -WhatIf:$WhatIf -Names $names
  }
  return @($names)
}

function Invoke-SetIosGhSecrets {
  param(
    [Parameter(Mandatory)]$Config,
    [switch]$WhatIf,
    [switch]$IncludeDartDefines
  )

  if (-not $WhatIf -and -not (Test-Path $Config.AscKeyPath)) {
    throw "ASC key not found: $($Config.AscKeyPath)"
  }

  $ascB64 = ''
  $matchAuth = ''
  if (-not $WhatIf) {
    $ascB64 = [Convert]::ToBase64String(
      [IO.File]::ReadAllBytes((Resolve-Path $Config.AscKeyPath)))
    $raw = "$($Config.MatchGitUsername):$($Config.MatchGitPat)"
    $matchAuth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))
  }

  $names = [System.Collections.Generic.List[string]]::new()
  foreach ($pair in @(
    @{ N = 'ASC_KEY_ID'; V = $Config.AscKeyId },
    @{ N = 'ASC_ISSUER_ID'; V = $Config.AscIssuerId },
    @{ N = 'ASC_KEY_CONTENT'; V = $ascB64 },
    @{ N = 'MATCH_PASSWORD'; V = $Config.MatchPassword },
    @{ N = 'MATCH_GIT_BASIC_AUTHORIZATION'; V = $matchAuth }
  )) {
    Set-GhSecret -Name $pair.N -Value $pair.V -Repo $Config.GitHubRepo `
      -Environment $Config.GitHubEnvironment -WhatIf:$WhatIf
    $names.Add($pair.N)
  }

  if ($IncludeDartDefines) {
    Set-DartDefineGhSecrets -Config $Config -WhatIf:$WhatIf -Names $names
  }
  return @($names)
}

function Invoke-SetGhSecrets {
  param(
    [Parameter(Mandatory)]$Config,
    [switch]$WhatIf
  )

  Ensure-GhEnvironment -Repo $Config.GitHubRepo -Environment $Config.GitHubEnvironment

  $all = [System.Collections.Generic.List[string]]::new()
  $setDartDefines = $Config.DartDefineKeys.Count -gt 0
  if ($Config.Platform -in 'Android', 'Both') {
    foreach ($n in (Invoke-SetAndroidGhSecrets -Config $Config -WhatIf:$WhatIf `
        -IncludeDartDefines:($setDartDefines -and $Config.Platform -eq 'Android'))) {
      if (-not $all.Contains($n)) { $all.Add($n) }
    }
  }
  if ($Config.Platform -in 'iOS', 'Both') {
    foreach ($n in (Invoke-SetIosGhSecrets -Config $Config -WhatIf:$WhatIf `
        -IncludeDartDefines:($setDartDefines -and $Config.Platform -eq 'iOS'))) {
      if (-not $all.Contains($n)) { $all.Add($n) }
    }
  }
  if ($setDartDefines -and $Config.Platform -eq 'Both') {
    Set-DartDefineGhSecrets -Config $Config -WhatIf:$WhatIf -Names $all
  }

  return @($all)
}
