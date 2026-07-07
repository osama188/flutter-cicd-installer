name: Deploy to Play Store
run-name: Android Play Store release ${{ github.ref_name }}

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
      - 'v*'

concurrency:
  group: android-deploy-${{ github.ref }}
  cancel-in-progress: true

jobs:
  deploy:
    name: Build & Deploy to Play Store
    runs-on: ubuntu-latest
    environment: {{GITHUB_ENV}}

    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Java
        uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: "17"

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
          working-directory: android

      - name: Install Flutter dependencies
        run: flutter pub get

      - name: Parse version from tag
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          TAG=${GITHUB_REF#refs/tags/v}
          if [[ ! "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
            echo "Tag must match v<major>.<minor>.<patch>+<build>, got: ${GITHUB_REF#refs/tags/}"
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

      - name: Decode keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/upload-keystore.jks

      - name: Create key.properties
        env:
          STORE_PASSWORD: ${{ secrets.STORE_PASSWORD }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
        run: |
          echo "storePassword=${STORE_PASSWORD}" > android/key.properties
          echo "keyPassword=${KEY_PASSWORD}" >> android/key.properties
          echo "keyAlias=${KEY_ALIAS}" >> android/key.properties
          echo "storeFile=upload-keystore.jks" >> android/key.properties

      - name: Decode Play Store service account
        env:
          PLAY_STORE_JSON_KEY_BASE64: ${{ secrets.PLAY_STORE_JSON_KEY_BASE64 }}
        run: |
          set -euo pipefail
          mkdir -p android/fastlane/secrets
          OUT=android/fastlane/secrets/cicd-play-store-secret-key.json

          if [ -z "${PLAY_STORE_JSON_KEY_BASE64:-}" ]; then
            echo "PLAY_STORE_JSON_KEY_BASE64 is not set in the {{GITHUB_ENV}} environment."
            exit 1
          fi

          printf '%s' "$PLAY_STORE_JSON_KEY_BASE64" | tr -d ' \t\n\r' | base64 --decode > "$OUT"

          if ! jq -e '.type == "service_account" and (.private_key | length) > 0' "$OUT" >/dev/null; then
            echo "Invalid Google service account JSON after decode."
            exit 1
          fi

          echo "Play Store JSON OK for $(jq -r '.client_email' "$OUT")"

{{DART_DEFINES_STEP}}
      - name: Run tests
        run: {{TEST_COMMAND}}

      - name: Build App Bundle
        run: |
          flutter build appbundle \
            --release \
            --build-name="${VERSION_NAME}" \
            --build-number="${BUILD_NUMBER}"{{BUILD_DEFINE_FLAGS}}

      - name: Deploy to Play Store
        run: bundle exec fastlane deploy
        working-directory: android
