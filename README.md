# flutter-android-cicd-installer

Install GitHub Actions + Fastlane Android Play Store CI/CD into Flutter projects.

## Prerequisites

- PowerShell 7+
- [GitHub CLI](https://cli.github.com/) authenticated (`gh auth login`)
- Ruby + Bundler (optional; used for `bundle lock` on target project)
- Flutter Android project with release signing configured in `android/app/build.gradle`

## Usage

```powershell
git clone https://github.com/<you>/flutter-android-cicd-installer.git
cd flutter-android-cicd-installer
.\install.ps1 -TargetPath "C:\path\to\flutter_app"
```

### Non-interactive mode

Copy `install.config.example.json`, fill in paths and values, then:

```powershell
.\install.ps1 -TargetPath "C:\path\to\flutter_app" `
  -ConfigFile ".\install.config.local.json" `
  -UpdateSecrets
```

### CLI flags

| Flag | Description |
|------|-------------|
| `-TargetPath` | Flutter project root (required) |
| `-ConfigFile` | JSON config for non-interactive install |
| `-Force` | Overwrite existing scaffolded files |
| `-UpdateSecrets` | Set GitHub secrets without prompting |
| `-SkipSecrets` | Scaffold files only; skip secret setup |
| `-WhatIf` | Preview changes without writing files or secrets |

## What gets installed

| Path | Purpose |
|------|---------|
| `.github/workflows/deploy-android.yml` | Tag-based deploy pipeline |
| `android/fastlane/Appfile` | Play Store package + JSON key path |
| `android/fastlane/Fastfile` | `deploy` lane (internal track by default) |
| `android/Gemfile` | Fastlane Ruby dependencies |

## GitHub secrets (environment: `production`)

| Secret | Description |
|--------|-------------|
| `KEYSTORE_BASE64` | Base64-encoded upload keystore (`.jks`) |
| `KEY_ALIAS` | Keystore key alias |
| `KEY_PASSWORD` | Key password |
| `STORE_PASSWORD` | Keystore password |
| `PLAY_STORE_JSON_KEY_BASE64` | Base64-encoded Google Play service account JSON |
| *(custom)* | Any dart-define keys you configure (e.g. `SUPABASE_URL`) |

Secrets are stored in the GitHub **environment** (default: `production`), not repo-level secrets.

## Release workflow

1. Bump version in `pubspec.yaml`
2. Commit and push
3. Tag: `git tag v1.0.0+1` (format: `v{major}.{minor}.{patch}+{build}`)
4. Push tag: `git push origin v1.0.0+1`

Or trigger manually via **Actions → Deploy to Play Store → Run workflow**.

## Troubleshooting

### `PLAY_STORE_JSON_KEY_BASE64 is not set`

Ensure the secret name is exactly `PLAY_STORE_JSON_KEY_BASE64` in the `production` environment.

### Tag rejected by workflow

Tags must match `v<major>.<minor>.<patch>+<build>` (e.g. `v1.0.3+12`). The `+` cannot appear in the GitHub tag glob; the workflow uses `v*` and validates in-job.

### `bundle` platform error on CI

Run locally in the target project's `android/` directory:

```powershell
bundle lock --add-platform x86_64-linux
```

### Signing errors

Ensure `android/app/build.gradle` has `signingConfigs` referencing `key.properties` before first deploy.

## Testing the installer

Dry-run against an existing project:

```powershell
.\install.ps1 -TargetPath "C:\path\to\flutter_app" -WhatIf -SkipSecrets
```

Run unit tests:

```powershell
Invoke-Pester -Path tests/
```

## Manual secret test

For a throwaway GitHub repo, use `-UpdateSecrets` with a filled `install.config.local.json` containing valid keystore and service account paths. Never commit that file.
