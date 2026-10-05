# Task: Fix iOS 27 launch crash (UIScene lifecycle) in this Flutter app

You are an AI coding agent. Fix the project so it launches on iOS 27 without crashing, and make sure push notifications, Google Maps and Firebase still work. Work on a new git branch (`fix/ios27-uiscene`), never on `main`. Do not change app features or business logic.

## 1. The problem

On an iPhone running **iOS 27** the app is killed with `SIGTRAP` as soon as the first screen is created. The crash report's main-thread frame is:

```
UIKitCore  _UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption
```

Meaning: the app has not adopted the **UIScene lifecycle**.

- Apple announced at WWDC 2025 that the old app-only lifecycle (`UIApplicationDelegate` without scenes) stops being allowed after iOS 26. iOS 26 only printed a warning. **iOS 27 enforces it.**
- Devices on older iOS (for example iOS 17 or 26) still run the old lifecycle, so they do not crash. Do not conclude the Dart code is at fault.
- Typical signs the project is affected:
  - `ios/Runner/Info.plist` has no `UIApplicationSceneManifest` key.
  - `ios/Runner/AppDelegate.swift` does all setup in `didFinishLaunchingWithOptions` and there is no scene delegate.
  - Flutter SDK is older than 3.38 (check `flutter --version`). UIScene APIs arrived in 3.38 and UIScene is the default in 3.41+.

## 2. Step-by-step fix

### Step 1: Branch and baseline
```
git checkout -b fix/ios27-uiscene
flutter --version
cat pubspec.yaml
```
Record the current Flutter version and the versions of Firebase, maps, location and notification plugins.

### Step 2: Upgrade Flutter
```
flutter upgrade
flutter --version   # target: 3.41 or newer
```
Flutter 3.41+ can migrate the iOS project automatically when you build or run for iOS. Watch the output for a line saying the migration to the UIScene lifecycle finished. If it appears, check the resulting diff in `ios/Runner` instead of redoing it by hand.

### Step 3: Upgrade plugins (important)
Old plugin versions predate scene support. Upgrade them, fix any Dart API breakages, and keep going in small steps:
```
flutter pub outdated
flutter pub upgrade --major-versions
flutter analyze
```
If a full upgrade breaks too much, upgrade in groups: Firebase packages together (`firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `cloud_functions`, `firebase_messaging`), then maps/location, then the rest.

**If the app uses `firebase_messaging`, it must be a recent 16.x release.** FlutterFire merged a fix in March 2026 for iOS notification handling under the UIScene lifecycle (`FlutterImplicitEngineDelegate`). Old 15.x versions can silently stop handling notification taps and foreground notifications after migration.

### Step 4: Check or perform the iOS migration manually
Only do this if the automatic migration did not happen or left the project incomplete. Verify against the official Flutter UIScene migration guide for your exact Flutter version, because details can change.

**4a. `ios/Runner/Info.plist`** must contain a scene manifest similar to:
```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UIApplicationSupportsMultipleScenes</key>
  <false/>
  <key>UISceneConfigurations</key>
  <dict>
    <key>UIWindowSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneClassName</key>
        <string>UIWindowScene</string>
        <key>UISceneDelegateClassName</key>
        <string>FlutterSceneDelegate</string>
        <key>UISceneConfigurationName</key>
        <string>flutter</string>
        <key>UISceneStoryboardFile</key>
        <string>Main</string>
      </dict>
    </array>
  </dict>
</dict>
```
(Optionally point `UISceneDelegateClassName` at a `SceneDelegate` subclass: `class SceneDelegate: FlutterSceneDelegate {}`.)

**4b. `ios/Runner/AppDelegate.swift`** uses the implicit engine pattern. Plugin registration moves into the engine callback; keep your own setup (Firebase, Google Maps key, etc.) in `didFinishLaunchingWithOptions`:
```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep existing setup here: FirebaseApp.configure(), GMSServices.provideAPIKey(...), etc.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```
Remove any old `GeneratedPluginRegistrant.register(with: self)` call so plugins are not registered twice.

### Step 5: Rebuild from clean
```
flutter clean
flutter pub get
cd ios && pod update && cd ..    # only if the project still uses CocoaPods for some plugins
flutter run --release --dart-define-from-file=.env -d <DEVICE_ID>
```
The first build after an upgrade can take 5 to 15 minutes. Warnings like "plugin X does not support Swift Package Manager" or "target does not support arm64 simulator" are warnings, not errors: Flutter falls back to CocoaPods, and the simulator warning only matters for simulator builds.

## 3. Verification checklist

Test on the **iOS 27 device** and on at least one **older iOS device**:

- [ ] App launches past the first screen on iOS 27 (no `SIGTRAP`).
- [ ] App still launches and behaves normally on older iOS.
- [ ] Firebase works (auth, Firestore reads and writes).
- [ ] Google Maps renders (API key still picked up).
- [ ] Location permission and live location still work.
- [ ] **Push notifications:**
  - [ ] a notification shows a banner while the app is **open** (needs `setForegroundNotificationPresentationOptions` set in Dart)
  - [ ] tapping a notification with the app in the **background** triggers `onMessageOpenedApp`
  - [ ] tapping a notification with the app **closed** triggers `getInitialMessage()`
- [ ] Deep links or any other app-lifecycle features still work.

For notification tap debugging use `flutter run` in **debug mode** and breakpoints or log prints. Breakpoints do not work in release or profile builds. If no Dart handler fires on tap, the problem is in the native plugin layer (usually an outdated `firebase_messaging`), not in the Dart handlers.

## 4. Known pitfalls

- **Late plugin registration:** with the implicit engine, plugins register after `didFinishLaunchingWithOptions`. Old plugins that hook the launch event (notably old `firebase_messaging`) can miss their setup. Symptoms: notifications arrive but taps do nothing, or no foreground notifications. Fix: upgrade the plugin.
- **Lifecycle events moved:** after migration UIKit no longer sends some app-level lifecycle callbacks to `AppDelegate`. Any custom code that relied on them (push, deep links, background tasks) must be reviewed.
- **Duplicate listeners in Dart:** if the same `FirebaseMessaging.onMessage` is listened to in several places, messages get processed twice. Make initialization idempotent (set the `_initialized` flag at the start, before any `await`).
- **Large upgrades break other packages:** that is why this work happens on a separate branch. Fix compile errors package by package.
- **Do not edit generated files** such as `GeneratedPluginRegistrant.*`.

## 5. Deliverable

When finished, report:
1. Flutter version before and after.
2. Plugin versions changed.
3. Exact diffs made to `Info.plist` and `AppDelegate.swift`.
4. Which checklist items you verified and which you could not (for example, no physical device available).
5. Any remaining warnings or risks.
