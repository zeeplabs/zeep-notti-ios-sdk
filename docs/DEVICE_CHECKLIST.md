# Device validation checklist for 0.1.0

CI cannot prove the items below: they need a physical iPhone, a real APNs path or an App Store Connect upload. Run them in one sitting with the example app before the `0.1.0` tag. This is a gate for Julio, not for contributors.

Closing an item in `.specs/project/STATE.md` is a **post-checklist step**: after an item passes, tick the todo it cites there (EXR-16). Do not tick it before.

## Prerequisites

- An iPhone on iOS 15 or later, plugged in, with Developer Mode on.
- An Apple Developer team that can sign for push notifications.
- A Notti app whose APNs key is configured in the backend (development environment for a debug build), and a way to send it a push (dashboard or API).
- The app id and client key of that Notti app in `Example/Config/Example.local.xcconfig` (git-ignored; keys `NOTTI_APP_ID`, `NOTTI_CLIENT_KEY`, optional `NOTTI_HOST`). Without it the example shows "Configured: no" and never calls the SDK.
- In Xcode, after `xcodegen --spec project.yml` (or `project-pods.yml`): set your **Team** and a **unique bundle id** on both `NottiExample` and `NotificationService` (the extension id must start with the app id). The generated project is git-ignored; regenerating resets this. Never commit it.
- Capabilities already in the example: Push Notifications (`aps-environment`), Background Modes → Remote notifications.

## How to record results

Tick **Pass** or **Fail** and add one line under `Result:` with what you saw. Do **not** write the app id, client key, push token, device id, email, phone or any tag value in this file or in a PR. Write "present", "absent" or a count instead.

Test data: use a throwaway external user id such as `checklist-user` and an address at `example.invalid`.

---

## D01. APNs registration and token delivery

**Closes:** STATE todo "(core-port T8) `NottiPlatformProviders.live()` closures … build-verified only" (APNs registration part).
**Prerequisites:** Local xcconfig with real credentials; app installed on the device.
**Steps:**
1. Open the app, **Setup** tab. Check "Configured: yes".
2. Tap **Initialize**. Tap **Push** tab → **Request permission (async)** and allow.
3. Back on **Setup**, tap **Refresh device id**.
**Expected:**
- **Log** tab shows `initialize: ok` and `permission: granted`.
- **Setup** shows "Initialized: yes" and a "Device id" other than "none".
- The device is listed in the Notti backend for that app, platform `ios`.
- A push sent from Notti reaches the device.

- [ ] Pass  - [ ] Fail
Result:

## D02. Permission prompt states

**Closes:** same todo as D01 (permission prompt part). Tick that todo once, after D01 to D04 pass.
**Prerequisites:** D01 passed. Be ready to reset the app's notification setting in iOS Settings.
**Steps:** The example starts uninitialized after every launch, and the SDK drops an APNs token or permission result it receives without an initialized core, so tap **Initialize** first each time.
1. Delete the app, reinstall, **Initialize**, **Request permission (completion)**. Choose **Don't Allow**.
2. In iOS Settings → the app → Notifications, turn **Allow Notifications** on. Reopen the app and tap **Initialize** again.
3. Call **Request permission (async)** again.
**Expected:**
- Step 1: the **Push** section title reads `Permission: denied` and the Log has `permission: denied`.
- Step 3: the title reads `Permission: granted` and the Log has `permission: granted`. The backend device shows the matching `permission_status` and `subscribed` values.

- [ ] Pass  - [ ] Fail
Result:

## D03. Geocoder and location sharing

**Closes:** same todo as D01 (`CLGeocoder` part).
**Prerequisites:** D01 passed. **Known gap:** the example has no `NSLocationWhenInUseUsageDescription` and never asks for location permission, so iOS will not list it under Location Services and this item cannot run in the example as it is. The SDK also never asks (it only reads the country when your app already holds permission). Run this item in a host app that requests When-In-Use location and integrates the SDK, or mark it "not proven" and carry it into the `0.1.0` known limitations. Network on.
**Steps:**
1. Leave **Share location (country)** off. Check the backend device has **no** `country`.
2. Make sure the host app holds When-In-Use location permission.
3. Turn **Share location (country)** on. Wait up to a minute.
4. Turn it off again.
**Expected:**
- Step 1: no `country` in the backend.
- Step 3: the backend device shows a `country` code matching where you are.
- Step 4: the `country` is cleared in the backend.

- [ ] Pass  - [ ] Fail
Result:

## D04. `UIDevice` profile fields

**Closes:** same todo as D01 (`UIDevice` part).
**Prerequisites:** D01 passed.
**Steps:** After **Initialize**, open the device in the Notti backend.
**Expected:** `app_version`, `sdk_version`, `device_os`, `device_model`, `timezone_id` and `language` are present and match the phone (iOS version, model identifier, time zone, language). `sdk_version` equals `NottiSDKVersion.current`.

- [ ] Pass  - [ ] Fail
Result:

