# flutter-cicd-installer

Install GitHub Actions + Fastlane CI/CD into Flutter projects for **Android** (Play Store) and **iOS** (TestFlight).

## Prerequisites

- PowerShell 7+
- [GitHub CLI](https://cli.github.com/) authenticated (`gh auth login`)
- Ruby + Bundler (optional; used for `bundle lock` on target project)
- For iOS first-time setup: macOS with Xcode for `fastlane match appstore`

## Usage

```powershell
git clone https://github.com/osama188/flutter-cicd-installer.git
cd flutter-cicd-installer
.\install.ps1 -TargetPath "C:\path\to\flutter_app" -Platform Both
```

### Platform flag

| `-Platform` | Scaffolds |
|-------------|-----------|
| `Android` | `deploy-android.yml`, `android/fastlane/*` |
| `iOS` | `deploy-ios.yml`, `ios/fastlane/*` |
| `Both` | All of the above (default) |

### Non-interactive mode

Copy `install.config.example.json`, fill in paths and values, then:

```powershell
.\install.ps1 -TargetPath "C:\path\to\flutter_app" `
  -ConfigFile ".\install.config.local.json" `
  -Platform Both `
  -UpdateSecrets
```

#### iOS config options (`install.config.json`)

| Field | Default | Description |
|-------|---------|-------------|
| `ios.inHouse` | `true` | Set `in_house` on the App Store Connect API key in the generated Fastfile. Use `true` for Apple Enterprise (in-house) accounts; set `false` for standard App Store Connect accounts. |

In interactive mode, you are prompted: `Apple Enterprise (in-house) account? [Y/n]` (default: yes).

### CLI flags

| Flag | Description |
|------|-------------|
| `-TargetPath` | Flutter project root (required) |
| `-Platform` | `Android`, `iOS`, or `Both` (default: `Both`) |
| `-ConfigFile` | JSON config for non-interactive install |
| `-Force` | Overwrite existing scaffolded files |
| `-UpdateSecrets` | Set GitHub secrets without prompting |
| `-SkipSecrets` | Scaffold files only |
| `-WhatIf` | Preview changes without writing |

## Release tags

| Platform | Tag format | Example |
|----------|------------|---------|
| Android | `android-v{version}+{build}` | `android-v1.0.4+13` |
| iOS | `ios-v{version}+{build}` | `ios-v1.0.4+13` |

Platforms deploy independently — push only the tag for the platform you want to release.

## GitHub secrets (`production` environment)

### Android

| Secret | Description |
|--------|-------------|
| `KEYSTORE_BASE64` | Base64 upload keystore |
| `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD` | Signing |
| `PLAY_STORE_JSON_KEY_BASE64` | Base64 Play service account JSON |

### iOS

| Secret | Description |
|--------|-------------|
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` | App Store Connect API key |
| `MATCH_PASSWORD` | Match encryption passphrase |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 `username:PAT` for certs repo |

The generated `ios/fastlane/Fastfile` sets `in_house: true` by default (configurable via `ios.inHouse` in the install config). Set `inHouse` to `false` if you use a standard App Store Connect account rather than Apple Enterprise.

### Shared (optional)

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL`, etc. | Dart-define keys (Android: test+build; iOS: build only) |

## iOS one-time operator checklist

The installer scaffolds files and sets secrets but **cannot** automate:

1. Create App Store Connect API key
2. Create private `ios-certificates` GitHub repo
3. Run `fastlane match appstore` on a Mac
4. Xcode: Runner → Release → manual signing → commit `project.pbxproj`

## Testing

```powershell
Invoke-Pester -Path tests/
.\install.ps1 -TargetPath "C:\path\to\flutter_app" -WhatIf -SkipSecrets -Platform Both
```

## Migration from v1.x

- Repo renamed from `flutter-android-cicd-installer` to `flutter-cicd-installer`
- Android tags changed from `v*` to `android-v*`
- Installer v2.0.0 adds iOS support
