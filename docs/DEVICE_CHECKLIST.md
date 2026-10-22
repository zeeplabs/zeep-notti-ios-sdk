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
**Prerequisites:** Local xcconfig with real credentials; app installed on the device, built with the default scheme `NottiExample`.
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

**Closes:** same todo as D01 (permission prompt part). Tick that todo once, after D01 to D04 pass; D03 "Not run" keeps it open.
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

## D03. Geocoder and location sharing (needs another host app)

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

- [ ] Pass  - [ ] Fail  - [ ] Not run (carried as unproven; then do **not** tick the core-port T8 todo)
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

## D09. SwiftUI app without `@UIApplicationDelegateAdaptor`

**Closes:** same todo as D08 (the class-name check on SwiftUI's internal delegate). Only part B below proves that check; part A alone does not.
**What the SDK does here:** it does **not** swizzle SwiftUI's internal app delegate. It logs one warning and leaves the APNs token callbacks alone, so the device never registers through the SDK (the fix for an integrator is to add `@UIApplicationDelegateAdaptor`). Only the `UNUserNotificationCenter` swizzle still applies. This is a documented limitation, not a bug to fix.
**Prerequisites:** D01 passed on the default scheme, so the device is already registered. Scheme `NottiExample-NoAdaptor`. Its `Debug-NoAdaptor` configuration has no `USE_ADAPTOR` flag (asserted in CI, and checked locally with `xcodebuild -showBuildSettings`), so SwiftUI supplies its own internal delegate.
**Steps, part A (over-install: `received` and `clicked`):**
1. Install the NoAdaptor build **over** the existing app (no delete). **Setup** → **Initialize**. **Push** → **Add listeners**.
2. Send a push in the foreground, then background the app and tap a push.
**Steps, part B (fresh install: the class-name check):**
3. Delete the app. Install the NoAdaptor build. **Setup** → **Initialize**. **Push** → **Request permission (async)** and allow. Wait about a minute, then tap **Refresh device id**. Check the Log shows `initialize: ok` and `permission: granted`, so a missing device id is not a network or backend failure.
**Expected:**
- Part A: no crash, and `received` (foreground) and `clicked` (tap) arrive in the Log through the notification-center path.
- Part B (the pass criterion for the class-name check): "Device id" stays "none". If a device id **does** appear, the SDK swizzled SwiftUI's internal delegate, which means the name check missed its real class: record that as a **Fail**.
- The "use @UIApplicationDelegateAdaptor or the manual API" warning is **not** a criterion: the SDK emits it once, at launch, at level `warn`, and the default level is `error`, so you will not see it (see the STATE todo on a launch-time log level).

- [ ] Pass  - [ ] Fail
Result:

## D10. Manual forwarding with swizzling off

**Closes:** same todo as D08 (manual path). New device proof from EXR-04.
**Prerequisites:** D01 passed. Scheme `NottiExample-Manual` (`NottiDisableSwizzling` is `true`).
**Steps:** **Setup** shows "Swizzling: off (manual forwarding)". Repeat D08.
**Expected:** `received` and `clicked` once each, delivered through the five forwarded calls.

- [ ] Pass  - [ ] Fail
Result:

## D11. Fetch callback added to a delegate that lacks it (needs another host app)

**Closes:** nothing by itself. The STATE todo "(delegate-integration Verifier r1 N5/N7/N9, notes)" is about the **late** install path (the SDK installs after UIKit already read the delegate's capabilities), which only happens when the launch hook did not run before the delegate was set. That is not a normal SPM or CocoaPods layout and no check here reaches it. A Pass here does **not** tick that todo; it stays open as unproven.
**What it checks:** the early path. With the hook linked, the SDK adds `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` to a delegate that has neither that method nor the legacy `application(_:didReceiveRemoteNotification:)`, before UIKit reads the delegate. (If the legacy method exists, the SDK adds nothing and a silent push gives no `received`.)
**Not provable with the example:** `ExampleAppDelegate` implements every callback. Run it in the separate test app you plan to build, or carry it as unproven.
**Prerequisites:** A host app with a UIKit app delegate that implements neither method above, the SDK linked, `Notti.initialize` called and a `received` listener added. D01 passed.
**Steps:** Cold-launch the app, then send a silent push (as in D15) with the app in the foreground.
**Expected:** One `received` for the silent push and no crash.

- [ ] Pass  - [ ] Fail  - [ ] Not run (carried as unproven)
Result:

## D12. Launch hook in a CocoaPods app, static frameworks

**Closes:** same todo as D08 (CocoaPods static half; tick it together with D08 and D09).
**Prerequisites:** `NOTTI_LINKAGE=static`, `xcodegen --spec project-pods.yml`, `pod install`, open `NottiExample.xcworkspace`.
**Steps:** Repeat D08.
**Expected:** Same results as SPM. Hook count in the app is 1 (the hosted tests assert it; here you confirm behavior on a device).

- [ ] Pass  - [ ] Fail
Result:

Static libraries (`NOTTI_LINKAGE=libs`) are proven by the hosted simulator tests and strict device builds only; no device item covers them. Add one run of D08 with `libs` if you want device proof.

## D13. Launch hook in a CocoaPods app, dynamic frameworks

**Closes:** same todo as D12 (dynamic half).
**Prerequisites:** `NOTTI_LINKAGE=dynamic`, regenerate and reinstall from scratch (`rm -rf Pods`).
**Steps:** Repeat D08. Also run **D05** once.
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
**Prerequisites:** D01 passed. A silent push (`content-available`) carrying both `notification_id` and `delivery_id` (the SDK reports an event only when both are present), sent through the Notti worker.
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

**Closes:** the open part of STATE todo "(nse-rich-media, D9 …) `PrivacyInfo.xcprivacy` over-declaration" (App Store validation; AD-014 D2). That todo is already ticked for the code change: append the validation result to it.
**Prerequisites:** An Archive of the example (or a throwaway host app) with the extension, signed for distribution, and an App Store Connect record. Upload with Xcode **Validate App** (no release needed).
**Steps:** Archive, **Validate App**, read the report. Check the privacy report in Organizer (**Generate Privacy Report**).
**Expected:** Validation accepts both manifests with no warning about a missing or unjustified required-reason API in `NottiSDKExtension`, and no ITMS error about `PrivacyInfo.xcprivacy`.

- [ ] Pass  - [ ] Fail
Result:

## D18. App Store Connect: privacy labels match the manifest

**Closes:** the open part of STATE todo "(core-port Verifier r1 N7, LGPD) `NSPrivacyCollectedDataTypeUserID` declared … Device ID" (label text confirmation). The todo is already ticked: append the review result to it. Needs legal or privacy review: this item records the review, it does not replace it.
**Prerequisites:** D17 passed. The privacy report from D17.
**Steps:** Compare the report with the README section "What your app declares in App Store Connect".
**Expected:** The report lists Device ID, User ID, Email Address, Phone Number, Coarse Location, Product Interaction, Other Diagnostic Data and Other Data Types, linked and not used for tracking. Legal or privacy confirmed the wording of the **Other** categories and of User ID before `0.1.0`.

- [ ] Pass  - [ ] Fail
Result (reviewer and date):

## D19. App Store acceptance of the dynamic-framework layout

**Closes:** the open part of STATE todo "(example-and-release T1 spike S6 …)" (the [Incerto] part: an extension that loads a framework from the host app). The todo is already ticked: append the App Store result to it.
**Prerequisites:** D13 passed. An Archive built with `NOTTI_LINKAGE=dynamic`.
**Steps:** **Validate App** on that archive.
**Expected:** No error about the extension's `@executable_path/../../Frameworks` rpath or embedded frameworks. If Apple rejects it, record the message: the `NottiSDKExtension` pod then needs a different packaging before `0.1.0`.

- [ ] Pass  - [ ] Fail
Result:

## D20. Device id continuity from `react-native-notti` 0.6.0

**Closes:** none (new item; backs the migration note in the CHANGELOG).
**What it checks:** the SDK does not send its stored device id. It registers with the push token and platform and adopts the id the backend returns, so continuity depends on the APNs token staying the same and on the backend upserting by token.
**Prerequisites:** A test app built with `react-native-notti` 0.6.0 on iOS that has registered a device, and a copy of the same app built with this SDK in place of the module (same bundle id; your own host app, not the example). D01 passed.
**Steps:**
1. Run the React Native build on the device, register, and note in the Notti backend that one device row exists for this install (do not write its id here).
2. Install the SDK build **over** it (no delete). Run it and call `Notti.initialize`.
3. Check the backend again.
**Expected:** Still one device row for this install, the same record, not two. Compare by the device record (and `Notti.deviceId`), not by the user: registration can reset the user link (see D21).

- [ ] Pass  - [ ] Fail
Result:

## D21. Link and tags after a relaunch

**Closes:** none (new item; backs the "launch registration may reset the link" limitation, [Provável]).
**Prerequisites:** D01 passed. Credentials in the local xcconfig.
**Steps:**
1. **Initialize**, **Login** with `checklist-user`, add the tag `checklist=1`. In the backend, confirm the device shows that external user id and tag.
2. Force-quit the app and relaunch it. **Initialize** only (do not log in again, do not add the tag).
3. Check the device in the backend again.
**Expected:** Record whether the external user id and the tag are still there. Pass means they survive; if they are cleared, that is the limitation described in the README (call `login` and `addTags` at each launch), and the result goes to the backend team as a decision.

- [ ] Pass  - [ ] Fail
Result:

---

## After the checklist

1. Tick the STATE todos cited above (one edit, with the date and the Pass results).
2. Move every Fail and every "Not run" (D03, D11) into the `0.1.0` changelog as a known limitation, or run it first.
3. Julio decides the remaining pre-tag gates (see the release PR).