## D05. Rich media in the Notification Service Extension: image

**Closes:** STATE todo "(nse-rich-media, device) End to end on a real device with a real push".
**Prerequisites:** D01 passed. The Notti push carries a public `https` image URL.
**Steps:**
1. Lock the phone. Send a push with an image from Notti.
2. Long-press the notification.
**Expected:** The image shows as an attachment in the banner and when expanded. No crash.

- [ ] Pass  - [ ] Fail
Result:

## D06. Rich media: video and audio

**Closes:** same todo as D05 (media kinds).
**Prerequisites:** D05 passed. Pushes whose media URL points to a video and to an audio file of a type the extension supports (`NottiMediaFileType`).
**Steps:** Send one push per kind. Expand each notification.
**Expected:** Each renders as an attachment of its kind. A type the extension does not support shows the text without media and no crash.

- [ ] Pass  - [ ] Fail
Result:

## D07. Notification Service Extension deadline fallback

**Closes:** same todo as D05, for the 20 second deadline path only. The OS expiry callback (`serviceExtensionTimeWillExpire`, about 30 seconds) is **not** reached by this item, because the SDK's own 20 second deadline always ends the job first. Carry the expiry callback as unproven on a device unless you find a way to exceed the deadline.
**Prerequisites:** D05 passed. A media URL that is slow or never finishes (a host you control that stalls).
**Steps:** Send a push pointing at the stalling URL. Wait about 30 seconds.
**Expected:** The notification still appears with its title and body, without the media, once the 20 second deadline passes. No stuck or missing notification.

- [ ] Pass  - [ ] Fail
Result:

## D08. SwiftUI delegate check, with `@UIApplicationDelegateAdaptor`

**Closes:** STATE todo "(delegate-integration, device) The SwiftUI-internal app delegate check … is a class-name check".
**Prerequisites:** D01 passed. Scheme `NottiExample` (the adaptor is on through `USE_ADAPTOR`).
**Steps:**
1. Run the app. **Setup** tab → **Initialize**. **Push** tab → **Add listeners** (both are needed on every launch: the example keeps no state).
2. With the app in the foreground, send a push. Then background the app and tap a push.
**Expected:** The Log shows `received` once per foreground push and `clicked` once per tap, with no duplicates. The Log lists key names only, never values.

- [ ] Pass  - [ ] Fail
Result:

## D09. SwiftUI delegate check, without `@UIApplicationDelegateAdaptor`

**Closes:** same todo as D08.
**Prerequisites:** D01 passed. Scheme `NottiExample-NoAdaptor`. Its `Debug-NoAdaptor` configuration has no `USE_ADAPTOR` flag (asserted in CI and checked locally with `xcodebuild -showBuildSettings`), so SwiftUI supplies its own internal delegate.
**Steps:** Repeat D08 with this scheme.
**Expected:** Same as D08: `received` and `clicked` once each. If the SDK cannot attach, record exactly what is missing; this is the case the class-name check guards.

- [ ] Pass  - [ ] Fail
Result:

## D10. Manual forwarding with swizzling off

**Closes:** same todo as D08 (manual path). New device proof from EXR-04.
**Prerequisites:** D01 passed. Scheme `NottiExample-Manual` (`NottiDisableSwizzling` is `true`).
**Steps:** **Setup** shows "Swizzling: off". Repeat D08.
**Expected:** `received` and `clicked` once each, delivered through the five forwarded calls.

- [ ] Pass  - [ ] Fail
Result:

## D11. Late install path of the launch hook

**Closes:** STATE todo "(delegate-integration Verifier r1 N5/N7/N9, notes)" (late-install path, device-only, [Incerto]).
**Prerequisites:** D01 and D09 passed. Scheme `NottiExample-NoAdaptor`: only there does the SDK have to add missing callbacks to SwiftUI's internal delegate, which is the path this todo is about. (`ExampleAppDelegate` implements all five callbacks, so the adaptor build cannot exercise it.)
**Steps:** Quit the app. Tap a push to launch it cold. Tap **Initialize**, then **Add listeners** and **Take initial click**. Check the Log.
**Expected:** One `clicked` row (key names only), and no crash during launch. Record whether the tap was also reported by the SDK's own callback path without your help.

- [ ] Pass  - [ ] Fail
Result:

## D12. Launch hook in a CocoaPods app, static frameworks

**Closes:** same todo as D08 (CocoaPods static half; tick it together with D08 and D09).
**Prerequisites:** `NOTTI_LINKAGE=static`, `xcodegen --spec project-pods.yml`, `pod install`, open `NottiExample.xcworkspace`.
**Steps:** Repeat D08 and D11.
**Expected:** Same results as SPM. Hook count in the app is 1 (the hosted tests assert it; here you confirm behavior on a device).

- [ ] Pass  - [ ] Fail
Result:

## D13. Launch hook in a CocoaPods app, dynamic frameworks

