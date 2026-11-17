import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_matter_google_home/src/method_channel_google_home_matter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_matter_google_home');
  late MethodChannelGoogleHomeMatter platform;
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    platform = MethodChannelGoogleHomeMatter();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return switch (call.method) {
            'checkAvailability' => <String, Object?>{
              'isReady': true,
              'status': 'ready',
              'message': 'ready',
            },
            'commission' => <String, Object?>{
              'target': 'androidLocalFabric',
              'handoffUsed': false,
            },
            'startHandoffSession' => <String, Object?>{
              'sessionId': 'session-1',
            },
            'requestModuleInstall' => <String, Object?>{
              'alreadyInstalled': true,
            },
            'completeHandoff' => null,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps availability and commissioning method calls', () async {
    final availability = await platform.checkAvailability();
    expect(availability['status'], 'ready');

    final result = await platform.commission(
      onboardingPayload: 'MT:payload',
      target: 'androidLocalFabric',
    );
    expect(result['handoffUsed'], isFalse);
    expect(calls.map((call) => call.method), <String>[
      'checkAvailability',
      'commission',
    ]);
    expect(calls.last.arguments, <String, Object?>{
      'onboardingPayload': 'MT:payload',
      'target': 'androidLocalFabric',
    });
  });

  test('starts and completes a handoff session', () async {
    final started = await platform.startHandoffSession(
      sessionId: 'session-1',
      onboardingPayload: 'MT:payload',
      target: 'googleHomeFabric',
      secondFabricTimeoutSeconds: 120,
    );
    expect(started['sessionId'], 'session-1');

    await platform.completeHandoff(
      sessionId: 'session-1',
      succeeded: false,
      errorCode: 9,
    );

    expect(calls.map((call) => call.method), <String>[
      'startHandoffSession',
      'completeHandoff',
    ]);
    expect(calls.last.arguments, <String, Object?>{
      'sessionId': 'session-1',
      'succeeded': false,
      'errorCode': 9,
    });
  });

  test('maps requestModuleInstall method calls', () async {
    final result = await platform.requestModuleInstall();

    expect(result, <String, Object?>{'alreadyInstalled': true});
    expect(calls.last.method, 'requestModuleInstall');
    expect(calls.last.arguments, isNull);
  });
}
