import 'dart:async';

import 'package:flutter/services.dart';

import 'google_home_matter_platform.dart';

/// Method channel implementation for the Android Google Home Matter plugin.
class MethodChannelGoogleHomeMatter extends GoogleHomeMatterPlatform {
  MethodChannelGoogleHomeMatter() {
    channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel channel = MethodChannel(
    'flutter_matter_google_home',
  );

  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<Map<String, Object?>> checkAvailability() async {
    return _asStringMap(
      await channel.invokeMethod<Object?>('checkAvailability'),
    );
  }

  @override
  Future<Map<String, Object?>> commission({
    required String onboardingPayload,
    required String target,
  }) async {
    final raw = await channel.invokeMethod<Object?>(
      'commission',
      <String, Object?>{
        'onboardingPayload': onboardingPayload,
        'target': target,
      },
    );
    return _asStringMap(raw);
  }

  @override
  Future<Map<String, Object?>> startHandoffSession({
    required String sessionId,
    required String onboardingPayload,
    required String target,
    required int secondFabricTimeoutSeconds,
  }) async {
    final raw = await channel
        .invokeMethod<Object?>('startHandoffSession', <String, Object?>{
          'sessionId': sessionId,
          'onboardingPayload': onboardingPayload,
          'target': target,
          'secondFabricTimeoutSeconds': secondFabricTimeoutSeconds,
        });
    return _asStringMap(raw);
  }

  @override
  Future<void> completeHandoff({
    required String sessionId,
    required bool succeeded,
    int? errorCode,
  }) async {
    await channel.invokeMethod<void>('completeHandoff', <String, Object?>{
      'sessionId': sessionId,
      'succeeded': succeeded,
      'errorCode': errorCode,
    });
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'sessionEvent') {
      throw MissingPluginException(
        'Unsupported Google Home Matter native method: ${call.method}',
      );
    }
    final event = _asStringMap(call.arguments);
    _events.add(event);
    return null;
  }

  Map<String, Object?> _asStringMap(Object? raw) {
    if (raw == null) {
      return <String, Object?>{};
    }
    if (raw is Map<String, Object?>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>(key?.toString() ?? '', value),
      );
    }
    throw PlatformException(
      code: 'INVALID_NATIVE_RESPONSE',
      message: 'Expected a map from Google Home Matter native code.',
    );
  }
}
