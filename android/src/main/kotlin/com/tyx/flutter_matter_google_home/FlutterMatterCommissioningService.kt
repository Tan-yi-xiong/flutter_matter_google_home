package com.tyx.flutter_matter_google_home

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.google.android.gms.home.matter.commissioning.CommissioningRequestMetadata
import com.google.android.gms.home.matter.commissioning.CommissioningService
import com.google.android.gms.home.matter.commissioning.CommissioningService.CommissioningError

/**
 * Exported service bound by Google Play Services when a handoff-enabled
 * CommissioningRequest asks for a second fabric.
 *
 * The service never logs onboarding payloads, network addresses, or passcodes.
 */
class FlutterMatterCommissioningService : Service(), CommissioningService.Callback {
    private lateinit var delegate: CommissioningService

    override fun onCreate() {
        super.onCreate()
        delegate = CommissioningService.Builder(this)
            .setCallback(this)
            .build()
    }

    override fun onBind(intent: Intent): IBinder = delegate.asBinder()

    override fun onCommissioningRequested(metadata: CommissioningRequestMetadata) {
        val coordinator = GoogleHomeMatterRuntime.coordinator
        if (coordinator == null) {
            delegate.sendCommissioningError(CommissioningError.OTHER)
            return
        }
        coordinator.onCommissioningRequested(delegate, metadata)
    }
}
