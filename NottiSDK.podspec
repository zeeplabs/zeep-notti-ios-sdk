Pod::Spec.new do |s|
  s.name         = 'NottiSDK'
  # Must equal NottiSDKVersion.current and NottiSDKExtension.podspec (scripts/check-version.sh enforces it in CI).
  s.version      = '0.1.0'
  s.summary      = 'Native iOS SDK for Zeep Notti push notifications.'
  s.description  = <<-DESC
    Device registration, user identity, tags and engagement events (received, opened,
    clicked) for Zeep Notti. Rich media in a Notification Service Extension is the
    separate pod NottiSDKExtension.
  DESC
  s.homepage     = 'https://github.com/zeeplabs/zeep-notti-ios-sdk'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'Zeep Tecnologia' => 'opensource@zeeplabs.com.br' }
  s.source       = { :git => 'https://github.com/zeeplabs/zeep-notti-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions        = ['5']
  # Resource bundle signing fix (CocoaPods #11402).
  s.cocoapods_version     = '>= 1.12'

  # Shared code uses Swift `package` access, which needs a package name (AD-006). NottiSDKExtension.podspec
  # sets the same name: both pods compile the NottiShared sources into their own module (AD-012).
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name NottiSDK' }

  # App SDK plus the Objective-C launch hook (`+load`). CocoaPods links static pods with -ObjC, so its class is kept.
  # The Notification Service Extension uses the separate pod NottiSDKExtension, never this one (AD-012).
  s.source_files = 'Sources/NottiShared/**/*.swift', 'Sources/NottiSDK/**/*.swift', 'Sources/NottiSDKBootstrap/**/*.{h,m}'
  s.public_header_files = 'Sources/NottiSDKBootstrap/include/*.h'
  s.resource_bundles = { 'NottiSDK_Privacy' => ['Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy'] }
end
