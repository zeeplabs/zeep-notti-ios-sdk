# NottiSDK for iOS

Native iOS SDK for [Zeep Notti](https://github.com/zeeplabs) push notifications: device registration, user identity, tags, engagement events (`received` / `opened` / `clicked`) and rich media in a Notification Service Extension.

> **Status: pre-release.** Nothing is published yet. The first release (`0.1.0`) targets behavior parity with `react-native-notti` 0.6.0 on iOS. Do not depend on this repo in production.

## Requirements

- iOS 15.0+
- Xcode 15+ (Swift 5.9)

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/zeeplabs/zeep-notti-ios-sdk.git
```

- Add the **`NottiSDK`** product to your app target.
- Add the **`NottiSDKExtension`** product to your Notification Service Extension target (optional, for rich media).

### CocoaPods

```ruby
target 'YourApp' do
  pod 'NottiSDK'
end

target 'YourNotificationServiceExtension' do
  pod 'NottiSDKExtension'
end
```

Linking `NottiSDKExtension` into the app target builds, but exposes no app API. Use `NottiSDK` there. In the extension, `import NottiSDKExtension`, the same line as with SPM. Both pods work with dynamic frameworks, static frameworks and static libraries.

## License

MIT. See [LICENSE](LICENSE).
