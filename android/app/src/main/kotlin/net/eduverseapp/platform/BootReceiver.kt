package net.eduverseapp.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Schedule periodic WorkManager checks for orphaned uploads
            UploadWorker.enqueuePeriodic(context)
            // Also do an immediate one-time check
            UploadWorker.enqueueOneTime(context)
        }
    }
}
