name: Deploy to TestFlight
run-name: iOS TestFlight release ${{ github.ref_name }}

on:
  workflow_dispatch:
    inputs:
      version_name:
        description: "Version name (e.g. 1.0.4)"
        required: true
      build_number:
        description: "Build number (e.g. 5)"
        required: true
  push:
    tags:
      - 'ios-v*'

concurrency:
  group: ios-deploy-${{ github.ref }}
  cancel-in-progress: true

jobs:
  deploy:
    name: Build & Deploy to TestFlight
    runs-on: macos-latest
    environment: {{GITHUB_ENV}}

    env:
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
      MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}

    steps:
      - name: Select latest stable Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: "{{FLUTTER_VERSION}}"
          cache: true

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
          working-directory: ios

      - name: Install Flutter dependencies
        run: flutter pub get

      - name: Install FlutterFire CLI
        run: |
          dart pub global activate flutterfire_cli
          echo "$HOME/.pub-cache/bin" >> $GITHUB_PATH

      - name: Parse version from tag
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          TAG=${GITHUB_REF#refs/tags/ios-v}
          if [[ ! "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
            echo "Tag must match ios-v<major>.<minor>.<patch>+<build>, got: ${GITHUB_REF#refs/tags/}"
            exit 1
          fi
          VERSION_NAME=${TAG%+*}
          BUILD_NUMBER=${TAG#*+}
          echo "VERSION_NAME=$VERSION_NAME" >> $GITHUB_ENV
          echo "BUILD_NUMBER=$BUILD_NUMBER" >> $GITHUB_ENV
          echo "Version name: $VERSION_NAME"
          echo "Build number: $BUILD_NUMBER"

      - name: Set version from manual input
        if: github.event_name == 'workflow_dispatch'
        run: |
          echo "VERSION_NAME=${{ inputs.version_name }}" >> $GITHUB_ENV
          echo "BUILD_NUMBER=${{ inputs.build_number }}" >> $GITHUB_ENV
          echo "Version name: ${{ inputs.version_name }}"
          echo "Build number: ${{ inputs.build_number }}"

      - name: Decode App Store Connect API key
        env:
          ASC_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
        run: |
          set -euo pipefail
          if [ -z "${ASC_KEY_CONTENT:-}" ]; then
            echo "ASC_KEY_CONTENT is not set in the {{GITHUB_ENV}} environment."
            exit 1
          fi
          printf '%s' "$ASC_KEY_CONTENT" | tr -d ' \t\n\r' | base64 --decode > /tmp/AuthKey.p8
          test -s /tmp/AuthKey.p8

{{DART_DEFINES_STEP}}
      - name: Prepare iOS build config
        run: |
{{BUILD_IOS_COMMAND}}

      - name: Deploy to TestFlight
        run: bundle exec fastlane deploy
        working-directory: ios
