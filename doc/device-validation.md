# Device validation checklist

## Prerequisites

- Physical Android 10+ device with Google Play Services `26.40.32` or newer.
- Matter commissionee with a fresh, open commissioning window.
- Google Home Developers project matching the commissionee VID/PID.
- Google Home SDK 1.11.1 artifacts configured through `GOOGLE_MATTER_SDK_REPO`.
- For the Google Home target only: compatible Matter Hub on the same network.

## Required checks

1. Availability returns `ready`.
   If it returns `moduleUnavailable`, call `requestModuleInstall()` to ask
   Play Services to deliver the Home module immediately (or keep the device
   online and wait for background delivery), then retry availability.
   A checker timeout reports `unknown` instead of `moduleUnavailable` and can
   simply be retried.
2. `commission(androidLocalFabric)` completes with a real commissionee.
3. `startHandoffSession(androidLocalFabric)` emits a handoff with a reachable
   address, positive port, and passcode.
4. Reporting second-fabric success yields a completed session.
5. Reporting second-fabric failure yields `secondFabric` with
   `googleFabricSucceeded == true`.
6. Back/cancel in Google UI yields `userCancelled` and no completed session.
7. Invalid payload or unavailable Play Services yields a typed failure.
8. A session with no second-fabric report times out and sends an error to
   Google Play Services.
9. No setup code, Wi-Fi credential, passcode, IP address, certificate, key, or
   device identifier appears in logs or evidence.
10. `googleHomeFabric` remains untested and blocked until a compatible Hub is
    available.

Use `example/` as the validation host. The example intentionally has no
dependency on another Matter commission implementation.
