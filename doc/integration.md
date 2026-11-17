# Integration

## Google-only

```dart
final commissioner = GoogleHomeMatterCommissioner();
final result = await commissioner.commission(
  onboardingPayload: payload,
  target: GoogleHomeMatterTarget.androidLocalFabric,
);
```

## Google plus another fabric

```dart
final session = await commissioner.startHandoffSession(
  onboardingPayload: payload,
  target: GoogleHomeMatterTarget.androidLocalFabric,
);

final handoff = await session.handoff;

// Start the external commissioner and await its terminal CompletionListener.
// Do not report success immediately after a start/commission call returns.
await session.completeHandoff(
  succeeded: secondFabricSucceeded,
  errorCode: secondFabricSucceeded ? null : privateErrorCode,
);

final result = await session.result;
```

## Required host responsibilities

- Keep the onboarding payload and handoff in memory only.
- Parse any additional setup data required by the external commissioner.
- Validate vendor/product data if the external commissioner relies on it.
- Await the external commissioner's actual terminal callback.
- Report failure with `completeHandoff(succeeded: false, errorCode: value)`.
- Do not persist handoff fields or include them in logs or evidence.

`secondFabricSucceeded` and `privateErrorCode` are host-defined values from the
private commissioner adapter. They are never inferred by this package.

The adapter should map the handoff explicitly rather than sharing package
objects:

```dart
Future<bool> runPrivateFabricCommissioning(GoogleHomeMatterHandoff handoff) async {
  // Replace this call with the private commissioner's actual existing-device
  // commissioning API. The private package must not depend on this package.
  return privateCommissioner.commissionExistingDevice(
    onboardingPayload: handoff.onboardingPayload,
    address: handoff.address,
    port: handoff.port,
    setupPinCode: handoff.setupPinCode,
    vendorId: handoff.vendorId,
    productId: handoff.productId,
  );
}
```
