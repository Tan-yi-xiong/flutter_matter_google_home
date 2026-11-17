# Architecture

## Package boundary

`flutter_matter_google_home` owns only the Google commissioning segment. It does
not import or expose another Matter controller implementation.

```text
Host App
  ├─ flutter_matter_google_home
  │    └─ Google Play Services Commissioning API
  │         ├─ Google Home fabric, or
  │         └─ Android local fabric
  │
  └─ optional external commissioner
       └─ second Matter fabric
```

The two packages communicate only through the host application and the
`GoogleHomeMatterHandoff` value object.

## Commission-only flow

1. Dart calls `commission()` with an explicit target.
2. Android creates a `CommissioningRequest` without `CommissioningService`.
3. Google Play Services runs its hosted Matter commissioning UI and completes
   the target fabric.
4. The native ActivityResult is mapped to `GoogleHomeMatterResult`.

## Handoff flow

1. Dart calls `startHandoffSession()`.
2. Android creates a `CommissioningRequest` with the package's exported
   `CommissioningService`.
3. Google Play Services provisions the device onto the target network/fabric
   and then binds the package's exported service.
4. The service receives `CommissioningRequestMetadata` containing the
   operational address and passcode.
5. The native coordinator emits a `handoffReady` event without logging secrets.
6. The host app commissions the second fabric with any external commissioner.
7. The host app calls `completeHandoff`.
8. The service sends `sendCommissioningComplete` or `sendCommissioningError`.
9. Android maps the final ActivityResult to `session.result`.

The native coordinator clears its retained onboarding payload, handoff map, and
service reference as soon as the session reaches a terminal state. The Dart
handoff remains available only for the lifetime of the caller-owned session
object and must not be persisted.

The session must stay open until step 7. Completing the Google session before
the second fabric starts can close the commissionable window.

## State ownership

- Native owns the Google `IntentSender`, ActivityResult, and service delegate.
- Dart owns the public session lifecycle and handles native events by session ID.
- The host app owns all second-fabric state, node IDs, credentials, and
  controller persistence.
- No private fabric implementation exists in this package.
