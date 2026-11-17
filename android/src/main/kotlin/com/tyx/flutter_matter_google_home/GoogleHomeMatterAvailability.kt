package com.tyx.flutter_matter_google_home

import android.content.Context
import android.os.Build
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.home.matter.Matter

internal data class GoogleHomeMatterAvailabilityResult(
    val isReady: Boolean,
    val status: String,
    val message: String,
    val playServicesVersion: String?,
    val minimumPlayServicesVersion: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "isReady" to isReady,
        "status" to status,
        "message" to message,
        "playServicesVersion" to playServicesVersion,
        "minimumPlayServicesVersion" to minimumPlayServicesVersion,
    )
}

internal object GoogleHomeMatterAvailabilityChecker {
    const val MINIMUM_PLAY_SERVICES_VERSION = "26.40.32"
    private const val MINIMUM_ANDROID_API = 29

    fun check(
        context: Context,
        onResult: (GoogleHomeMatterAvailabilityResult) -> Unit,
    ) {
        val playServicesVersion = installedPlayServicesVersion(context)

        if (Build.VERSION.SDK_INT < MINIMUM_ANDROID_API) {
            onResult(
                result(
                    status = "androidTooOld",
                    message = "Google Home Matter requires Android 10 (API 29) or newer.",
                    playServicesVersion = playServicesVersion,
                )
            )
            return
        }

        val availability = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context)
        if (availability != ConnectionResult.SUCCESS) {
            val tooOld = availability == ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED
            onResult(
                result(
                    status = if (tooOld) "playServicesTooOld" else "playServicesUnavailable",
                    message = if (tooOld) {
                        "Google Play Services must be $MINIMUM_PLAY_SERVICES_VERSION or newer."
                    } else {
                        "Google Play Services is unavailable (code $availability)."
                    },
                    playServicesVersion = playServicesVersion,
                )
            )
            return
        }

        if (playServicesVersion == null ||
            compareVersions(playServicesVersion, MINIMUM_PLAY_SERVICES_VERSION) < 0
        ) {
            onResult(
                result(
                    status = "playServicesTooOld",
                    message = "Google Play Services must be $MINIMUM_PLAY_SERVICES_VERSION or newer.",
                    playServicesVersion = playServicesVersion,
                )
            )
            return
        }

        val readyResult = try {
            Matter.getCommissioningClient(context)
            result(
                isReady = true,
                status = "ready",
                message = "Google Home Matter commissioning is available.",
                playServicesVersion = playServicesVersion,
            )
        } catch (error: Throwable) {
            result(
                status = "sdkUnavailable",
                message = "Google Home commissioning SDK is unavailable: " +
                    (error.javaClass.simpleName),
                playServicesVersion = playServicesVersion,
            )
        }
        if (!readyResult.isReady) {
            onResult(readyResult)
            return
        }

        try {
            val commissioningClient = Matter.getCommissioningClient(context)
            ModuleInstall.getClient(context)
                .areModulesAvailable(commissioningClient)
                .addOnSuccessListener { moduleAvailability ->
                    if (moduleAvailability.areModulesAvailable()) {
                        onResult(readyResult)
                    } else {
                        onResult(
                            readyResult.copy(
                                isReady = false,
                                status = "moduleUnavailable",
                                message = "The Google Play Services Home module is not installed yet.",
                            )
                        )
                    }
                }
                .addOnFailureListener { error ->
                    onResult(
                        readyResult.copy(
                            isReady = false,
                            status = "sdkUnavailable",
                            message = "Unable to check the Google Play Services Home module: " +
                                (error.javaClass.simpleName),
                        )
                    )
                }
        } catch (error: Throwable) {
            onResult(
                readyResult.copy(
                    isReady = false,
                    status = "sdkUnavailable",
                    message = "Unable to check the Google Play Services Home module: " +
                        (error.javaClass.simpleName),
                )
            )
        }
    }

    fun compareVersions(left: String, right: String): Int {
        val leftParts = left.split('.')
        val rightParts = right.split('.')
        val count = maxOf(leftParts.size, rightParts.size)
        for (index in 0 until count) {
            val leftPart = leftParts.getOrNull(index)?.toIntOrNull() ?: 0
            val rightPart = rightParts.getOrNull(index)?.toIntOrNull() ?: 0
            if (leftPart != rightPart) {
                return leftPart.compareTo(rightPart)
            }
        }
        return 0
    }

    private fun installedPlayServicesVersion(context: Context): String? {
        return try {
            @Suppress("DEPRECATION")
            context.packageManager
                .getPackageInfo("com.google.android.gms", 0)
                .versionName
        } catch (_: Throwable) {
            null
        }
    }

    private fun result(
        status: String,
        message: String,
        playServicesVersion: String?,
        isReady: Boolean = false,
    ): GoogleHomeMatterAvailabilityResult {
        return GoogleHomeMatterAvailabilityResult(
            isReady = isReady,
            status = status,
            message = message,
            playServicesVersion = playServicesVersion,
            minimumPlayServicesVersion = MINIMUM_PLAY_SERVICES_VERSION,
        )
    }
}
