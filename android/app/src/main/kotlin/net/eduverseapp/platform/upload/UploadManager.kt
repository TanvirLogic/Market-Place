package net.eduverseapp.platform.upload

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Entry point that enqueues native upload jobs.
 *
 * Jobs are appended to a single unique WorkManager chain so they run strictly
 * one-by-one (like YouTube's upload queue). Because WorkManager persists its
 * queue to disk, the remaining jobs continue and complete even if the app is
 * killed, and resume after a device reboot.
 */
object UploadManager {

    private const val UNIQUE_WORK = "eduverse_upload_queue"

    fun enqueue(context: Context, job: UploadJobData) {
        // Persist the full job payload so the worker can run without Dart.
        UploadStore(context).savePending(job)

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<UploadWorker>()
            .setInputData(Data.Builder().putString(UploadWorker.KEY_JOB_ID, job.jobId).build())
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(UNIQUE_WORK)
            .build()

        // APPEND_OR_REPLACE keeps the FIFO order and continues the chain across
        // process death. Each job is its own OneTimeWorkRequest in the chain.
        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_WORK,
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request,
        )
    }

    fun cancelAll(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK)
    }
}
