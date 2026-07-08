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
| `ios.inHouse` | `false` | Set `in_house` on the App Store Connect API key in the generated Fastfile. Use `false` for standard App Store / TestFlight accounts; set `true` only for Apple Enterprise (in-house) accounts. |

In interactive mode, you are prompted: `Apple Enterprise (in-house) account? [y/N]` (default: no).

### What the iOS installer patches automatically

| Target | Change |
|--------|--------|
| `.github/workflows/deploy-ios.yml` | FlutterFire CLI install step (for Crashlytics symbol upload) |
| `ios/fastlane/Fastfile` | `in_house: false` by default (App Store / TestFlight) |
| `ios/Podfile` | `IPHONEOS_DEPLOYMENT_TARGET` aligned to `platform :ios` version in `post_install` |
| Flutter build step | Full `flutter build ios` in Fastlane (not `--config-only`) with `--dart-define-from-file` so compile-time defines are baked in before archive |

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

The generated `ios/fastlane/Fastfile` sets `in_house: false` by default (configurable via `ios.inHouse` in the install config). Set `inHouse` to `true` only if you use an Apple Enterprise account.

### Shared (optional)

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL`, etc. | Dart-define keys (Android: test+build; iOS: build only) |

## iOS one-time operator checklist

The installer scaffolds files and sets secrets but **cannot** automate:

1. Create App Store Connect API key (role: **App Manager** or **Admin**)
2. Create private `ios-certificates` GitHub repo
3. Run `fastlane match appstore` on a Mac
4. Xcode: Runner → Release → manual signing → commit `project.pbxproj`

The installer **does** automatically:

- Install `flutterfire_cli` in CI (required if `flutterfire configure` added the Crashlytics Xcode build phase)
- Patch `ios/Podfile` pod deployment targets to match your `platform :ios` version
- Generate `in_house: false` in the Fastfile for standard TestFlight deploys

## iOS troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Archive fails on `flutterfire upload-crashlytics-symbols` | `flutterfire` CLI missing on CI | Re-run installer with `-Force -Platform iOS` (v2.1.0+ includes the workflow step) |
| App shows "Something went wrong" after splash on TestFlight | `--dart-define` values not compiled into release build | v2.1.1+ runs full `flutter build ios` in Fastlane before archive; verify `SUPABASE_*` secrets are non-empty |
| `upload_to_testflight` auth error | `in_house: true` on a standard App Store account | Set `ios.inHouse` to `false` and re-scaffold Fastfile |
| Pod `IPHONEOS_DEPLOYMENT_TARGET` warnings | Pods target older iOS than Xcode supports | Re-run installer to patch Podfile, or add the `post_install` block manually |
| Match works but upload fails | ASC API key lacks App Manager role, or wrong `ASC_*` secrets | Verify secrets in `production` environment; re-encode `.p8` as base64 |

To refresh an existing project after upgrading the installer:

```powershell
.\install.ps1 -TargetPath "C:\path\to\flutter_app" -Platform iOS -Force -SkipSecrets
```

## Testing

```powershell
Invoke-Pester -Path tests/
.\install.ps1 -TargetPath "C:\path\to\flutter_app" -WhatIf -SkipSecrets -Platform Both
```

## Migration from v1.x

- Repo renamed from `flutter-android-cicd-installer` to `flutter-cicd-installer`
- Android tags changed from `v*` to `android-v*`
- Installer v2.0.0 adds iOS support
- Installer v2.1.0 ports production iOS CI fixes: FlutterFire CLI step, `in_house: false` default, Podfile deployment-target patch
- Installer v2.1.1 fixes dart-define propagation: full `flutter build ios` in Fastlane instead of workflow `--config-only`