**Closes:** same todo as D12 (dynamic half).
**Prerequisites:** `NOTTI_LINKAGE=dynamic`, regenerate and reinstall from scratch (`rm -rf Pods`).
**Steps:** Repeat D08 and D11. Also run **D05** once.
**Expected:** Same results. In this layout the extension reaches `NottiSDKExtension.framework` through the app's `Frameworks/`; D05 must still render.

- [ ] Pass  - [ ] Fail
Result:

## D14. Cold-start click

**Closes:** none (new item from EXR-15).
**Prerequisites:** D01 passed.
**Steps:** Quit the app. Tap a push to launch it. Tap **Initialize**, then open **Push** → **Take initial click**.
**Expected:** The Log has one `clicked` row (key names only). Pressing **Take initial click** a second time adds no new `clicked` row, because the click is taken once.

- [ ] Pass  - [ ] Fail
Result:

## D15. Silent push `received`

**Closes:** none (new item from EXR-15).
**Prerequisites:** D01 passed. A silent push (`content-available`) with a `delivery_id`, sent through the Notti worker.
**Steps:** App in the foreground with listeners added. Send the silent push.
**Expected:** One `received` in the Log, and one `received` event for that delivery in the backend.

- [ ] Pass  - [ ] Fail
Result:

## D16. Background `received`

**Closes:** none (new item from EXR-15). Related to STATE todo "NSE reports `received` in the background through an App Group", which stays open and is **not** in scope for 0.1.0.
**Prerequisites:** D15 passed. Background App Refresh on.
**Steps:** Background the app (do not force-quit). Send a silent push. Reopen the app.
**Expected:** Record what happened. Pass means the backend has one `received` event for that delivery; Fail with the observed behavior is a valid, useful result and goes to the changelog as a limitation.

- [ ] Pass  - [ ] Fail
Result:

## D17. App Store Connect validation upload: privacy manifest and `C617.1`

**Closes:** STATE todo "(nse-rich-media, D9 …) `PrivacyInfo.xcprivacy` over-declaration" (App Store validation part; AD-014 D2).
**Prerequisites:** An Archive of the example (or a throwaway host app) with the extension, signed for distribution, and an App Store Connect record. Upload with Xcode **Validate App** (no release needed).
**Steps:** Archive, **Validate App**, read the report. Check the privacy report in Organizer (**Generate Privacy Report**).
**Expected:** Validation accepts both manifests with no warning about a missing or unjustified required-reason API in `NottiSDKExtension`, and no ITMS error about `PrivacyInfo.xcprivacy`.

- [ ] Pass  - [ ] Fail
Result:

## D18. App Store Connect: privacy labels match the manifest

**Closes:** STATE todo "(core-port Verifier r1 N7, LGPD) `NSPrivacyCollectedDataTypeUserID` declared … Device ID" (label text confirmation). Needs legal or privacy review: this item records the review, it does not replace it.
**Prerequisites:** D17 passed. The privacy report from D17.
**Steps:** Compare the report with the README section "What your app declares in App Store Connect".
**Expected:** The report lists Device ID, User ID, Email Address, Phone Number, Coarse Location, Product Interaction, Other Diagnostic Data and Other Data Types, linked and not used for tracking. Legal or privacy confirmed the wording of the **Other** categories and of User ID before `0.1.0`.

- [ ] Pass  - [ ] Fail
Result (reviewer and date):

## D19. App Store acceptance of the dynamic-framework layout

**Closes:** STATE todo "(example-and-release T1 spike S6 …)" (the [Incerto] part: an extension that loads a framework from the host app).
**Prerequisites:** D13 passed. An Archive built with `NOTTI_LINKAGE=dynamic`.
**Steps:** **Validate App** on that archive.
**Expected:** No error about the extension's `@executable_path/../../Frameworks` rpath or embedded frameworks. If Apple rejects it, record the message: the `NottiSDKExtension` pod then needs a different packaging before `0.1.0`.

- [ ] Pass  - [ ] Fail
Result:

## D20. Device id continuity from `react-native-notti` 0.6.0

**Closes:** none (new item; backs the migration note in the CHANGELOG).
**Prerequisites:** A test app built with `react-native-notti` 0.6.0 on iOS that has registered a device. D01 passed for the native SDK.
**Steps:**
1. Run the React Native build on the device, register, and note in the Notti backend that one device exists for the test user (do not write its id here).
2. Replace the module with this SDK in the same app and bundle id, and install the new build **over** the old one (no delete).
3. Run it. **Initialize**, then check the backend.
**Expected:** The backend still shows one device for the test user (same device record), not two. **Setup** shows the "Device id" unchanged from step 1.

- [ ] Pass  - [ ] Fail
Result:

---

## After the checklist

1. Tick the STATE todos cited above (one edit, with the date and the Pass results).
2. Move every Fail into the `0.1.0` changelog as a known limitation, or fix it first.
3. Julio decides the remaining pre-tag gates (see the release PR).
