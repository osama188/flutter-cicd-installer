function Ensure-GhEnvironment {
  param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Environment
  )
  $owner, $name = $Repo.Split('/')
  $prevNativePreference = $PSNativeCommandUseErrorActionPreference
  $prevErrorAction = $ErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    $ErrorActionPreference = 'Continue'
  try {
    gh api "repos/$owner/$name/environments/$Environment" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      gh api --method PUT "repos/$owner/$name/environments/$Environment" 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub environment '$Environment' for $Repo. Verify the repo exists and gh has admin access."
      }
    }
  } finally {
    $PSNativeCommandUseErrorActionPreference = $prevNativePreference
    $ErrorActionPreference = $prevErrorAction
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

function Get-MatchGitRepoFromUrl {
  param([Parameter(Mandatory)][string]$MatchGitUrl)

  if ($MatchGitUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)') {
    return @{ Owner = $Matches.owner; Name = $Matches.repo }
  }
  throw "Unsupported matchGitUrl format: $MatchGitUrl"
}

function Test-MatchGitCredentials {
  param(
    [Parameter(Mandatory)][string]$Username,
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$MatchGitUrl
  )

  if ([string]::IsNullOrWhiteSpace($Token)) { return $false }

  $repo = Get-MatchGitRepoFromUrl -MatchGitUrl $MatchGitUrl
  $raw = "${Username}:${Token}"
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))
  try {
    $null = Invoke-RestMethod `
      -Uri "https://api.github.com/repos/$($repo.Owner)/$($repo.Name)" `
      -Headers @{
        Authorization = "Basic $b64"
        Accept        = 'application/vnd.github+json'
      }
    return $true
  } catch {
    return $false
  }
}

function Resolve-MatchGitPat {
  param(
    [Parameter(Mandatory)]$Config
  )

  if (-not [string]::IsNullOrWhiteSpace($Config.MatchGitPat)) {
    if (Test-MatchGitCredentials -Username $Config.MatchGitUsername `
        -Token $Config.MatchGitPat -MatchGitUrl $Config.MatchGitUrl) {
      return $Config.MatchGitPat
    }
    Write-Warning "ios.matchGitPat cannot access $($Config.MatchGitUrl). Falling back to gh auth token."
  }

  $ghToken = (gh auth token 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ghToken)) {
    throw "No valid match Git credentials. Set ios.matchGitPat in config or run 'gh auth login' with access to $($Config.MatchGitUrl)."
  }
  if (-not (Test-MatchGitCredentials -Username $Config.MatchGitUsername `
      -Token $ghToken -MatchGitUrl $Config.MatchGitUrl)) {
    throw "gh auth token cannot read $($Config.MatchGitUrl). Grant repo access or use a PAT with read access to ios-certificates."
  }

  Write-Host 'Using gh auth token for MATCH_GIT_BASIC_AUTHORIZATION'
  return $ghToken
}

function New-MatchGitBasicAuthorization {
  param(
    [Parameter(Mandatory)][string]$Username,
    [Parameter(Mandatory)][string]$Token
  )

  $raw = "${Username}:${Token}"
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))
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
    $matchPat = Resolve-MatchGitPat -Config $Config
    $matchAuth = New-MatchGitBasicAuthorization `
      -Username $Config.MatchGitUsername -Token $matchPat
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
