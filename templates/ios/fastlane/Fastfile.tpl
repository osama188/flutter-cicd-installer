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

    project_root = File.expand_path("../..", __dir__)
    dart_defines = File.join(project_root, "dart_defines.json")
    define_flag = File.exist?(dart_defines) ? "--dart-define-from-file=#{dart_defines}" : ""

    sh(
      "cd #{project_root.shellescape} && flutter build ios --release --no-codesign " \
      "--build-name=#{ENV['VERSION_NAME']} " \
      "--build-number=#{ENV['BUILD_NUMBER']} " \
      "#{define_flag}"
    )

    if File.exist?(dart_defines)
      generated_xcconfig = File.join(project_root, "ios/Flutter/Generated.xcconfig")
      generated = File.read(generated_xcconfig)
      unless generated.match?(/DART_DEFINES=.+/)
        UI.user_error!(
          "DART_DEFINES missing from Generated.xcconfig — " \
          "dart-defines were not applied to the iOS build"
        )
      end
    end

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
