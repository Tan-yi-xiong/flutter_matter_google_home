package com.tyx.flutter_matter_google_home

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class FlutterMatterGoogleHomePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var coordinator: GoogleHomeMatterCoordinator
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        coordinator = GoogleHomeMatterCoordinator(binding.applicationContext, channel)
        GoogleHomeMatterRuntime.coordinator = coordinator
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (::coordinator.isInitialized) {
            coordinator.dispose()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!::coordinator.isInitialized) {
            result.error(
                GoogleHomeMatterErrorCodes.INTERNAL,
                "Google Home Matter plugin is not attached.",
                googleHomeMatterErrorMap("internal", "Google Home Matter plugin is not attached."),
            )
            return
        }
        val arguments = call.arguments as? Map<*, *>
        when (call.method) {
            "checkAvailability" -> coordinator.checkAvailability(result)
            "commission" -> coordinator.commission(
                onboardingPayload = arguments?.get("onboardingPayload") as? String,
                targetWireName = arguments?.get("target") as? String,
                result = result,
            )
            "startHandoffSession" -> coordinator.startHandoffSession(
                sessionId = arguments?.get("sessionId") as? String,
                onboardingPayload = arguments?.get("onboardingPayload") as? String,
                targetWireName = arguments?.get("target") as? String,
                secondFabricTimeoutSeconds = (arguments?.get("secondFabricTimeoutSeconds") as? Number)?.toInt(),
                result = result,
            )
            "completeHandoff" -> coordinator.completeHandoff(
                sessionId = arguments?.get("sessionId") as? String,
                succeeded = arguments?.get("succeeded") as? Boolean,
                errorCode = (arguments?.get("errorCode") as? Number)?.toInt(),
                result = result,
            )
            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        coordinator.attachActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity(failPending = false)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity(failPending = true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        return if (::coordinator.isInitialized) {
            coordinator.handleActivityResult(requestCode, resultCode, data)
        } else {
            false
        }
    }

    private fun detachActivity(failPending: Boolean) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        if (::coordinator.isInitialized) {
            coordinator.detachActivity(failPending)
        }
    }

    companion object {
        const val CHANNEL_NAME = "flutter_matter_google_home"
    }
}
