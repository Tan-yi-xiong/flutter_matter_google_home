import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_matter_google_home/flutter_matter_google_home.dart';
import 'package:flutter_matter_google_home/src/method_channel_google_home_matter.dart';
import 'package:flutter_matter_google_home/src/google_home_matter_platform.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeGoogleHomeMatterPlatform
    with MockPlatformInterfaceMixin
    implements GoogleHomeMatterPlatform {
  final StreamController<Map<String, Object?>> controller =
      StreamController<Map<String, Object?>>.broadcast();

  Map<String, Object?> availability = <String, Object?>{
    'isReady': true,
    'status': 'ready',
    'message': 'ready',
    'playServicesVersion': '26.40.32',
    'minimumPlayServicesVersion': '26.40.32',
  };
  Map<String, Object?> commissionResult = <String, Object?>{
    'target': 'androidLocalFabric',
    'handoffUsed': false,
    'deviceName': 'Light',
    'deviceIds': <String>['device-1'],
    'vendorId': 1,
    'productId': 2,
  };

  String? lastOnboardingPayload;
  String? lastTarget;
  String? lastSessionId;
  int? lastTimeoutSeconds;
  bool? lastHandoffSucceeded;
  int? lastHandoffErrorCode;

  @override
  Stream<Map<String, Object?>> get events => controller.stream;

  @override
  Future<Map<String, Object?>> checkAvailability() async => availability;

  @override
  Future<Map<String, Object?>> commission({
    required String onboardingPayload,
    required String target,
  }) async {
    lastOnboardingPayload = onboardingPayload;
    lastTarget = target;
    return commissionResult;
  }

  @override
  Future<Map<String, Object?>> startHandoffSession({
    required String sessionId,
    required String onboardingPayload,
    required String target,
    required int secondFabricTimeoutSeconds,
  }) async {
    lastSessionId = sessionId;
    lastOnboardingPayload = onboardingPayload;
    lastTarget = target;
    lastTimeoutSeconds = secondFabricTimeoutSeconds;
    return <String, Object?>{'sessionId': sessionId};
  }

  @override
  Future<void> completeHandoff({
    required String sessionId,
    required bool succeeded,
    int? errorCode,
  }) async {
    lastSessionId = sessionId;
    lastHandoffSucceeded = succeeded;
    lastHandoffErrorCode = errorCode;
  }

  void emit(Map<String, Object?> event) => controller.add(event);

  Future<void> close() => controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGoogleHomeMatterPlatform platform;
  late GoogleHomeMatterCommissioner commissioner;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = FakeGoogleHomeMatterPlatform();
    GoogleHomeMatterPlatform.instance = platform;
    commissioner = GoogleHomeMatterCommissioner();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await platform.close();
    GoogleHomeMatterPlatform.instance = MethodChannelGoogleHomeMatter();
  });

  test('returns unsupported platform without invoking native code', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final availability = await commissioner.checkAvailability();
    expect(availability.isReady, isFalse);
    expect(
      availability.status,
      GoogleHomeMatterAvailabilityStatus.unsupportedPlatform,
    );
  });

  test('maps native availability', () async {
    final availability = await commissioner.checkAvailability();
    expect(availability.isReady, isTrue);
    expect(availability.status, GoogleHomeMatterAvailabilityStatus.ready);
    expect(availability.playServicesVersion, '26.40.32');
  });

  test('maps module delivery availability', () async {
    platform.availability = <String, Object?>{
      'isReady': false,
      'status': 'moduleUnavailable',
      'message': 'module pending',
    };

    final availability = await commissioner.checkAvailability();
    expect(availability.isReady, isFalse);
    expect(
      availability.status,
      GoogleHomeMatterAvailabilityStatus.moduleUnavailable,
    );
  });

  test('runs standalone commissioning with an explicit target', () async {
    final result = await commissioner.commission(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );

    expect(platform.lastOnboardingPayload, 'MT:payload');
    expect(platform.lastTarget, 'androidLocalFabric');
    expect(result.target, GoogleHomeMatterTarget.androidLocalFabric);
    expect(result.handoffUsed, isFalse);
    expect(result.deviceName, 'Light');
  });

  test('completes a handoff session after a truthful second result', () async {
    final session = await commissioner.startHandoffSession(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.googleHomeFabric,
      secondFabricTimeout: const Duration(minutes: 2),
    );

    platform.emit(<String, Object?>{
      'type': 'handoffReady',
      'sessionId': platform.lastSessionId,
      'handoff': <String, Object?>{
        'onboardingPayload': 'MT:payload',
        'address': 'commissionee.local',
        'port': 5540,
        'setupPinCode': 12345678,
        'vendorId': 1,
        'productId': 2,
        'deviceType': 256,
      },
    });

    final handoff = await session.handoff;
    expect(handoff.address, 'commissionee.local');
    expect(handoff.setupPinCode, 12345678);
    await session.completeHandoff(succeeded: true);

    platform.emit(<String, Object?>{
      'type': 'completed',
      'sessionId': platform.lastSessionId,
      'result': <String, Object?>{
        'target': 'googleHomeFabric',
        'handoffUsed': true,
        'deviceName': 'Light',
        'deviceIds': <String>['device-1'],
        'vendorId': 1,
        'productId': 2,
      },
    });

    final result = await session.result;
    expect(result.target, GoogleHomeMatterTarget.googleHomeFabric);
    expect(result.handoffUsed, isTrue);
    expect(platform.lastHandoffSucceeded, isTrue);

    final nextResult = await commissioner.commission(
      onboardingPayload: 'MT:next-payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );
    expect(nextResult.target, GoogleHomeMatterTarget.androidLocalFabric);
  });

  test('strictly aggregates a reported second-fabric failure', () async {
    final session = await commissioner.startHandoffSession(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );

    platform.emit(<String, Object?>{
      'type': 'handoffReady',
      'sessionId': platform.lastSessionId,
      'handoff': <String, Object?>{
        'onboardingPayload': 'MT:payload',
        'address': 'commissionee.local',
        'port': 5540,
        'setupPinCode': 12345678,
        'vendorId': 1,
        'productId': 2,
      },
    });
    await session.handoff;
    await session.completeHandoff(succeeded: false, errorCode: 42);

    platform.emit(<String, Object?>{
      'type': 'failed',
      'sessionId': platform.lastSessionId,
      'error': <String, Object?>{
        'stage': 'secondFabric',
        'message': 'second fabric failed',
        'secondFabricErrorCode': 42,
        'googleFabricSucceeded': true,
      },
    });

    await expectLater(
      session.result,
      throwsA(
        isA<GoogleHomeMatterException>()
            .having(
              (error) => error.stage,
              'stage',
              GoogleHomeMatterFailureStage.secondFabric,
            )
            .having(
              (error) => error.googleFabricSucceeded,
              'googleFabricSucceeded',
              isTrue,
            )
            .having(
              (error) => error.secondFabricErrorCode,
              'secondFabricErrorCode',
              42,
            ),
      ),
    );
    expect(platform.lastHandoffSucceeded, isFalse);
    expect(platform.lastHandoffErrorCode, 42);
  });

  test('rejects concurrent operations', () async {
    await commissioner.startHandoffSession(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );

    await expectLater(
      commissioner.commission(
        onboardingPayload: 'MT:payload',
        target: GoogleHomeMatterTarget.androidLocalFabric,
      ),
      throwsA(
        isA<GoogleHomeMatterException>().having(
          (error) => error.stage,
          'stage',
          GoogleHomeMatterFailureStage.request,
        ),
      ),
    );
  });

  test('rejects an out-of-range second-fabric timeout', () async {
    await expectLater(
      commissioner.startHandoffSession(
        onboardingPayload: 'MT:payload',
        target: GoogleHomeMatterTarget.androidLocalFabric,
        secondFabricTimeout: const Duration(milliseconds: 500),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('redacts sensitive handoff values from toString', () {
    final handoff = GoogleHomeMatterHandoff(
      onboardingPayload: 'MT:secret-payload',
      address: 'commissionee.local',
      port: 5540,
      setupPinCode: 12345678,
      vendorId: 1,
      productId: 2,
    );

    final text = handoff.toString();
    expect(text, isNot(contains('secret-payload')));
    expect(text, isNot(contains('commissionee.local')));
    expect(text, isNot(contains('12345678')));
    expect(text, contains('<redacted>'));
  });

  test('redacts device identifiers from result toString', () {
    const result = GoogleHomeMatterResult(
      target: GoogleHomeMatterTarget.androidLocalFabric,
      handoffUsed: false,
      deviceName: 'Light',
      deviceIds: <String>['device-secret-id'],
    );

    expect(result.toString(), isNot(contains('device-secret-id')));
    expect(result.toString(), contains('<redacted>'));
  });

  test('fails the session on a malformed handoff event', () async {
    final session = await commissioner.startHandoffSession(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );

    platform.emit(<String, Object?>{
      'type': 'handoffReady',
      'sessionId': platform.lastSessionId,
      'handoff': <String, Object?>{
        'onboardingPayload': 'MT:payload',
        'port': 5540,
        'setupPinCode': 12345678,
      },
    });

    await expectLater(
      session.handoff,
      throwsA(
        isA<GoogleHomeMatterException>().having(
          (error) => error.stage,
          'stage',
          GoogleHomeMatterFailureStage.internal,
        ),
      ),
    );
  });

  test('does not default a missing result target', () async {
    final session = await commissioner.startHandoffSession(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );

    platform.emit(<String, Object?>{
      'type': 'completed',
      'sessionId': platform.lastSessionId,
      'result': <String, Object?>{'handoffUsed': true},
    });

    await expectLater(
      session.result,
      throwsA(
        isA<GoogleHomeMatterException>().having(
          (error) => error.stage,
          'stage',
          GoogleHomeMatterFailureStage.internal,
        ),
      ),
    );
  });

  test('rejects a handoff before it is ready', () async {
    final session = await commissioner.startHandoffSession(
      onboardingPayload: 'MT:payload',
      target: GoogleHomeMatterTarget.androidLocalFabric,
    );

    await expectLater(
      session.completeHandoff(succeeded: true),
      throwsA(isA<StateError>()),
    );
  });
}
