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

Copy `install.config.example.json` (no dart-defines) or `install.config.with-dart-defines.example.json` (Supabase example), fill in paths and values, then:

```powershell
.\install.ps1 -TargetPath "C:\path\to\flutter_app" `
  -ConfigFile ".\install.config.local.json" `
  -Platform Both `
  -UpdateSecrets
```

### Dart-define keys (optional)

Many Flutter apps need **no** compile-time `--dart-define` values in CI. The installer supports both cases.

#### No dart-defines (default)

Use this when your app does not read `String.fromEnvironment(...)` at build time (no Supabase keys, API URLs baked in at compile time, etc.).

**Interactive:** press Enter at the prompt:

```text
Dart-define keys (comma-separated) [none]:
```

**Config file:**

```json
"dartDefineKeys": [],
"dartDefineValues": {}
```

**Generated CI behavior:**

| Platform | What happens |
|----------|----------------|
| Android | No `dart_defines.json` step; `flutter test` / `flutter build appbundle` run without `--dart-define-from-file` |
| iOS | No `dart_defines.json` step; Fastlane runs `flutter build ios` without `--dart-define-from-file` |
| Secrets | No extra GitHub secrets beyond signing / store credentials |

#### With dart-defines

Use when your app expects compile-time values, e.g. `String.fromEnvironment('API_URL')`.

**Interactive:** enter comma-separated key names:

```text
Dart-define keys (comma-separated) [none]: API_URL,API_KEY
```

**Config file:**

```json
"dartDefineKeys": ["API_URL", "API_KEY"],
"dartDefineValues": {
  "API_URL": "https://api.example.com",
  "API_KEY": "your-key"
}
```

The installer will:

1. Add a `Create dart_defines.json` workflow step (one GitHub secret per key)
2. Pass `--dart-define-from-file=dart_defines.json` on Android test + build
3. On iOS, pass the same file in Fastlane before archive and fail the build if `DART_DEFINES` is missing from `Generated.xcconfig`

Key names are **fully configurable** — not limited to Supabase. See `install.config.with-dart-defines.example.json` for a Supabase-shaped example.

#### iOS config options (`install.config.json`)

| Field | Default | Description |
|-------|---------|-------------|
| `ios.inHouse` | `false` | Set `in_house` on the App Store Connect API key in the generated Fastfile. Use `false` for standard App Store / TestFlight accounts; set `true` only for Apple Enterprise (in-house) accounts. |

In interactive mode, you are prompted: `Apple Enterprise (in-house) account? [y/N]` (default: no).

### What the iOS installer patches automatically

| Target | Change |
|--------|--------|
| `.github/workflows/deploy-ios.yml` | FlutterFire CLI install step (for Crashlytics symbol upload) |
| `ios/fastlane/Fastfile` | `in_house: false` by default; full `flutter build ios` before archive; reads `dart_defines.json` from **project root** |
| `ios/Podfile` | `IPHONEOS_DEPLOYMENT_TARGET` aligned to `platform :ios` version in `post_install` |

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

## Triggering deployments

After the installer runs, commit the scaffolded files (`.github/workflows/`, `android/fastlane/`, `ios/fastlane/`) and push to GitHub. Each platform has its own workflow and can be released independently.

| Platform | Workflow | Tag prefix |
|----------|----------|------------|
| Android | `Deploy to Play Store` | `android-v*` |
| iOS | `Deploy to TestFlight` | `ios-v*` |

Version format is `{version}+{build}` — same as `pubspec.yaml` (e.g. `version: 1.0.4+13` → tag `android-v1.0.4+13` or `ios-v1.0.4+13`).

### Create and push a release tag

**1. Bump version in `pubspec.yaml`**

```yaml
version: 1.0.4+13
```

**2. Commit and push your branch**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.4+13"
git push origin main
```

Replace `main` with your default branch if different (`master`, etc.).

