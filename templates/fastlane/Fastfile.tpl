default_platform(:android)

platform :android do
  desc "Upload AAB to Play Store"
  lane :deploy do
    upload_to_play_store(
      track: "{{PLAY_STORE_TRACK}}",
      aab: "../build/app/outputs/bundle/release/app-release.aab",
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_changelogs: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )
  end
end
