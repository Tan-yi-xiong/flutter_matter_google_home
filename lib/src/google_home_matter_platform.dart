import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_google_home_matter.dart';

/// Platform boundary used by [GoogleHomeMatterCommissioner].
abstract class GoogleHomeMatterPlatform extends PlatformInterface {
  GoogleHomeMatterPlatform() : super(token: _token);

  static final Object _token = Object();

  static GoogleHomeMatterPlatform _instance = MethodChannelGoogleHomeMatter();

  static GoogleHomeMatterPlatform get instance => _instance;

  static set instance(GoogleHomeMatterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Native events for handoff-enabled sessions.
  Stream<Map<String, Object?>> get events;

  Future<Map<String, Object?>> checkAvailability();

  Future<Map<String, Object?>> commission({
    required String onboardingPayload,
    required String target,
  });

  Future<Map<String, Object?>> startHandoffSession({
    required String sessionId,
    required String onboardingPayload,
    required String target,
    required int secondFabricTimeoutSeconds,
  });

  Future<void> completeHandoff({
    required String sessionId,
    required bool succeeded,
    int? errorCode,
  });
}
