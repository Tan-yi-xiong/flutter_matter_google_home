/// Fabric target selected for the Google commissioning flow.
enum GoogleHomeMatterTarget {
  googleHomeFabric('googleHomeFabric'),
  androidLocalFabric('androidLocalFabric');

  const GoogleHomeMatterTarget(this.wireName);

  final String wireName;

  static GoogleHomeMatterTarget fromWireName(String value) {
    for (final target in values) {
      if (target.wireName == value) {
        return target;
      }
    }
    throw FormatException('Unknown Google Home Matter target: $value');
  }
}

/// The readiness of the Google Home Matter integration on this device.
enum GoogleHomeMatterAvailabilityStatus {
  ready('ready'),
  unsupportedPlatform('unsupportedPlatform'),
  androidTooOld('androidTooOld'),
  playServicesUnavailable('playServicesUnavailable'),
  playServicesTooOld('playServicesTooOld'),
  moduleUnavailable('moduleUnavailable'),
  sdkUnavailable('sdkUnavailable'),
  unknown('unknown');

  const GoogleHomeMatterAvailabilityStatus(this.wireName);

  final String wireName;

  static GoogleHomeMatterAvailabilityStatus fromWireName(String value) {
    for (final status in values) {
      if (status.wireName == value) {
        return status;
      }
    }
    return GoogleHomeMatterAvailabilityStatus.unknown;
  }
}

/// Availability information for Google Home Matter commissioning.
class GoogleHomeMatterAvailability {
  const GoogleHomeMatterAvailability({
    required this.isReady,
    required this.status,
    required this.message,
    this.playServicesVersion,
    this.minimumPlayServicesVersion,
  });

  factory GoogleHomeMatterAvailability.fromMap(Map<String, Object?> map) {
    return GoogleHomeMatterAvailability(
      isReady: map['isReady'] == true,
      status: GoogleHomeMatterAvailabilityStatus.fromWireName(
        map['status'] as String? ?? 'unknown',
      ),
      message: map['message'] as String? ?? '',
      playServicesVersion: map['playServicesVersion'] as String?,
      minimumPlayServicesVersion: map['minimumPlayServicesVersion'] as String?,
    );
  }

  final bool isReady;
  final GoogleHomeMatterAvailabilityStatus status;
  final String message;
  final String? playServicesVersion;
  final String? minimumPlayServicesVersion;

  static const GoogleHomeMatterAvailability unsupportedPlatform =
      GoogleHomeMatterAvailability(
        isReady: false,
        status: GoogleHomeMatterAvailabilityStatus.unsupportedPlatform,
        message: 'Google Home Matter commissioning is Android-only.',
      );

  @override
  String toString() {
    return 'GoogleHomeMatterAvailability('
        'isReady: $isReady, status: ${status.wireName}, '
        'message: $message, playServicesVersion: $playServicesVersion)';
  }
}

/// Result of requesting immediate delivery of the Play Services Home module.
class GoogleHomeMatterModuleInstallResult {
  const GoogleHomeMatterModuleInstallResult({
    required this.alreadyInstalled,
    this.sessionId,
  });

  factory GoogleHomeMatterModuleInstallResult.fromMap(
    Map<String, Object?> map,
  ) {
    return GoogleHomeMatterModuleInstallResult(
      alreadyInstalled: map['alreadyInstalled'] == true,
      sessionId: map['sessionId'] as int?,
    );
  }

  /// Whether the Home module was already installed on this device.
  final bool alreadyInstalled;

  /// Google Play Services module-install session id, when delivery started.
  final int? sessionId;

  @override
  String toString() {
    return 'GoogleHomeMatterModuleInstallResult('
        'alreadyInstalled: $alreadyInstalled, sessionId: $sessionId)';
  }
}

/// Stages where a Google Home Matter operation can fail.
enum GoogleHomeMatterFailureStage {
  availability('availability'),
  request('request'),
  userCancelled('userCancelled'),
  googleCommissioning('googleCommissioning'),
  handoff('handoff'),
  secondFabric('secondFabric'),
  finalization('finalization'),
  internal('internal');

  const GoogleHomeMatterFailureStage(this.wireName);

  final String wireName;

  static GoogleHomeMatterFailureStage fromWireName(String value) {
    for (final stage in values) {
      if (stage.wireName == value) {
        return stage;
      }
    }
    return GoogleHomeMatterFailureStage.internal;
  }
}

