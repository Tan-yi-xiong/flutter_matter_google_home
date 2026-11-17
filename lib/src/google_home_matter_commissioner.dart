import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'google_home_matter_models.dart';
import 'google_home_matter_platform.dart';
import 'google_home_matter_session.dart';

/// Entry point for Google Home Matter commissioning on Android.
class GoogleHomeMatterCommissioner {
  GoogleHomeMatterCommissioner()
    : _platform = GoogleHomeMatterPlatform.instance;

  final GoogleHomeMatterPlatform _platform;
  bool _operationInProgress = false;

  /// Checks whether Google Home Matter commissioning can run on this device.
  Future<GoogleHomeMatterAvailability> checkAvailability() async {
    if (!_isAndroid) {
      return GoogleHomeMatterAvailability.unsupportedPlatform;
    }
    try {
      return GoogleHomeMatterAvailability.fromMap(
        await _platform.checkAvailability(),
      );
    } on PlatformException catch (error) {
      return GoogleHomeMatterAvailability(
        isReady: false,
        status: GoogleHomeMatterAvailabilityStatus.sdkUnavailable,
        message: error.message ?? 'Unable to check Google Home availability.',
      );
    } catch (_) {
      return const GoogleHomeMatterAvailability(
        isReady: false,
        status: GoogleHomeMatterAvailabilityStatus.sdkUnavailable,
        message: 'Unable to check Google Home availability.',
      );
    }
  }

  /// Runs Google commissioning without exposing a handoff or waiting for a
  /// second fabric.
  Future<GoogleHomeMatterResult> commission({
    required String onboardingPayload,
    required GoogleHomeMatterTarget target,
  }) async {
    _ensureAndroid();
    _validatePayload(onboardingPayload);
    _beginOperation();
    try {
      final result = await _platform.commission(
        onboardingPayload: onboardingPayload,
        target: target.wireName,
      );
      return GoogleHomeMatterResult.fromMap(result);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    } catch (_) {
      throw const GoogleHomeMatterException(
        stage: GoogleHomeMatterFailureStage.internal,
        message: 'Google Home Matter commissioning failed.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  /// Starts Google commissioning and exposes a handoff for a second fabric.
  ///
  /// The returned session remains open until [GoogleHomeMatterSession.result]
  /// completes. Call [GoogleHomeMatterSession.completeHandoff] only after the
  /// second fabric operation has actually completed.
  Future<GoogleHomeMatterSession> startHandoffSession({
    required String onboardingPayload,
    required GoogleHomeMatterTarget target,
    Duration secondFabricTimeout = const Duration(seconds: 120),
  }) async {
    _ensureAndroid();
    _validatePayload(onboardingPayload);
    if (secondFabricTimeout < const Duration(seconds: 1) ||
        secondFabricTimeout > const Duration(minutes: 10)) {
      throw ArgumentError.value(
        secondFabricTimeout,
        'secondFabricTimeout',
        'Must be between 1 second and 10 minutes',
      );
    }
    _beginOperation();

    final sessionId = _createSessionId();
    final session = _MethodChannelGoogleHomeMatterSession(
      platform: _platform,
      sessionId: sessionId,
      onFinished: () {
        _operationInProgress = false;
      },
    );
    try {
      await _platform.startHandoffSession(
        sessionId: sessionId,
        onboardingPayload: onboardingPayload,
        target: target.wireName,
        secondFabricTimeoutSeconds: secondFabricTimeout.inSeconds,
      );
      return session;
    } on PlatformException catch (error) {
      final mapped = _mapPlatformException(error);
      session.abandonBeforeStart();
      throw mapped;
    } catch (_) {
      session.abandonBeforeStart();
      throw const GoogleHomeMatterException(
        stage: GoogleHomeMatterFailureStage.request,
        message: 'Unable to start Google Home Matter handoff session.',
      );
    } finally {
      if (session.isFinished) {
        _operationInProgress = false;
      }
    }
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  void _ensureAndroid() {
    if (!_isAndroid) {
      throw const GoogleHomeMatterException(
        stage: GoogleHomeMatterFailureStage.availability,
        message: 'Google Home Matter commissioning is Android-only.',
      );
    }
  }

  void _validatePayload(String onboardingPayload) {
    if (onboardingPayload.isEmpty) {
      throw ArgumentError.value(
        onboardingPayload,
        'onboardingPayload',
        'Must not be empty',
      );
    }
  }

  void _beginOperation() {
    if (_operationInProgress) {
      throw const GoogleHomeMatterException(
        stage: GoogleHomeMatterFailureStage.request,
        message: 'Another Google Home Matter operation is already in progress.',
      );
    }
    _operationInProgress = true;
  }

  String _createSessionId() {
    final random = Random.secure().nextInt(1 << 32);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${random.toRadixString(36)}';
  }
}

class _MethodChannelGoogleHomeMatterSession implements GoogleHomeMatterSession {
  _MethodChannelGoogleHomeMatterSession({
    required this.platform,
    required this.sessionId,
    required this.onFinished,
  }) {
    _subscription = platform.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        _fail(
          const GoogleHomeMatterException(
            stage: GoogleHomeMatterFailureStage.internal,
            message: 'The Google Home Matter native event stream failed.',
          ),
        );
      },
    );
    // A caller may await only `result`; keep the sibling `handoff` future from
    // surfacing as an unhandled asynchronous error.
    unawaited(
      _handoffCompleter.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      ),
    );
    unawaited(
      _resultCompleter.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      ),
    );
  }

