APP_IDENTIFIER = "{{BUNDLE_ID}}"

default_platform(:ios)

platform :ios do
  desc "Sync certificates, build, and upload to TestFlight"
  lane :deploy do
    setup_ci

    app_store_connect_api_key(
      key_id: ENV["ASC_KEY_ID"],
      issuer_id: ENV["ASC_ISSUER_ID"],
      key_filepath: "/tmp/AuthKey.p8",
      in_house: {{IN_HOUSE}}
    )

    match(
      type: "appstore",
      readonly: true
    )

    increment_version_number(version_number: ENV["VERSION_NAME"])
    increment_build_number(build_number: ENV["BUILD_NUMBER"])

    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      export_method: "app-store",
      output_directory: "../build/ios/ipa",
      output_name: "Runner.ipa",
      export_xcargs: "-allowProvisioningUpdates",
      export_options: {
        provisioningProfiles: {
          APP_IDENTIFIER => "match AppStore #{APP_IDENTIFIER}"
        }
      }
    )

    upload_to_testflight(
      skip_waiting_for_build_processing: true
    )
  end
end
