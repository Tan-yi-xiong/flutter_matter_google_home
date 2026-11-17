# flutter_matter_google_home

Android-only Google Home Matter commissioning for Flutter, with an optional
handoff session for adding the same device to another Matter fabric.

This package is deliberately independent of `flutter_matter` and any private
commissioning implementation. A host app may depend on this package alone, or
combine it with another commissioner at the application layer.

## Capabilities

- `commission(...)`: Google-only commissioning. No handoff is exposed.
- `startHandoffSession(...)`: Google commissioning plus an in-memory handoff
  containing the operational address, port, passcode, and product metadata.
- `requestModuleInstall()`: proactively asks Google Play Services to deliver
  the optional Home module when `checkAvailability()` reports
  `moduleUnavailable`.
- Two explicit targets:
  - `googleHomeFabric`: adds the device to the Google Home ecosystem.
  - `androidLocalFabric`: uses Google Play Services' Android local fabric.

`googleHomeFabric` requires a compatible Matter Google Hub. `androidLocalFabric`
does not require a hub, but Google documents it as a development fabric rather
than a production Google Home cloud deployment.

## Requirements

- Flutter 3.41.0 or newer.
- Android 10 / API 29 or newer.
- The host Android app must use `minSdk 29` or newer and `compileSdk 36` or
  newer.
- Google Play Services `26.40.32` or newer.
- A physical Android device. Emulators are not supported by Google Home APIs.
- A Matter commissionee with an open commissioning window.
- For `googleHomeFabric`, a compatible Google Hub on the same network and a
  Google Home Developer Console project matching the device VID/PID.
- The Home APIs 1.11.1 Android SDK artifacts from Google.

The plugin declares the Play Services package-visibility queries and depends on
`play-services-home`; the `play-services-home` artifact's manifest contributes
the required `home:0:preferred` module-dependency service to the host app
during manifest merging. `checkAvailability()` also verifies that the Play
Services Home module is already installed and returns `moduleUnavailable`
while delivery is pending.

## Install

Use a Git tag after the repository has published one:

```yaml
dependencies:
  flutter_matter_google_home:
    git:
      url: https://github.com/Tan-yi-xiong/flutter_matter_google_home.git
      ref: v0.1.0-dev.1
```

The package does not depend on `flutter_matter`.

## Configure the Google SDK repository

Google distributes the Home APIs Android SDK separately from public Maven.
Download `home.android.sdk_1_11_1.zip` from the link in the
[Android SDK release notes](https://developers.home.google.com/apis/android/release-notes),
verify SHA-256
`9154ee88b3d93e7eafb85a1132043e281a14d1f60fc50913a4c230b34afafef4`,
unzip it, and point Gradle at the unzipped Maven repository root:

```bash
export GOOGLE_MATTER_SDK_REPO=/absolute/path/to/unzipped/repo
```

Alternatively set the same absolute path as a Gradle property:

```properties
googleMatterSdkRepo=/absolute/path/to/unzipped/repo
```

The host app must also expose that repository to its own Gradle resolution.
For a Flutter app using `allprojects { repositories { ... } }`:

```groovy
def googleMatterSdkRepo = providers.gradleProperty('googleMatterSdkRepo')
    .orElse(providers.environmentVariable('GOOGLE_MATTER_SDK_REPO'))
    .orNull

allprojects {
    repositories {
        google()
        mavenCentral()
        if (googleMatterSdkRepo != null) {
            maven { url = uri(googleMatterSdkRepo) }
        }
    }
}
```

Do not commit Google SDK artifacts, local Maven repositories, setup codes,
Wi-Fi credentials, certificates, private keys, or raw commissioning logs.

## Google-only commissioning

Both commissioning entry points use Google Play Services' hosted Matter
commissioning UI. This package does not render or replace that UI.

```dart
final commissioner = GoogleHomeMatterCommissioner();

final availability = await commissioner.checkAvailability();
if (!availability.isReady) {
  throw StateError(availability.message);
}

final result = await commissioner.commission(
  onboardingPayload: onboardingPayload,
  target: GoogleHomeMatterTarget.androidLocalFabric,
);
```

`target` is intentionally required. Choose `androidLocalFabric` only when a
local Google-managed development fabric is acceptable.

When `checkAvailability()` returns `moduleUnavailable`, the Home module has not
been delivered yet. Delivery normally completes in the background while the
device is online. To speed this up, call `requestModuleInstall()` to ask
Google Play Services to deliver the module immediately, then re-check
availability:

```dart
final install = await commissioner.requestModuleInstall();
// install.alreadyInstalled reports whether the module was already present.
```

## Handoff session

A handoff session stays open while the host app commissions the same device to
another fabric. The host must report the result only after its second
commissioner has actually completed or failed.

```dart
final session = await commissioner.startHandoffSession(
  onboardingPayload: onboardingPayload,
  target: GoogleHomeMatterTarget.androidLocalFabric,
  secondFabricTimeout: const Duration(seconds: 120),
);

final handoff = await session.handoff;

// Handoff fields:
// handoff.onboardingPayload
// handoff.address
// handoff.port
// handoff.setupPinCode
// handoff.vendorId
// handoff.productId

// Run the external commissioner here and await its terminal callback.
final secondFabricSucceeded = await runPrivateFabricCommissioning(handoff);
await session.completeHandoff(succeeded: secondFabricSucceeded);

final result = await session.result;
```

`runPrivateFabricCommissioning` above is a host-defined adapter. This package
does not import or call the private commissioner directly.

The package cannot verify the external commissioner's work. It trusts the
`completeHandoff` result and enforces strict aggregate completion semantics.
If the external fabric fails, pass `succeeded: false`; the session then fails
with `googleFabricSucceeded == true`.

## Handoff security

- `GoogleHomeMatterHandoff` is sensitive and in-memory only.
- Its `toString()` redacts the onboarding payload, address, and passcode.
- Never persist or log the object, its fields, or raw MethodChannel arguments.
- Do not put setup codes, passcodes, IP addresses, or credentials in reports.

## Package boundaries

This repository intentionally has no dependency on `flutter_matter` or another
private commissioner. Integration is performed by the host application:

1. Start this package's handoff session.
2. Use the private commissioner to join the second fabric.
3. Report the truthful second-fabric result to this package.
4. Await the final session result.

## Android local fabric limitation

Google documents the Android local fabric path as a development fabric. It is
scoped to the Android device and user, and devices must be commissioned
separately on other controllers. Use of this path in production is an accepted
integration risk, not a Google Home cloud deployment.

Google Home fabric requirements are documented in the
[Home APIs Android codelab](https://developers.home.google.com/codelabs/home-apis-android-build-mobile-app)
and [Connectivity guide](https://developers.home.google.com/apis/android/connectivity).
The no-hub local flow is described in the
[Matter Sample App codelab](https://developers.home.google.com/codelabs/matter-sample-app).

## Development

```bash
fvm flutter pub get
fvm flutter analyze --no-fatal-infos --no-fatal-warnings
fvm flutter test

cd example
fvm flutter pub get
fvm flutter test

export GOOGLE_MATTER_SDK_REPO=/absolute/path/to/unzipped/repo
fvm flutter build apk --debug
```

Run the Android Kotlin unit tests from `example/android`:

```bash
./gradlew :flutter_matter_google_home:testDebugUnitTest --no-daemon
```

## License

MIT. Google Home SDK artifacts are downloaded separately and retain Google's
applicable terms.
