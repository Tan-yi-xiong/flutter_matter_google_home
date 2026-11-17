# Repository Instructions

This repository is the standalone Android plugin
`flutter_matter_google_home`.

## Boundaries

- Do not add a dependency on `flutter_matter` or any private Matter
  commissioner.
- The package may expose a handoff, but must not implement a second fabric.
- Never commit Google Home SDK artifacts, local Maven repositories, `.aar`
  files, onboarding payloads, Wi-Fi credentials, passcodes, IP addresses,
  certificates, private keys, or raw logs.
- Keep `googleHomeFabric` and `androidLocalFabric` explicit; do not add a
  default target.

## Commands

```bash
fvm flutter pub get
fvm flutter analyze --no-fatal-infos --no-fatal-warnings
fvm flutter test

cd example
fvm flutter pub get
fvm flutter test
export GOOGLE_MATTER_SDK_REPO=/absolute/path/to/unzipped/repo
fvm flutter build apk --debug
cd android
./gradlew :flutter_matter_google_home:testDebugUnitTest --no-daemon
```

Google Home SDK `1.11.1 / play-services-home(-types) 17.1.0` is downloaded
separately. The plugin uses Kotlin 2.4.0, Java 17, minSdk 29, and compileSdk 36.