**3. Create the tag**

Android:

```bash
git tag android-v1.0.4+13
```

iOS:

```bash
git tag ios-v1.0.4+13
```

**4. Push the tag** (this starts the GitHub Action)

```bash
git push origin android-v1.0.4+13
```

or for iOS:

```bash
git push origin ios-v1.0.4+13
```

**One-liner** (create + push tag in one step):

```bash
# Android
git tag android-v1.0.4+13 && git push origin android-v1.0.4+13

# iOS
git tag ios-v1.0.4+13 && git push origin ios-v1.0.4+13
```

Tag must match exactly: `android-v<major>.<minor>.<patch>+<build>` or `ios-v<major>.<minor>.<patch>+<build>`.

### Run manually from GitHub Actions

1. GitHub → **Actions** → **Deploy to Play Store** or **Deploy to TestFlight**
2. **Run workflow** → enter version name (`1.0.4`) and build number (`13`) → **Run workflow**

Use this for ad-hoc deploys without a tag. Keep `pubspec.yaml` in sync with the values you enter.

### Monitor

**Actions** tab on your repo (e.g. `https://github.com/you/your-app/actions`). Workflows use the `production` environment for secrets.

## Release tags (quick reference)

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

### Dart-define secrets (only when `dartDefineKeys` is non-empty)

| Secret | Description |
|--------|-------------|
| One per key in `dartDefineKeys` | Value passed as `--dart-define` at build time (e.g. `API_URL`, `SUPABASE_ANON_KEY`) |

Omit this section entirely for apps with `"dartDefineKeys": []`.

## iOS one-time operator checklist

The installer scaffolds files and sets secrets but **cannot** automate:

1. Create App Store Connect API key (role: **App Manager** or **Admin**)
2. Create private `ios-certificates` GitHub repo
3. Run `fastlane match appstore` on a Mac (from the Flutter project root):

   ```bash
   cd ios
   bundle install
   bundle exec fastlane match appstore
   ```

   Set `matchGitUrl` in your install config to your real certs repo (e.g. `https://github.com/you/ios-certificates.git`), not the example `owner` placeholder.
4. Xcode: Runner → Release → manual signing → commit `project.pbxproj`

The installer **does** automatically:

- Install `flutterfire_cli` in CI (required if `flutterfire configure` added the Crashlytics Xcode build phase)
- Patch `ios/Podfile` pod deployment targets to match your `platform :ios` version
- Generate `in_house: false` in the Fastfile for standard TestFlight deploys

## iOS troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Archive fails on `flutterfire upload-crashlytics-symbols` | `flutterfire` CLI missing on CI | Re-run installer with `-Force -Platform iOS` (v2.1.0+ includes the workflow step) |
| App shows "Something went wrong" after splash on TestFlight | `--dart-define` values not compiled into release build | Verify `production` secrets are non-empty; use v2.1.1+ (full `flutter build ios` in Fastlane); v2.1.3+ fixes `dart_defines.json` path from repo root |
| `upload_to_testflight` auth error | `in_house: true` on a standard App Store account | Set `ios.inHouse` to `false` and re-scaffold Fastfile |
| Pod `IPHONEOS_DEPLOYMENT_TARGET` warnings | Pods target older iOS than Xcode supports | Re-run installer to patch Podfile, or add the `post_install` block manually |
| Match clone fails with exit 128 / "could not read Username" | `MATCH_GIT_BASIC_AUTHORIZATION` uses an expired or invalid PAT | Re-run installer with `-UpdateSecrets` (v2.1.4+ falls back to `gh auth token` if config PAT is invalid), or create a new PAT with read access to `ios-certificates` |
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
- Installer v2.1.2 defaults interactive dart-define prompt to none; documents optional dart-defines in README
- Installer v2.1.3 fixes `dart_defines.json` lookup from repo root in generated iOS Fastfile (not `ios/dart_defines.json`)
