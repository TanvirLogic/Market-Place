package net.eduverseapp.platform

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.util.concurrent.TimeUnit

class UploadWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val state = UploadStateManager.load(applicationContext)
        if (state == null || state.items.isEmpty()) {
            UploadStateManager.clear(applicationContext)
            return Result.success()
        }

        // Remove completed/failed items that are already processed
        UploadStateManager.removeCompletedAndFailed(applicationContext)

        // Re-check after cleanup
        val cleanedState = UploadStateManager.load(applicationContext)
        if (cleanedState == null || cleanedState.items.isEmpty()) {
            return Result.success()
        }

        // Check if any items still have valid files
        val hasPendingItems = cleanedState.items.any { item ->
            val file = File(item.filePath)
            file.exists() && file.length() > 0L && item.status == UploadConstants.STATUS_PENDING
        }

        if (!hasPendingItems) {
            UploadStateManager.clear(applicationContext)
            return Result.success()
        }

        // Start the UploadReschedulerService to process the queue.
        // The service runs in a separate :upload process and survives app kill.
        val intent = android.content.Intent(
            applicationContext,
            UploadReschedulerService::class.java,
        ).apply {
            action = UploadReschedulerService.ACTION_PROCESS_QUEUE
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(intent)
        } else {
            applicationContext.startService(intent)
        }

        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "eduverse_upload_check"
        private const val PERIODIC_WORK_NAME = "eduverse_upload_periodic"

        fun enqueueOneTime(context: Context) {
            val request = OneTimeWorkRequestBuilder<UploadWorker>()
                .addTag("eduverse_upload")
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
        }

        fun enqueuePeriodic(context: Context) {
            // Reduced from 15 min to 3 min for faster orphan recovery
            val request = PeriodicWorkRequestBuilder<UploadWorker>(
                3, TimeUnit.MINUTES,
            ).addTag("eduverse_upload")
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    PERIODIC_WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request,
                )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK_NAME)
        }
    }
}
