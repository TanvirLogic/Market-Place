package net.eduverseapp.platform.upload

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.util.concurrent.TimeUnit

/**
 * Runs ONE upload job's full pipeline natively so it completes even while the
 * Flutter app is killed:
 *
 *   1. init      -> ask backend for presigned URL(s)
 *   2. transfer  -> PUT bytes to S3 (direct, or per-part with a byte Range)
 *   3. complete  -> (multipart only) send ETags, get final fileUrl
 *   4. callback  -> tell the backend the asset is ready
 *
 * Enqueued via WorkManager with a unique-work chain so multiple queued videos
 * run one-by-one, survive process death, and resume after reboot. The worker is
 * expedited/foreground so long transfers are not throttled.
 */
class UploadWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    private val store = UploadStore(context)
    private val tokens = TokenManager(context)

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS)
        .writeTimeout(0, TimeUnit.MILLISECONDS) // no write timeout for big PUTs
        .build()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val jobId = inputData.getString(KEY_JOB_ID)
            ?: return@withContext Result.failure()
        val job = store.loadPending(jobId)
            ?: return@withContext Result.success() // already handled/cleared

        setForegroundSafe(job.title, "Preparing…", indeterminate = true)

        try {
            runPipeline(job)
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Upload failed for $jobId", e)
            store.saveResult(UploadResult(jobId, "failed", null, e.message ?: "Unknown error"))
            store.deletePending(jobId)
            Result.success() // terminal; do not let WorkManager retry endlessly
        }
    }

    private suspend fun runPipeline(job: UploadJobData) {
        // ── Step 1: init (retry once on 401) ──
        var initBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
        if (initBody == null) throw RuntimeException("Init failed")
        var init = InitParser.parse(initBody, job.courseAssetKey)
            ?: throw RuntimeException("Init parse failed")

        var fileUrl = init.fileUrl

        // ── Step 2: transfer ──
        if (init.isMultipart) {
            val etags = JSONArray()
            val total = init.parts.size
            val partSize = 5L * 1024 * 1024
            for ((idx, part) in init.parts.withIndex()) {
                val start = idx * partSize
                val isLast = idx == total - 1
                val end = if (isLast) -1L else (start + partSize - 1)
                val pct = ((idx.toFloat() / total) * 100).toInt()
                setForegroundSafe(job.title, "$pct%", progress = pct)

                var etag = uploadPart(job.filePath, start, end, part.uploadUrl)
                if (etag == null) {
                    // Presigned URL may have expired mid-flight → re-init and retry the rest.
                    initBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
                    val reinit = initBody?.let { InitParser.parse(it, job.courseAssetKey) }
                    val fresh = reinit?.parts?.getOrNull(idx)
                    if (fresh != null) {
                        etag = uploadPart(job.filePath, start, end, fresh.uploadUrl)
                    }
                }
                if (etag == null) {
                    abort(job, init)
                    throw RuntimeException("Part ${part.partNumber} failed")
                }
                etags.put(JSONObject().apply {
                    put("partNumber", part.partNumber)
                    put("eTag", etag)
                })
            }

            // ── Step 3: complete ──
            setForegroundSafe(job.title, "Finalizing…", progress = 95)
            val completeBody = JSONObject().apply {
                put("key", init.key)
                put("uploadId", init.s3UploadId)
                put("parts", etags)
            }.toString()
            val completeResp = httpJson(job.completeUrl, "POST", completeBody, auth = true)
                ?: run { abort(job, init); throw RuntimeException("Complete failed") }
            fileUrl = InitParser.extractFileUrl(completeResp)
                ?: run { abort(job, init); throw RuntimeException("Complete missing fileUrl") }
        } else {
            // Direct upload
            setForegroundSafe(job.title, "Uploading…", indeterminate = true)
            var ok = uploadDirect(job.filePath, init.uploadUrl!!)
            if (!ok) {
                // Retry once with fresh presigned URL.
                initBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
                val reinit = initBody?.let { InitParser.parse(it, job.courseAssetKey) }
                if (reinit?.uploadUrl != null) {
                    init = reinit
                    fileUrl = reinit.fileUrl
                    ok = uploadDirect(job.filePath, reinit.uploadUrl)
                }
            }
            if (!ok) throw RuntimeException("Direct upload failed")
        }

        // ── Step 4: callback ──
        setForegroundSafe(job.title, "Almost done…", progress = 99)
        val callbackBody = job.callbackBodyTemplate.replace("__FILE_URL__", fileUrl)
        val callbackResp = httpJson(
            job.callbackUrl, job.callbackMethod, callbackBody, auth = true, allow409 = true,
        )
        if (callbackResp == null) {
            // Bytes are on S3 but the backend callback failed. Mark completed with
            // the fileUrl anyway so the Dart side can retry the (idempotent) callback.
            store.saveResult(UploadResult(job.jobId, "failed", fileUrl, "Callback failed"))
            store.deletePending(job.jobId)
            throw RuntimeException("Callback failed")
        }

        store.saveResult(UploadResult(job.jobId, "completed", fileUrl, null))
        store.deletePending(job.jobId)
        showCompletionNotification(job)
    }

    // ── HTTP helpers ─────────────────────────────────────────────────────

    /**
     * JSON call to our backend with bearer auth. On 401, refreshes the token
     * once and retries. Returns the response body on success (or 409 when
     * [allow409]); null otherwise.
     */
    private fun httpJson(
        url: String,
        method: String,
        body: String,
        auth: Boolean,
        allow409: Boolean = false,
    ): String? {
        var attempt = 0
        while (attempt < 2) {
            attempt++
            try {
                val reqBody = body.toRequestBody("application/json".toMediaType())
                val builder = Request.Builder()
                    .url(url)
                    .header("content-type", "application/json")
                if (auth) builder.header("Authorization", "Bearer ${tokens.currentToken()}")
                when (method.uppercase()) {
                    "PUT" -> builder.put(reqBody)
                    else -> builder.post(reqBody)
                }
                client.newCall(builder.build()).execute().use { resp ->
                    if (resp.isSuccessful || (allow409 && resp.code == 409)) {
                        return resp.body?.string() ?: ""
                    }
                    if (resp.code == 401 && auth && attempt < 2) {
                        if (!tokens.refresh()) return null
                        // loop to retry with the new token
                    } else {
                        Log.w(TAG, "$method $url -> HTTP ${resp.code}")
                        return null
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "$method $url error", e)
                if (attempt >= 2) return null
            }
        }
        return null
    }

    private fun uploadDirect(filePath: String, uploadUrl: String): Boolean {
        return try {
            val bytes = openInputStream(filePath).use { it.readBytes() }
            val req = Request.Builder()
                .url(uploadUrl)
                .put(bytes.toRequestBody("application/octet-stream".toMediaType()))
                .build()
            client.newCall(req).execute().use { it.isSuccessful }
        } catch (e: Exception) {
            Log.e(TAG, "Direct upload error", e)
            false
        }
    }

    /** Returns the ETag header (verbatim, quotes kept) or null on failure. */
    private fun uploadPart(filePath: String, start: Long, end: Long, uploadUrl: String): String? {
        return try {
            val req = Request.Builder()
                .url(uploadUrl)
                .put(rangeBody(filePath, start, end))
                .build()
            client.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) resp.header("ETag") else null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Part upload error", e)
            null
        }
    }

    private fun rangeBody(filePath: String, start: Long, end: Long): RequestBody {
        return object : RequestBody() {
            override fun contentType() = "application/octet-stream".toMediaType()
            override fun contentLength(): Long = if (end < 0) -1 else end - start + 1
            override fun writeTo(sink: BufferedSink) {
                openInputStream(filePath).use { input ->
                    var skipped = 0L
                    while (skipped < start) {
                        val s = input.skip(start - skipped)
                        if (s <= 0) break
                        skipped += s
                    }
                    val buf = ByteArray(64 * 1024)
                    var remaining = if (end < 0) Long.MAX_VALUE else (end - start + 1)
                    while (remaining > 0) {
                        val toRead = buf.size.toLong().coerceAtMost(remaining).toInt()
                        val read = input.read(buf, 0, toRead)
                        if (read == -1) break
                        sink.write(buf, 0, read)
                        remaining -= read.toLong()
                    }
                }
            }
        }
    }

    private fun openInputStream(filePath: String): InputStream {
        val uri = Uri.parse(filePath)
        return if (uri.scheme == "content") {
            applicationContext.contentResolver.openInputStream(uri)!!
        } else {
            FileInputStream(File(uri.path ?: filePath))
        }
    }

    private fun abort(job: UploadJobData, init: InitResult) {
        if (init.key == null || init.s3UploadId == null) return
        try {
            val body = JSONObject().apply {
                put("key", init.key)
                put("uploadId", init.s3UploadId)
            }.toString()
            httpJson(job.abortUrl, "POST", body, auth = true)
        } catch (e: Exception) {
            Log.w(TAG, "abort error", e)
        }
    }

    // ── Foreground notification ──────────────────────────────────────────

    private suspend fun setForegroundSafe(
        title: String,
        text: String,
        progress: Int = 0,
        indeterminate: Boolean = false,
    ) {
        try {
            setForeground(buildForegroundInfo(title, text, progress, indeterminate))
        } catch (e: Exception) {
            // On some OEMs setForeground can throw if the app is in a state that
            // disallows starting a foreground service; the upload still proceeds.
            Log.w(TAG, "setForeground failed: ${e.message}")
        }
    }

    private fun buildForegroundInfo(
        title: String,
        text: String,
        progress: Int,
        indeterminate: Boolean,
    ): ForegroundInfo {
        createChannel()
        val tapIntent = applicationContext.packageManager
            .getLaunchIntentForPackage(applicationContext.packageName)
            ?.let {
                PendingIntent.getActivity(
                    applicationContext, 0, it, PendingIntent.FLAG_IMMUTABLE,
                )
            }
        val notification: Notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(tapIntent)
            .apply {
                if (indeterminate) setProgress(0, 0, true)
                else if (progress in 1..100) setProgress(100, progress, false)
            }
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Uploads", NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Video upload progress" }
            applicationContext.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    /**
     * A separate, dismissable "completed" notification with a per-job id. The
     * ongoing progress notification (NOTIFICATION_ID) is removed by WorkManager
     * when the worker finishes, so this is the single "success" message.
     */
    private fun showCompletionNotification(job: UploadJobData) {
        createChannel()
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(job.title)
            .setContentText("Uploaded successfully")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()
        applicationContext.getSystemService(NotificationManager::class.java)
            .notify(job.jobId.hashCode() and 0x7FFFFFFF, notification)
    }

    companion object {
        private const val TAG = "EduverseUploadWorker"
        const val KEY_JOB_ID = "jobId"
        const val CHANNEL_ID = "eduverse_upload_channel"
        // Distinct notification id per worker instance so concurrent/sequential
        // jobs don't stomp each other's notification.
        private val NOTIFICATION_ID = 20250709
    }
}
