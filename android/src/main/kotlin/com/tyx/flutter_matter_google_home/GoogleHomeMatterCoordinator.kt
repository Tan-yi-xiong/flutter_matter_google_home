package com.tyx.flutter_matter_google_home

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.home.matter.Matter
import com.google.android.gms.home.matter.commissioning.CommissioningCompleteMetadata
import com.google.android.gms.home.matter.commissioning.CommissioningRequest
import com.google.android.gms.home.matter.commissioning.CommissioningRequestMetadata
import com.google.android.gms.home.matter.commissioning.CommissioningResult
import com.google.android.gms.home.matter.commissioning.CommissioningService
import com.google.android.gms.home.matter.commissioning.CommissioningService.CommissioningError
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

internal object GoogleHomeMatterRuntime {
    @Volatile
    var coordinator: GoogleHomeMatterCoordinator? = null
}

internal class GoogleHomeMatterCoordinator(
    private val applicationContext: android.content.Context,
    private val channel: MethodChannel,
) {
    private companion object {
        const val TAG = "GoogleHomeMatter"
        const val FIRST_REQUEST_CODE = 42000
        const val LAST_REQUEST_CODE = 65000
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val requestCodeCounter = AtomicInteger(FIRST_REQUEST_CODE)

    private var activity: Activity? = null
    private var pendingStandalone: PendingStandalone? = null
    private var activeSession: HandoffSession? = null

    fun attachActivity(activity: Activity) {
        this.activity = activity
    }

    fun detachActivity(failPending: Boolean = true) {
        activity = null
        if (failPending) {
            failAll(
                reason = "The host activity was detached.",
                stage = "internal",
            )
        }
    }

    fun dispose() {
        activity = null
        failAll(
            reason = "The Google Home Matter plugin was detached.",
            stage = "internal",
        )
        if (GoogleHomeMatterRuntime.coordinator === this) {
            GoogleHomeMatterRuntime.coordinator = null
        }
    }

    fun checkAvailability(result: MethodChannel.Result) {
        GoogleHomeMatterAvailabilityChecker.check(applicationContext) { availability ->
            result.success(availability.toMap())
        }
    }

    fun commission(
        onboardingPayload: String?,
        targetWireName: String?,
        result: MethodChannel.Result,
    ) {
        mainHandler.post {
            if (isBusy()) {
                respondError(result, GoogleHomeMatterErrorCodes.BUSY, "Another operation is in progress.", "request")
                return@post
            }
            val payload = onboardingPayload?.takeIf { it.isNotEmpty() }
            val target = parseTarget(targetWireName)
            val hostActivity = activity
            if (payload == null || target == null || hostActivity == null) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.BAD_ARGS,
                    "onboardingPayload, target, and an attached activity are required.",
                    "request",
                )
                return@post
            }

            val request = try {
                buildRequest(payload, target, includeCommissioningService = false)
            } catch (_: Throwable) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.BAD_ARGS,
                    "Unable to build the Google commissioning request.",
                    "request",
                )
                return@post
            }
            val requestCode = nextRequestCode()
            pendingStandalone = PendingStandalone(requestCode, target, result)
            commissionDevice(hostActivity, request, requestCode, result) {
                pendingStandalone = null
            }
        }
    }

    fun startHandoffSession(
        sessionId: String?,
        onboardingPayload: String?,
        targetWireName: String?,
        secondFabricTimeoutSeconds: Int?,
        result: MethodChannel.Result,
    ) {
        mainHandler.post {
            if (isBusy()) {
                respondError(result, GoogleHomeMatterErrorCodes.BUSY, "Another operation is in progress.", "request")
                return@post
            }
            val hostActivity = activity
            val payload = onboardingPayload?.takeIf { it.isNotEmpty() }
            val target = parseTarget(targetWireName)
            if (sessionId.isNullOrEmpty() || payload == null || target == null || hostActivity == null) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.BAD_ARGS,
                    "sessionId, onboardingPayload, target, and an attached activity are required.",
                    "request",
                )
                return@post
            }
            val timeoutSeconds = secondFabricTimeoutSeconds?.coerceIn(1, 600) ?: 120
            val requestCode = nextRequestCode()
            val session = HandoffSession(
                id = sessionId,
                requestCode = requestCode,
                target = target,
                onboardingPayload = payload,
                timeoutSeconds = timeoutSeconds,
            )
            val request = try {
                buildRequest(payload, target, includeCommissioningService = true)
            } catch (_: Throwable) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.BAD_ARGS,
                    "Unable to build the Google commissioning request.",
                    "request",
                )
                return@post
            }
            activeSession = session
            try {
                commissionDevice(hostActivity, request, requestCode, result, onStarted = {
                    result.success(mapOf("sessionId" to sessionId))
                }, onFailed = {
                    if (activeSession === session) {
                        activeSession = null
                    }
                })
            } catch (_: Throwable) {
                if (activeSession === session) {
                    activeSession = null
                }
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.REQUEST_FAILED,
                    "Unable to start Google commissioning.",
                    "request",
                )
            }
        }
    }

    fun completeHandoff(
        sessionId: String?,
        succeeded: Boolean?,
        errorCode: Int?,
        result: MethodChannel.Result,
    ) {
        mainHandler.post {
            val session = activeSession
            if (session == null || session.id != sessionId) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.SESSION_NOT_FOUND,
                    "The Google Home Matter session no longer exists.",
                    "handoff",
                )
                return@post
            }
            if (succeeded == null) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.BAD_ARGS,
                    "succeeded is required.",
                    "request",
                )
                return@post
            }
            val delegate = session.serviceDelegate
            if (!session.handoffReady || delegate == null) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.SESSION_NOT_READY,
                    "The handoff is not ready yet.",
                    "handoff",
                )
                return@post
            }
            if (session.completionReported) {
                respondError(
                    result,
                    GoogleHomeMatterErrorCodes.COMPLETE_ALREADY_REPORTED,
                    "The second-fabric result has already been reported.",
                    "handoff",
                )
                return@post
            }

            session.completionReported = true
            session.completionSucceeded = succeeded
            session.secondFabricErrorCode = errorCode

            if (session.completionSucceeded == true) {
                delegate.sendCommissioningComplete(
                    CommissioningCompleteMetadata.builder().build()
                ).addOnSuccessListener {
                    result.success(null)
                }.addOnFailureListener { error ->
                    session.completionReported = false
                    session.completionSucceeded = null
                    respondError(
                        result,
                        GoogleHomeMatterErrorCodes.INTERNAL,
                        "Google Play Services rejected the commissioning completion.",
                        "finalization",
                    )
                    Log.w(TAG, "sendCommissioningComplete failed: ${error.javaClass.simpleName}")
                }
            } else {
                delegate.sendCommissioningError(CommissioningError.OTHER)
                    .addOnSuccessListener {
                        result.success(null)
                        if (activeSession === session && !session.resultEmitted) {
                            emitSessionFailure(
                                session,
                                googleHomeMatterErrorMap(
                                    stage = "secondFabric",
                                    message = "The second fabric did not complete successfully.",
                                    secondFabricErrorCode = session.secondFabricErrorCode,
                                    googleFabricSucceeded = session.handoffReady,
                                ),
                            )
                        }
                    }
                    .addOnFailureListener { error ->
                        session.completionReported = false
                        session.completionSucceeded = null
                        respondError(
                            result,
                            GoogleHomeMatterErrorCodes.INTERNAL,
                            "Google Play Services rejected the second-fabric failure report.",
                            "finalization",
                        )
                        Log.w(TAG, "sendCommissioningError failed: ${error.javaClass.simpleName}")
                    }
            }
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val standalone = pendingStandalone
        if (standalone != null && standalone.requestCode == requestCode) {
            pendingStandalone = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                try {
                    val parsed = CommissioningResult.fromIntentSenderResult(resultCode, data)
                    standalone.result.success(resultMap(standalone.target, parsed, handoffUsed = false))
                } catch (error: ApiException) {
                    standalone.result.error(
                        GoogleHomeMatterErrorCodes.REQUEST_FAILED,
                        error.status.statusMessage,
                        googleHomeMatterErrorMap(
                            stage = "googleCommissioning",
                            message = error.status.statusMessage ?: "Google commissioning failed.",
                            googleApiStatusCode = error.statusCode,
                        ),
                    )
                } catch (error: Throwable) {
                    standalone.result.error(
                        GoogleHomeMatterErrorCodes.REQUEST_FAILED,
                        "Unable to read the Google commissioning result.",
                        googleHomeMatterErrorMap(
                            stage = "finalization",
                            message = "Unable to read the Google commissioning result.",
                        ),
                    )
                }
            } else {
                standalone.result.error(
                    GoogleHomeMatterErrorCodes.USER_CANCELLED,
                    "Google commissioning was cancelled.",
                    googleHomeMatterErrorMap(
                        stage = "userCancelled",
                        message = "Google commissioning was cancelled.",
                    ),
                )
            }
            return true
        }

        val session = activeSession
        if (session != null && session.requestCode == requestCode) {
            finishHandoffSession(session, resultCode, data)
            return true
        }
        return false
    }

    fun onCommissioningRequested(
        delegate: CommissioningService,
        metadata: CommissioningRequestMetadata,
    ) {
        mainHandler.post {
            val session = activeSession
            if (session == null) {
                delegate.sendCommissioningError(CommissioningError.OTHER)
                return@post
            }
            if (session.handoffReady) {
                delegate.sendCommissioningError(CommissioningError.OTHER)
                return@post
            }

            session.serviceDelegate = delegate
            session.handoffPayload = try {
                handoffMap(session.onboardingPayload, metadata)
            } catch (_: Throwable) {
                delegate.sendCommissioningError(CommissioningError.OTHER)
                emitSessionFailure(
                    session,
                    googleHomeMatterErrorMap(
                        stage = "finalization",
                        message = "Google commissioning did not provide usable handoff data.",
                    ),
                )
                return@post
            }
            session.handoffReady = true
            scheduleSecondFabricTimeout(session)
            emitEvent(
                mapOf(
                    "type" to "handoffReady",
                    "sessionId" to session.id,
                    "handoff" to session.handoffPayload,
                )
            )
            session.onboardingPayload = ""
            session.handoffPayload = null
        }
    }

    private fun commissionDevice(
        hostActivity: Activity,
        request: CommissioningRequest,
        requestCode: Int,
        channelResult: MethodChannel.Result,
        onStarted: (() -> Unit)? = null,
        onFailed: (() -> Unit)? = null,
    ) {
        try {
            Matter.getCommissioningClient(applicationContext)
                .commissionDevice(request)
                .addOnSuccessListener { sender ->
                    try {
                        hostActivity.startIntentSenderForResult(sender, requestCode, null, 0, 0, 0)
                        onStarted?.invoke()
                        if (onStarted == null) {
                            // Standalone commissioning keeps its MethodChannel result
                            // pending until Activity.onActivityResult.
                        }
                    } catch (_: Exception) {
                        onFailed?.invoke()
                        respondError(
                            channelResult,
                            GoogleHomeMatterErrorCodes.REQUEST_FAILED,
                            "Unable to launch the Google commissioning UI.",
                            "request",
                        )
                    }
                }
                .addOnFailureListener { error ->
                    onFailed?.invoke()
                    val apiError = error as? ApiException
                    respondError(
                        channelResult,
                        GoogleHomeMatterErrorCodes.REQUEST_FAILED,
                        apiError?.status?.statusMessage ?: "Unable to start Google commissioning.",
                        "request",
                        googleApiStatusCode = apiError?.statusCode,
                    )
                }
        } catch (_: Throwable) {
            onFailed?.invoke()
            respondError(
                channelResult,
                GoogleHomeMatterErrorCodes.REQUEST_FAILED,
                "Unable to start Google commissioning.",
                "request",
            )
        }
    }

    private fun finishHandoffSession(
        session: HandoffSession,
        resultCode: Int,
        data: Intent?,
    ) {
        cancelSecondFabricTimeout(session)
        if (session.resultEmitted) {
            if (activeSession === session) {
                activeSession = null
            }
            return
        }

        val completionSucceeded = session.completionSucceeded
        if (completionSucceeded == false) {
            emitSessionFailure(
                session,
                googleHomeMatterErrorMap(
                    stage = "secondFabric",
                    message = "The second fabric did not complete successfully.",
                    secondFabricErrorCode = session.secondFabricErrorCode,
                    googleFabricSucceeded = session.handoffReady,
                ),
            )
            return
        }

        if (completionSucceeded != true) {
            emitSessionFailure(
                session,
                googleHomeMatterErrorMap(
                    stage = if (session.handoffReady) "secondFabric" else "finalization",
                    message = "The second-fabric result was not reported before Google commissioning ended.",
                    googleFabricSucceeded = session.handoffReady,
                ),
            )
            return
        }

        if (resultCode == Activity.RESULT_OK && data != null) {
            try {
                val parsed = CommissioningResult.fromIntentSenderResult(resultCode, data)
                val result = resultMap(session.target, parsed, handoffUsed = true)
                session.resultEmitted = true
                if (activeSession === session) {
                    activeSession = null
                }
                emitEvent(
                    mapOf(
                        "type" to "completed",
                        "sessionId" to session.id,
                        "result" to result,
                    )
                )
                clearSensitiveSessionData(session)
            } catch (error: ApiException) {
                emitSessionFailure(
                    session,
                    googleHomeMatterErrorMap(
                        stage = "finalization",
                        message = error.status.statusMessage ?: "Google commissioning finalization failed.",
                        googleApiStatusCode = error.statusCode,
                        googleFabricSucceeded = session.handoffReady,
                    ),
                )
            } catch (_: Throwable) {
                emitSessionFailure(
                    session,
                    googleHomeMatterErrorMap(
                        stage = "finalization",
                        message = "Unable to read the Google commissioning result.",
                        googleFabricSucceeded = session.handoffReady,
                    ),
                )
            }
        } else {
            val stage = when {
                completionSucceeded == true -> "finalization"
                session.handoffReady -> "secondFabric"
                else -> "userCancelled"
            }
            emitSessionFailure(
                session,
                googleHomeMatterErrorMap(
                    stage = stage,
                    message = "Google commissioning did not complete.",
                    googleFabricSucceeded = session.handoffReady,
                ),
            )
        }
    }

    private fun scheduleSecondFabricTimeout(session: HandoffSession) {
        cancelSecondFabricTimeout(session)
        session.timeoutRunnable = Runnable {
            if (activeSession === session && session.completionSucceeded == null) {
                session.completionReported = true
                session.completionSucceeded = false
                session.secondFabricErrorCode = null
                session.serviceDelegate?.sendCommissioningError(CommissioningError.OTHER)
                emitSessionFailure(
                    session,
                    googleHomeMatterErrorMap(
                        stage = "secondFabric",
                        message = "The second fabric did not report completion before the timeout.",
                        googleFabricSucceeded = true,
                    ),
                )
            }
        }
        mainHandler.postDelayed(session.timeoutRunnable!!, session.timeoutSeconds * 1_000L)
    }

    private fun cancelSecondFabricTimeout(session: HandoffSession) {
        session.timeoutRunnable?.let(mainHandler::removeCallbacks)
        session.timeoutRunnable = null
    }

    private fun emitSessionFailure(session: HandoffSession, error: Map<String, Any?>) {
        session.resultEmitted = true
        emitEvent(
            mapOf(
                "type" to "failed",
                "sessionId" to session.id,
                "error" to error,
            )
        )
        if (activeSession === session) {
            activeSession = null
        }
        cancelSecondFabricTimeout(session)
        clearSensitiveSessionData(session)
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post {
            try {
                channel.invokeMethod("sessionEvent", payload)
            } catch (_: Throwable) {
                // The Flutter engine may already be detached. Never retry or log
                // the payload because it can contain a handoff.
            }
        }
    }

    private fun failAll(reason: String, stage: String) {
        pendingStandalone?.let { pending ->
            pendingStandalone = null
            pending.result.error(
                GoogleHomeMatterErrorCodes.ACTIVITY_UNAVAILABLE,
                reason,
                googleHomeMatterErrorMap(stage = stage, message = reason),
            )
        }
        activeSession?.let { session ->
            val serviceDelegate = session.serviceDelegate
            if (!session.resultEmitted) {
                emitSessionFailure(
                    session,
                    googleHomeMatterErrorMap(
                        stage = stage,
                        message = reason,
                        googleFabricSucceeded = session.handoffReady,
                    ),
                )
            }
            serviceDelegate?.sendCommissioningError(CommissioningError.OTHER)
            cancelSecondFabricTimeout(session)
            activeSession = null
        }
    }

    private fun buildRequest(
        onboardingPayload: String,
        target: String,
        includeCommissioningService: Boolean,
    ): CommissioningRequest {
        val builder = CommissioningRequest.builder()
            .setOnboardingPayload(onboardingPayload)
            .setStoreToGoogleFabric(target == TARGET_GOOGLE_HOME)
        if (includeCommissioningService) {
            builder.setCommissioningService(
                ComponentName(applicationContext, FlutterMatterCommissioningService::class.java)
            )
        }
        return builder.build()
    }

    private fun handoffMap(
        onboardingPayload: String,
        metadata: CommissioningRequestMetadata,
    ): Map<String, Any?> {
        val descriptor = metadata.deviceDescriptor
        return mapOf(
            "onboardingPayload" to onboardingPayload,
            "address" to metadata.networkLocation.formattedIpAddress,
            "port" to metadata.networkLocation.port,
            "setupPinCode" to metadata.passcode,
            "vendorId" to descriptor.vendorId.takeIf { it != 0 },
            "productId" to descriptor.productId.takeIf { it != 0 },
        )
    }

    private fun resultMap(
        target: String,
        parsed: CommissioningResult,
        handoffUsed: Boolean,
    ): Map<String, Any?> {
        val descriptor = parsed.commissionedDeviceDescriptor
        return mapOf(
            "target" to target,
            "handoffUsed" to handoffUsed,
            "deviceName" to parsed.deviceName,
            "deviceIds" to (parsed.deviceIds ?: emptyList<String>()),
            "vendorId" to descriptor.vendorId.takeIf { it != 0 },
            "productId" to descriptor.productId.takeIf { it != 0 },
        )
    }

    private fun clearSensitiveSessionData(session: HandoffSession) {
        session.handoffPayload = null
        session.onboardingPayload = ""
        session.serviceDelegate = null
    }

    private fun parseTarget(value: String?): String? {
        return when (value) {
            TARGET_GOOGLE_HOME, TARGET_ANDROID_LOCAL -> value
            else -> null
        }
    }

    private fun isBusy(): Boolean = pendingStandalone != null || activeSession != null

    private fun nextRequestCode(): Int {
        while (true) {
            val current = requestCodeCounter.getAndUpdate { value ->
                if (value >= LAST_REQUEST_CODE) FIRST_REQUEST_CODE else value + 1
            }
            return current
        }
    }

    private fun respondError(
        result: MethodChannel.Result,
        code: String,
        message: String,
        stage: String,
        googleApiStatusCode: Int? = null,
        secondFabricErrorCode: Int? = null,
        googleFabricSucceeded: Boolean = false,
    ) {
        result.error(
            code,
            message,
            googleHomeMatterErrorMap(
                stage = stage,
                message = message,
                googleApiStatusCode = googleApiStatusCode,
                secondFabricErrorCode = secondFabricErrorCode,
                googleFabricSucceeded = googleFabricSucceeded,
            ),
        )
    }

    private data class PendingStandalone(
        val requestCode: Int,
        val target: String,
        val result: MethodChannel.Result,
    )

    private data class HandoffSession(
        val id: String,
        val requestCode: Int,
        val target: String,
        var onboardingPayload: String,
        val timeoutSeconds: Int,
    ) {
        var serviceDelegate: CommissioningService? = null
        var handoffPayload: Map<String, Any?>? = null
        var handoffReady: Boolean = false
        var completionReported: Boolean = false
        var completionSucceeded: Boolean? = null
        var secondFabricErrorCode: Int? = null
        var timeoutRunnable: Runnable? = null
        var resultEmitted: Boolean = false
    }
}

internal const val TARGET_GOOGLE_HOME = "googleHomeFabric"
internal const val TARGET_ANDROID_LOCAL = "androidLocalFabric"
