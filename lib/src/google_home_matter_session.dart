import 'google_home_matter_models.dart';

/// A handoff-enabled Google commissioning operation.
///
/// The session remains open after [handoff] becomes available. The caller must
/// finish the second fabric and report the truthful result through
/// [completeHandoff].
abstract class GoogleHomeMatterSession {
  Future<GoogleHomeMatterHandoff> get handoff;

  /// Reports the terminal result of the host's second-fabric operation.
  ///
  /// [errorCode] is retained by this package and exposed through
  /// [GoogleHomeMatterException.secondFabricErrorCode]. It is not interpreted
  /// as a Google Play Services error code.
  Future<void> completeHandoff({required bool succeeded, int? errorCode});

  Future<GoogleHomeMatterResult> get result;
}