/// A sanitized failure returned by Google Home Matter commissioning.
class GoogleHomeMatterException implements Exception {
  const GoogleHomeMatterException({
    required this.stage,
    required this.message,
    this.googleApiStatusCode,
    this.secondFabricErrorCode,
    this.googleFabricSucceeded = false,
  });

  factory GoogleHomeMatterException.fromMap(Map<String, Object?> map) {
    return GoogleHomeMatterException(
      stage: GoogleHomeMatterFailureStage.fromWireName(
        map['stage'] as String? ?? 'internal',
      ),
      message:
          map['message'] as String? ?? 'Google Home Matter operation failed.',
      googleApiStatusCode: map['googleApiStatusCode'] as int?,
      secondFabricErrorCode: map['secondFabricErrorCode'] as int?,
      googleFabricSucceeded: map['googleFabricSucceeded'] == true,
    );
  }

  final GoogleHomeMatterFailureStage stage;
  final String message;
  final int? googleApiStatusCode;
  final int? secondFabricErrorCode;

  /// Whether the Google-side fabric was provisioned before a later stage failed.
  final bool googleFabricSucceeded;

  @override
  String toString() {
    return 'GoogleHomeMatterException('
        'stage: ${stage.wireName}, message: $message, '
        'googleApiStatusCode: $googleApiStatusCode, '
        'secondFabricErrorCode: $secondFabricErrorCode, '
        'googleFabricSucceeded: $googleFabricSucceeded)';
  }
}

/// Sensitive runtime data needed to continue commissioning another fabric.
///
/// Do not persist or log this object. [toString] intentionally redacts the
/// payload, network address, and passcode.
class GoogleHomeMatterHandoff {
  GoogleHomeMatterHandoff({
    required this.onboardingPayload,
    required this.address,
    required this.port,
    required this.setupPinCode,
    this.vendorId,
    this.productId,
  }) {
    if (onboardingPayload.isEmpty) {
      throw ArgumentError('onboardingPayload must not be empty.');
    }
    if (address.isEmpty) {
      throw ArgumentError('address must not be empty.');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be between 1 and 65535');
    }
    if (setupPinCode < 1 || setupPinCode > 99999998) {
      throw ArgumentError('setupPinCode must be between 1 and 99999998.');
    }
  }

  factory GoogleHomeMatterHandoff.fromMap(Map<String, Object?> map) {
    return GoogleHomeMatterHandoff(
      onboardingPayload: map['onboardingPayload'] as String,
      address: map['address'] as String,
      port: map['port'] as int,
      setupPinCode: map['setupPinCode'] as int,
      vendorId: map['vendorId'] as int?,
      productId: map['productId'] as int?,
    );
  }

  final String onboardingPayload;
  final String address;
  final int port;
  final int setupPinCode;
  final int? vendorId;
  final int? productId;

  @override
  String toString() {
    return 'GoogleHomeMatterHandoff('
        'onboardingPayload: <redacted>, address: <redacted>, port: $port, '
        'setupPinCode: <redacted>, vendorId: $vendorId, '
        'productId: $productId)';
  }
}

/// Successful result from the Google commissioning flow.
class GoogleHomeMatterResult {
  const GoogleHomeMatterResult({
    required this.target,
    required this.handoffUsed,
    this.deviceName,
    this.deviceIds = const <String>[],
    this.vendorId,
    this.productId,
  });

  factory GoogleHomeMatterResult.fromMap(Map<String, Object?> map) {
    final target = map['target'] as String?;
    if (target == null) {
      throw const FormatException('Missing Google Home Matter result target.');
    }
    final rawDeviceIds = map['deviceIds'];
    return GoogleHomeMatterResult(
      target: GoogleHomeMatterTarget.fromWireName(target),
      handoffUsed: map['handoffUsed'] == true,
      deviceName: map['deviceName'] as String?,
      deviceIds: rawDeviceIds is List
          ? rawDeviceIds.whereType<String>().toList(growable: false)
          : const <String>[],
      vendorId: map['vendorId'] as int?,
      productId: map['productId'] as int?,
    );
  }

  final GoogleHomeMatterTarget target;
  final bool handoffUsed;
  final String? deviceName;
  final List<String> deviceIds;
  final int? vendorId;
  final int? productId;

  @override
  String toString() {
    return 'GoogleHomeMatterResult('
        'target: ${target.wireName}, handoffUsed: $handoffUsed, '
        'deviceName: $deviceName, deviceIds: <redacted>, '
        'vendorId: $vendorId, productId: $productId)';
  }
}
