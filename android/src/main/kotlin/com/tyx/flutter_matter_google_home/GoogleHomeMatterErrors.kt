package com.tyx.flutter_matter_google_home

internal fun googleHomeMatterErrorMap(
    stage: String,
    message: String,
    googleApiStatusCode: Int? = null,
    secondFabricErrorCode: Int? = null,
    googleFabricSucceeded: Boolean = false,
): Map<String, Any?> = mapOf(
    "stage" to stage,
    "message" to message,
    "googleApiStatusCode" to googleApiStatusCode,
    "secondFabricErrorCode" to secondFabricErrorCode,
    "googleFabricSucceeded" to googleFabricSucceeded,
)

internal object GoogleHomeMatterErrorCodes {
    const val BUSY = "GOOGLE_HOME_MATTER_BUSY"
    const val BAD_ARGS = "GOOGLE_HOME_MATTER_BAD_ARGS"
    const val ACTIVITY_UNAVAILABLE = "GOOGLE_HOME_MATTER_ACTIVITY_UNAVAILABLE"
    const val REQUEST_FAILED = "GOOGLE_HOME_MATTER_REQUEST_FAILED"
    const val USER_CANCELLED = "GOOGLE_HOME_MATTER_USER_CANCELLED"
    const val SESSION_NOT_READY = "GOOGLE_HOME_MATTER_SESSION_NOT_READY"
    const val SESSION_NOT_FOUND = "GOOGLE_HOME_MATTER_SESSION_NOT_FOUND"
    const val COMPLETE_ALREADY_REPORTED = "GOOGLE_HOME_MATTER_COMPLETE_ALREADY_REPORTED"
    const val INTERNAL = "GOOGLE_HOME_MATTER_INTERNAL"
}
