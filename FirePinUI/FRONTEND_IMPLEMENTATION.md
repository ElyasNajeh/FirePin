# FirePin / شباب البلد frontend

Frontend-only implementation on `feat/frontend-foundation`. No commits or pushes.
All paths below are relative to `FirePinUI/`.

## Implemented flow

Welcome → camera explanation/native permission → real ID camera/capture →
1.5-second mock scan → identity success → identity data review → phone →
six-digit OTP → phone success → create/confirm four-digit PIN → native location
permission/current position → citizen/volunteer selection.

- Citizen continues to Home, then the real fire-report camera.
- Volunteer continues through confirmation to pending council approval. Pending
  has no Home access; navigation history cannot bypass that state.
- Fire reporting supports a camera capture or no photo, obtains a current
  location, and creates one local incident shared by the reporter, nearby-citizen,
  volunteer, alerts, map, and account views. The demo lifecycle covers waiting,
  volunteer acceptance/en-route, acknowledgment, withdrawal, and resolution.
- Account and alerts are role-aware demo screens. Normal and municipality login
  remain local placeholders.

This is an interactive frontend development build, **not an operational identity
verification or emergency-reporting system**.

## Figma and visual fidelity

The Figma design-to-code skill was used to inspect design context and screenshots
for every supplied node before implementing its corresponding screen. Source:
[FirePin Figma](https://www.figma.com/design/D4V9HSR5hje7rNwssmwhR5/Untitled?node-id=0-1).

| Nodes inspected | Flutter implementation |
| --- | --- |
| `5:8` | `lib/features/welcome/welcome_screen.dart` |
| `109:2`, `52:2` | `lib/features/onboarding/permission_screens.dart` |
| `20:3`, `118:2`, `109:22` | `lib/features/onboarding/identity_screens.dart` |
| `109:48`, `109:63`, `109:81`, `110:2` | `lib/features/onboarding/phone_pin_screens.dart` |
| `110:25`, `110:42`, `110:59`, `110:74` | `lib/features/onboarding/role_screens.dart` |
| `59:2` | `lib/features/home/home_screen.dart` |
| `77:2` | `lib/features/report/fire_camera_screen.dart` |

Arabic locale and RTL apply globally. Material 3 supplies semantics and ink
responses; shared components use the inspected Figma colors, radii, spacing,
typography, and supplied SVG artwork. Dark green is `#0D514B`; canvas is
`#F6F8F7`. Amber is used for warnings/errors. Red is reserved for the emergency CTA.

Cairo was not originally present. Its variable font and OFL license are bundled
locally from the [official Google Fonts source](https://github.com/google/fonts/tree/main/ofl/cairo).
There is no runtime font download or typography package.

### Explicit differences and assumptions

- Responsive scrolling, safe insets, keyboard handling, and text scaling take
  precedence over absolute Figma coordinates. All frames are checked at 390×844
  and 320×568 with 1.5× text/reduced motion. The location benefits card expands
  to show all its text rather than reproducing clipped text in the reference.
- Camera viewports show actual device imagery, not Figma's placeholder imagery.
- Identity details are the supplied Figma fixture. The portrait is only a visual
  crop of the captured image, **not OCR, face detection, or portrait extraction**.
  There is no expiry-date field.
- Home uses the exact bundled illustrative map. Its marker is not geographically
  projected from GPS; the map has no provider, API key, pan, or live map data.
- The two SVGs with filter-based shadows (shutter and location marker) retain
  their exact circle geometry/shadow values through native vector painting, to
  avoid unsupported SVG filters and low-resolution raster edges. Original SVG
  and PNG exports are retained as references.
- Device text rasterization, emoji, system status bars and native permission
  sheets vary by platform. This is not a pixel-identical rendering of system UI.
- Motion is the requested Flutter enhancement, not motion extracted from Figma.
  Success uses a staged reveal of the supplied shield/check, not a newly drawn icon.
- No blocking splash was added. Welcome is usable immediately.
- Physical-device haptics, sustained 60fps profiling, and iOS visual/runtime QA
  still require real devices. No claim of measured 60fps is made.

## Architecture and mock boundaries

`main.dart` only initializes Flutter/system chrome and starts `FirePinApp`.
`AppServices` injects narrow service interfaces. A basic nested Navigator and
short native page routes own one in-memory `OnboardingSession`. No routing or
state-management package was added.

The following replaceable mocks live in
`lib/features/onboarding/onboarding_services.dart`:

- `MockIdentityVerificationService`: delays 1.5 seconds and returns fixture data.
  It does not verify authenticity, age, document validity, or identity.
- `MockOtpService`: sends no SMS; accepts `123456` after issuance for the current
  phone, rejects invalid codes, consumes a successful code, and supports resend.
- `MockVolunteerApplicationService`: returns local pending status; no council is
  contacted and no application is created remotely.
- `MockFireReportService`: sends no image, location, notification, or emergency
  report. It only simulates completion.

Future backend work must replace those implementations and define real session,
authentication/PIN, verification, consent, approval, and report-delivery contracts.
There is no invented client-side authenticity or server-authentication algorithm.

The PIN is private session memory only, never logged or persisted. Identity
images and coordinates are session-only. Native camera cache files are deleted
after their bytes are read; the app does not save to the gallery. A process
restart intentionally returns to onboarding; there is no durable account yet.

## Real device functionality and permissions

- `NativeDevicePermissions`: camera permission and app-settings access.
- `NativeCameraSource` / `LiveCamera`: rear-camera preview, still capture without
  audio, camera-only input, serialized initialization/capture/disposal, background
  suspension, resume, retry, and resource cleanup.
- `NativeLocationService`: foreground permission, enabled-service checks,
  current position with a 15-second timeout, denied/permanent-denial handling,
  and application/location settings. The Flutter app sends no coordinates.
  OS location providers retain their own platform-controlled behavior.
- Android: added `CAMERA`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, and
  optional camera hardware declaration. Existing Internet permission retained.
- iOS: added Arabic `NSCameraUsageDescription` and
  `NSLocationWhenInUseUsageDescription`; added Podfile permission macros and
  CocoaPods xcconfig includes. Existing iOS 13 target is preserved.
- No photo-library, gallery, microphone, or background-location permission added.

## Motion

- 260ms page fade with 12px rise; 120ms button press scale to 0.98.
- 190ms selection border/fill/radio transitions and 120ms digit reveal.
- 260ms restrained validation shake, staged success-circle/shield/title/chip
  reveals, and 40–60ms identity-field stagger.
- Captured-photo scanning uses an isolated CustomPainter, not a central spinner.
- Breathing effects are limited to camera framing/status, Home live/accuracy
  indicators, and pending state. Repaint boundaries isolate these visuals.
- Selective haptics accompany important actions. Reduced motion/accessibility
  settings suppress nonessential animations. Controllers, focus nodes, timers,
  text controllers, and camera resources are disposed.

## Dependencies added

| Dependency | Selected constraint | Why |
| --- | --- | --- |
| `camera` | `^0.12.1` | Native preview and still capture |
| `permission_handler` | `12.0.1` | Camera runtime permission/settings; 13.x requires Android SDK 37 |
| `geolocator` | `14.0.2` | Current location; 14.0.3 conflicts with existing secure-storage Windows dependencies |
| `flutter_svg` | `^2.3.0` | Exact bundled Figma vectors/map |
| `flutter_localizations` | Flutter SDK | Arabic Material/Cupertino localization |

No animation, routing, state-management, map, or font package was added. Existing
package versions and Flutter/Gradle/AGP/Kotlin tooling were not upgraded.
The installed Flutter 3.47.5 / Dart 3.13.4 toolchain was used; new dependency
resolution raises the lockfile's minimum SDK requirements without changing the
installed SDK or project build-tool versions. Generated desktop plugin registrants
were refreshed by Flutter; no desktop UI was implemented.

## Exact file inventory

### Created

```text
FRONTEND_IMPLEMENTATION.md
ios/Podfile
lib/app/app_services.dart
lib/core/services/camera_service.dart
lib/core/services/device_services.dart
lib/core/ui/components.dart
lib/core/ui/digit_input.dart
lib/core/ui/live_camera.dart
lib/core/ui/motion.dart
lib/features/home/home_screen.dart
lib/features/onboarding/identity_screens.dart
lib/features/onboarding/onboarding_flow.dart
lib/features/onboarding/onboarding_models.dart
lib/features/onboarding/onboarding_services.dart
lib/features/onboarding/permission_screens.dart
lib/features/onboarding/phone_pin_screens.dart
lib/features/onboarding/role_screens.dart
lib/features/report/fire_camera_screen.dart
test/onboarding_services_test.dart
test/screen_layout_test.dart
test/test_fakes.dart
assets/fonts/Cairo.ttf
assets/fonts/OFL.txt
assets/figma/account.svg
assets/figma/basemap.svg
assets/figma/camera.svg
assets/figma/camera_bottom_gradient.svg
assets/figma/camera_dot.svg
assets/figma/camera_top_gradient.svg
assets/figma/close.svg
assets/figma/id_corners.svg
assets/figma/identity_success.svg
assets/figma/info.svg
assets/figma/live_dot.svg
assets/figma/location.svg
assets/figma/location_bullet.svg
assets/figma/location_halo.svg
assets/figma/location_marker.png
assets/figma/location_marker.svg
assets/figma/nav_account.svg
assets/figma/nav_alerts.svg
assets/figma/nav_home.svg
assets/figma/notification.svg
assets/figma/pending.svg
assets/figma/phone.svg
assets/figma/phone_success.svg
assets/figma/portrait.svg
assets/figma/radio_dot.svg
assets/figma/radio_empty.svg
assets/figma/radio_selected.svg
assets/figma/requirement_dot.svg
assets/figma/shutter.png
assets/figma/shutter.svg
assets/figma/verified_shield.svg
assets/figma/warning.svg
```

### Modified

These three foundation files were already uncommitted/untracked at task start;
they were inspected and refactored, not treated as newly created work:

```text
lib/app/firepin_app.dart
lib/features/welcome/welcome_screen.dart
lib/theme/app_theme.dart
```

Other modified files:

```text
android/app/src/main/AndroidManifest.xml
ios/Flutter/Debug.xcconfig
ios/Flutter/Release.xcconfig
ios/Runner/Info.plist
lib/main.dart
macos/Flutter/GeneratedPluginRegistrant.swift
pubspec.lock
pubspec.yaml
test/widget_test.dart
windows/flutter/generated_plugin_registrant.cc
windows/flutter/generated_plugins.cmake
```

Build/test outputs and optional screenshots are ignored artifacts under `build/`
and `.dart_tool/visual_qa/`, not source additions. No files outside FirePinUI,
backend/database/Docker/env files, Git metadata, `api_client.dart`, or
`token_storage.dart` were edited.

## Validation commands and handoff

Final automated results:

- `dart format lib test`: passed; 26 Dart files formatted, no remaining changes.
- `flutter analyze`: passed, no issues found.
- `flutter test`: passed, all 25 tests.
- `git diff --check`: passed, no whitespace errors.
- `flutter build apk --debug --no-pub`: passed.
- Android manifest and iOS plist: parsed successfully as XML.
- Protected-file/backend diff check: no changes.

Android emulator smoke checks exercised native camera permission, rear preview,
ID capture/scan/review, phone/OTP/PIN, foreground location permission and actual
geolocator retrieval of a synthetic GPS fix, citizen Home, and both photo/no-photo
local reports returning to Home. Denying the optional OS location-accuracy prompt
was handled without a crash; retrying with an available location provider worked.
Scoped app logs contained no Flutter exceptions or fatal runtime errors in these
checks. A final visual review also caught and fixed system-bar contrast on the
Home → dark camera → Home transition, now covered by the widget regression test.

Commands run include:

```text
git status --short
git branch --show-current
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter test --dart-define=FIREPIN_VISUAL_QA=true
git diff --check
flutter run -d emulator-5554 --no-pub
flutter build apk --debug --no-pub
```

ADB was used to install/launch the debug APK, inspect screen semantics, take
screenshots, enter disposable demo values, supply a synthetic emulator GPS fix,
and inspect scoped process logs. The mock OTP is `123456`.

The tests use fake permission/camera/location services, never physical devices.
They cover OTP acceptance/rejection/resend, PIN confirmation and retry, Arabic
digits/phone validation, both complete onboarding branches, pending-state access
restriction, camera denial/settings/lifecycle, location denial/settings/skip,
camera and no-photo reporting, the shared incident lifecycle, role-specific
alerts/accounts, photo preview, small-screen keyboard interaction, and all
onboarding plus incident visual states at reference and accessible sizes.

iOS native build/runtime validation is not available in this Windows workspace.
Known Gradle/AGP/Kotlin deprecation warnings were left untouched.
