Pod::Spec.new do |s|
  s.name         = 'NottiSDKExtension'
  # Must equal NottiSDKVersion.current and NottiSDK.podspec (scripts/check-version.sh enforces it in CI).
  s.version      = '0.1.0'
  s.summary      = 'Notification Service Extension rich media for Zeep Notti.'
  s.description  = <<-DESC
    Downloads and attaches the image, video or audio of a Zeep Notti push from a
    Notification Service Extension. Extension-safe; never depends on NottiSDK.
  DESC
  s.homepage     = 'https://github.com/zeeplabs/zeep-notti-ios-sdk'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'Zeep Tecnologia' => 'opensource@zeeplabs.com.br' }
  s.source       = { :git => 'https://github.com/zeeplabs/zeep-notti-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions        = ['5']
  # Resource bundle signing fix (CocoaPods #11402).
  s.cocoapods_version     = '>= 1.12'

  # Same package name as NottiSDK.podspec: the NottiShared sources below use `package` access (AD-006, AD-012).
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name NottiSDK' }

  # Extension-safe code only: never the app SDK, never the launch hook.
  s.source_files = 'Sources/NottiShared/**/*.swift', 'Sources/NottiSDKExtension/**/*.swift'
  s.resource_bundles = { 'NottiSDKExtension_Privacy' => ['Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy'] }
end
