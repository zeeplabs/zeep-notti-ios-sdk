Pod::Spec.new do |s|
  s.name         = 'NottiSDK'
  # Must equal NottiSDKVersion.current (scripts/check-version.sh enforces it in CI).
  s.version      = '0.1.0'
  s.summary      = 'Native iOS SDK for Zeep Notti push notifications.'
  s.description  = <<-DESC
    Device registration, user identity, tags, engagement events (received, opened,
    clicked) and Notification Service Extension rich media for Zeep Notti.
  DESC
  s.homepage     = 'https://github.com/zeeplabs/zeep-notti-ios-sdk'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'Zeep Tecnologia' => 'opensource@zeeplabs.com.br' }
  s.source       = { :git => 'https://github.com/zeeplabs/zeep-notti-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions        = ['5']
  # Resource bundle signing fix (CocoaPods #11402).
  s.cocoapods_version     = '>= 1.12'

  # CocoaPods compiles every subspec into one module, `NottiSDK`. Shared code
  # uses Swift `package` access, which needs a package name (AD-006).
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name NottiSDK' }

  s.default_subspecs = 'Core'

  # Extension-safe code shared by Core and Extension. Not meant to be used alone.
  s.subspec 'Shared' do |ss|
    ss.source_files = 'Sources/NottiShared/**/*.swift'
  end

  # App target SDK. Default subspec.
  s.subspec 'Core' do |ss|
    ss.dependency 'NottiSDK/Shared'
    ss.source_files = 'Sources/NottiSDK/**/*.swift'
    ss.resource_bundles = { 'NottiSDK_Privacy' => ['Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy'] }
  end

  # Notification Service Extension helpers. Must never depend on Core.
  s.subspec 'Extension' do |ss|
    ss.dependency 'NottiSDK/Shared'
    ss.source_files = 'Sources/NottiSDKExtension/**/*.swift'
    ss.resource_bundles = { 'NottiSDKExtension_Privacy' => ['Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy'] }
  end
end