  final GoogleHomeMatterPlatform platform;
  final String sessionId;
  final void Function() onFinished;
  final Completer<GoogleHomeMatterHandoff> _handoffCompleter =
      Completer<GoogleHomeMatterHandoff>();
  final Completer<GoogleHomeMatterResult> _resultCompleter =
      Completer<GoogleHomeMatterResult>();
  StreamSubscription<Map<String, Object?>>? _subscription;
  bool _handoffReady = false;
  bool _reported = false;
  bool _reporting = false;
  bool _finished = false;

  bool get isFinished => _finished;

  @override
  Future<GoogleHomeMatterHandoff> get handoff => _handoffCompleter.future;

  @override
  Future<GoogleHomeMatterResult> get result => _resultCompleter.future;

  @override
  Future<void> completeHandoff({
    required bool succeeded,
    int? errorCode,
  }) async {
    if (!_handoffReady) {
      throw StateError('The handoff is not ready yet.');
    }
    if (_reported || _reporting) {
      throw StateError('The handoff result has already been reported.');
    }
    if (_finished) {
      throw StateError('The Google Home Matter session has already finished.');
    }
    _reporting = true;
    try {
      try {
        await platform.completeHandoff(
          sessionId: sessionId,
          succeeded: succeeded,
          errorCode: errorCode,
        );
      } on PlatformException catch (error) {
        throw _mapPlatformException(error);
      } catch (_) {
        throw const GoogleHomeMatterException(
          stage: GoogleHomeMatterFailureStage.finalization,
          message: 'Unable to report the second-fabric result.',
        );
      }
      _reported = true;
    } finally {
      _reporting = false;
    }
  }

  void abandonBeforeStart() {
    _finished = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _handleEvent(Map<String, Object?> event) {
    if (event['sessionId'] != sessionId) {
      return;
    }
    try {
      switch (event['type']) {
        case 'handoffReady':
          final payload = _asStringMap(event['handoff']);
          if (payload.isEmpty || _handoffReady) {
            return;
          }
          _handoffReady = true;
          _handoffCompleter.complete(GoogleHomeMatterHandoff.fromMap(payload));
        case 'completed':
          final payload = _asStringMap(event['result']);
          if (payload.isEmpty) {
            _fail(
              const GoogleHomeMatterException(
                stage: GoogleHomeMatterFailureStage.finalization,
                message: 'Google Home Matter returned an empty result.',
              ),
            );
            return;
          }
          _complete(GoogleHomeMatterResult.fromMap(payload));
        case 'failed':
          final errorPayload = _asStringMap(event['error']);
          _fail(
            errorPayload.isEmpty
                ? const GoogleHomeMatterException(
                    stage: GoogleHomeMatterFailureStage.internal,
                    message: 'Google Home Matter session failed.',
                  )
                : GoogleHomeMatterException.fromMap(errorPayload),
          );
      }
    } catch (_) {
      _fail(
        const GoogleHomeMatterException(
          stage: GoogleHomeMatterFailureStage.internal,
          message: 'Google Home Matter returned an invalid session event.',
        ),
      );
    }
  }

  void _complete(GoogleHomeMatterResult result) {
    if (_finished) {
      return;
    }
    _finished = true;
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.complete(result);
    }
    _finish();
  }

  void _fail(GoogleHomeMatterException error) {
    if (_finished) {
      return;
    }
    _finished = true;
    if (!_handoffCompleter.isCompleted) {
      _handoffCompleter.completeError(error, StackTrace.current);
    }
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError(error, StackTrace.current);
    }
    _finish();
  }

  void _finish() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    onFinished();
  }

  Map<String, Object?> _asStringMap(Object? raw) {
    if (raw is Map<String, Object?>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>(key?.toString() ?? '', value),
      );
    }
    return <String, Object?>{};
  }
}

GoogleHomeMatterException _mapPlatformException(PlatformException error) {
  final details = _asStringMap(error.details);
  if (details.isNotEmpty) {
    return GoogleHomeMatterException.fromMap(details);
  }
  final stage = switch (error.code) {
    'GOOGLE_HOME_MATTER_BUSY' ||
    'GOOGLE_HOME_MATTER_BAD_ARGS' => GoogleHomeMatterFailureStage.request,
    'GOOGLE_HOME_MATTER_USER_CANCELLED' =>
      GoogleHomeMatterFailureStage.userCancelled,
    'GOOGLE_HOME_MATTER_SESSION_NOT_READY' ||
    'GOOGLE_HOME_MATTER_SESSION_NOT_FOUND' ||
    'GOOGLE_HOME_MATTER_COMPLETE_ALREADY_REPORTED' =>
      GoogleHomeMatterFailureStage.handoff,
    _ => GoogleHomeMatterFailureStage.internal,
  };
  return GoogleHomeMatterException(
    stage: stage,
    message: error.message ?? 'Google Home Matter operation failed.',
  );
}

Map<String, Object?> _asStringMap(Object? raw) {
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map<String, Object?>(
      (Object? key, Object? value) =>
          MapEntry<String, Object?>(key?.toString() ?? '', value),
    );
  }
  return <String, Object?>{};
}
