package net.eduverseapp.platform.upload

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
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

class UploadWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    private val store = UploadStore(context)
    private val tokens = TokenManager(context)

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS)
        .writeTimeout(0, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(true)
        .build()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val jobId = inputData.getString(KEY_JOB_ID)
            ?: return@withContext Result.failure()
        val job = store.loadPending(jobId)
            ?: return@withContext Result.success()

        Log.i(TAG, "=== PIPELINE START: jobId=$jobId title=${job.title} filePath=${job.filePath} fileSize=${job.fileSize} initUrl=${job.initUrl} completeUrl=${job.completeUrl} callbackUrl=${job.callbackUrl} ===")
        Log.i(TAG, "PIPELINE: initBody=${job.initBody}")
        Log.i(TAG, "PIPELINE: callbackBodyTemplate=${job.callbackBodyTemplate}")

        setForegroundSafe(job.title, "Preparing…", indeterminate = true)
        writeProgress(jobId, 0)

        val result = runPipeline(job)

        if (result.success) {
            Log.i(TAG, "=== PIPELINE SUCCESS: jobId=$jobId fileUrl=${result.fileUrl} ===")
            store.saveResult(UploadResult(jobId, "completed", result.fileUrl, null))
            store.deletePending(jobId)
            showCompletionNotification(job)
        } else {
            Log.w(TAG, "=== PIPELINE FAILED: jobId=$jobId fileUrl=${result.fileUrl} error=${result.error} ===")
            if (store.loadPending(jobId) != null) {
                store.saveResult(UploadResult(jobId, "failed", result.fileUrl, result.error))
                store.deletePending(jobId)
            }
            showFailureNotification(job, result.error)
        }
        writeProgress(jobId, -1)
        Result.success()
    }

    /**
     * Returns a [PipelineResult] instead of throwing, so [doWork] can distinguish
     * between expected failures (callback failed but bytes on S3) and unexpected
     * crashes, without the catch-block overwriting a previously-saved fileUrl.
     */
    private data class PipelineResult(
        val success: Boolean,
        val fileUrl: String?,
        val error: String?,
    )

    private suspend fun runPipeline(job: UploadJobData): PipelineResult {
        // ── Step 1: init ──
        Log.i(TAG, "INIT REQUEST: jobId=${job.jobId} url=${job.initUrl} body=${job.initBody}")
        var initBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
        if (initBody == null) {
            Log.e(TAG, "INIT FAILED: jobId=${job.jobId} — null response")
            return PipelineResult(false, null, "Init failed")
        }
        Log.i(TAG, "INIT RESPONSE: jobId=${job.jobId} body=$initBody")
        var init = InitParser.parse(initBody, job.courseAssetKey)
        if (init == null) {
            Log.e(TAG, "INIT PARSE FAILED: jobId=${job.jobId} body=$initBody")
            return PipelineResult(false, null, "Init parse failed")
        }
        Log.i(TAG, "INIT SUCCESS: jobId=${job.jobId} isMultipart=${init.isMultipart} parts=${init.parts.size} fileUrl=${init.fileUrl} key=${init.key} s3UploadId=${init.s3UploadId}")

        var fileUrl = init.fileUrl

        // ── Proactive presigned URL refresh ──
        val age = System.currentTimeMillis() - job.createdAt
        if (init.isMultipart && age > PRESIGNED_REFRESH_MS) {
            Log.i(TAG, "Job ${job.jobId} is ${age / 1000}s old — proactively refreshing presigned URLs")
            val freshBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
            if (freshBody != null) {
                val freshInit = InitParser.parse(freshBody, job.courseAssetKey)
                if (freshInit != null && freshInit.isMultipart && freshInit.parts.size == init.parts.size) {
                    for (i in init.parts.indices) {
                        init.parts[i] = PartUrl(freshInit.parts[i].partNumber, freshInit.parts[i].uploadUrl)
                    }
                    Log.i(TAG, "Proactive refresh succeeded for ${job.jobId}")
                }
            }
        }

        // ── Step 2: transfer ──
        if (init.isMultipart) {
            val etags = JSONArray()
            val total = init.parts.size
            val partSize = 5L * 1024 * 1024
            Log.i(TAG, "MULTIPART START: jobId=${job.jobId} totalParts=$total fileSize=${job.fileSize} partSize=$partSize")
            for ((idx, part) in init.parts.withIndex()) {
                val start = idx * partSize
                val isLast = idx == total - 1
                val end = if (isLast) -1L else (start + partSize - 1)
                val pct = ((idx.toFloat() / total) * 100).toInt()

                val text = "Uploading part ${idx + 1} of $total — $pct%"
                setForegroundSafe(job.title, text, progress = pct)
                writeProgress(job.jobId, pct)

                Log.i(TAG, "PART UPLOAD: jobId=${job.jobId} part=${part.partNumber} idx=$idx range=bytes=$start-$end url=${part.uploadUrl.take(80)}...")
                var etag = uploadPart(job.filePath, start, end, part.uploadUrl)
                if (etag == null) {
                    Log.w(TAG, "PART RETRY: jobId=${job.jobId} part=${part.partNumber} failed, re-initing")
                    initBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
                    val reinit = initBody?.let { InitParser.parse(it, job.courseAssetKey) }
                    val fresh = reinit?.parts?.getOrNull(idx)
                    if (fresh != null) {
                        etag = uploadPart(job.filePath, start, end, fresh.uploadUrl)
                    }
                }
                if (etag == null) {
                    Log.e(TAG, "PART FAILED: jobId=${job.jobId} part=${part.partNumber} — aborting")
                    abort(job, init)
                    return PipelineResult(false, null, "Part ${part.partNumber} failed after retry")
                }
                Log.i(TAG, "PART SUCCESS: jobId=${job.jobId} part=${part.partNumber} eTag=$etag")
                etags.put(JSONObject().apply {
                    put("partNumber", part.partNumber)
                    put("eTag", etag)
                })
            }
            Log.i(TAG, "MULTIPART ALL DONE: jobId=${job.jobId}")

            // ── Step 3: complete ──
            setForegroundSafe(job.title, "Finalizing…", progress = 95)
            writeProgress(job.jobId, 95)
            val completeBody = JSONObject().apply {
                put("key", init.key)
                put("uploadId", init.s3UploadId)
                put("parts", etags)
            }.toString()
            Log.i(TAG, "COMPLETE REQUEST: jobId=${job.jobId} url=${job.completeUrl} body=$completeBody")
            val completeResp = httpJson(job.completeUrl, "POST", completeBody, auth = true)
            if (completeResp == null) {
                Log.e(TAG, "COMPLETE FAILED: jobId=${job.jobId} — null response, aborting")
                abort(job, init)
                return PipelineResult(false, null, "Complete failed")
            }
            Log.i(TAG, "COMPLETE RESPONSE: jobId=${job.jobId} body=$completeResp")
            val extractedUrl = InitParser.extractFileUrl(completeResp)
            if (extractedUrl == null) {
                Log.e(TAG, "COMPLETE FAILED: jobId=${job.jobId} — no fileUrl in response, aborting")
                abort(job, init)
                return PipelineResult(false, null, "Complete response missing fileUrl")
            }
            Log.i(TAG, "COMPLETE SUCCESS: jobId=${job.jobId} fileUrl=$extractedUrl")
            fileUrl = extractedUrl
        } else {
            Log.i(TAG, "DIRECT UPLOAD: jobId=${job.jobId} url=${init.uploadUrl}")
            setForegroundSafe(job.title, "Uploading…", indeterminate = true)
            writeProgress(job.jobId, 50)
            var ok = uploadDirect(job.filePath, init.uploadUrl!!)
            if (!ok) {
                Log.w(TAG, "DIRECT UPLOAD RETRY: jobId=${job.jobId} URL expired, re-initing")
                initBody = httpJson(job.initUrl, "POST", job.initBody, auth = true)
                val reinit = initBody?.let { InitParser.parse(it, job.courseAssetKey) }
                if (reinit?.uploadUrl != null) {
                    init = reinit
                    fileUrl = reinit.fileUrl
                    ok = uploadDirect(job.filePath, reinit.uploadUrl)
                }
            }
            if (!ok) {
                Log.e(TAG, "DIRECT UPLOAD FAILED: jobId=${job.jobId}")
                return PipelineResult(false, null, "Direct upload failed")
            }
            Log.i(TAG, "DIRECT UPLOAD SUCCESS: jobId=${job.jobId}")
        }

        // ── Step 4: callback (with retry) ──
        setForegroundSafe(job.title, "Almost done…", progress = 99)
        writeProgress(job.jobId, 99)
        val callbackBody = job.callbackBodyTemplate.replace("__FILE_URL__", fileUrl)
        Log.i(TAG, "CALLBACK REQUEST: jobId=${job.jobId} url=${job.callbackUrl} method=${job.callbackMethod} body=$callbackBody")

        // Exponential backoff: 2s, 4s, 8s, 16s (~30s total before giving up).
        // Each round internally retries once on 401 (token refresh), so we get
        // ~8 total attempts over 4 rounds. This survives app kills because the
        // entire pipeline runs inside the WorkManager worker.
        val callbackResult = callbackWithRetry(job, callbackBody)
        // callbackResult is either the body (succeeded) or an error description.
        if (callbackResult.startsWith("Callback failed")) {
            Log.e(TAG, "$callbackResult for ${job.jobId}")
            store.saveResult(UploadResult(job.jobId, "failed", fileUrl, callbackResult))
            store.deletePending(job.jobId)
            return PipelineResult(false, fileUrl, callbackResult)
        }

        Log.i(TAG, "Callback succeeded for ${job.jobId}")
        return PipelineResult(true, fileUrl, null)
    }

    /**
     * Callback with exponential backoff so the upload survives app restarts.
     * Each round delegates to [httpWithCode] which handles 401→refresh internally,
     * so we get ~2 attempts per round × 4 rounds = ~8 total attempts.
     * Returns the response body on success, or an error description on failure.
     */
    private suspend fun callbackWithRetry(job: UploadJobData, body: String): String {
        val maxRounds = 4
        var lastCode = -1
        for (round in 0 until maxRounds) {
            if (round > 0) {
                delay((1L shl round) * 1000L) // 2s, 4s, 8s, 16s
            }
            val resp = httpWithCode(job.callbackUrl, job.callbackMethod, body, auth = true)
            if (resp != null && (resp.code in 200..299 || resp.code == 409)) {
                return resp.body ?: ""
            }
            if (resp != null) {
                lastCode = resp.code
                Log.w(TAG, "Callback round ${round + 1}/$maxRounds HTTP $lastCode for ${job.jobId}")
            } else {
                Log.w(TAG, "Callback round ${round + 1}/$maxRounds network error for ${job.jobId}")
            }
        }
        return if (lastCode > 0) "Callback failed (HTTP $lastCode)" else "Callback failed (network error)"
    }

    /**
     * Like [httpJson] but returns the HTTP status code alongside the body so
     * callers can diagnose 4xx/5xx errors.
     */
    private data class HttpResult(val code: Int, val body: String?)

    private fun httpWithCode(
        url: String, method: String, body: String, auth: Boolean,
    ): HttpResult? {
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
                    val respBody = resp.body?.string() ?: ""
                    if (resp.isSuccessful) return HttpResult(resp.code, respBody)
                    if (resp.code == 409) return HttpResult(resp.code, respBody) // idempotent
                    if ((resp.code == 401 || resp.code == 403) && auth && attempt < 2) {
                        if (tokens.refresh()) {
                            Log.i(TAG, "Token refreshed (HTTP ${resp.code}), retrying $method $url")
                        } else {
                            return HttpResult(resp.code, null)
                        }
                    } else {
                        Log.w(TAG, "$method $url -> HTTP ${resp.code}")
                        return HttpResult(resp.code, null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "$method $url error", e)
                if (attempt >= 2) return null
            }
        }
        return null
    }

    // ── HTTP helpers ─────────────────────────────────────────────────────

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
                    if ((resp.code == 401 || resp.code == 403) && auth && attempt < 2) {
                        if (!tokens.refresh()) return null
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

    private fun getFileSize(filePath: String): Long {
        val uri = Uri.parse(filePath)
        return if (uri.scheme == "content") {
            try {
                val cursor = applicationContext.contentResolver.query(uri, null, null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val idx = it.getColumnIndex(android.provider.OpenableColumns.SIZE)
                        if (idx >= 0) it.getLong(idx) else -1L
                    } else -1L
                } ?: -1L
            } catch (_: Exception) {
                -1L
            }
        } else {
            File(uri.path ?: filePath).length()
        }
    }

    /**
     * Builds a [RequestBody] that sends only the byte range [start..end] from
     * [filePath]. When [end] is -1 the part extends to the end of the file.
     * The real content length is always reported so OkHttp sends a valid
     * `Content-Length` header instead of chunked transfer encoding — S3
     * multipart uploads require `Content-Length`.
     */
    private fun rangeBody(filePath: String, start: Long, end: Long): RequestBody {
        val partLen = if (end < 0L) {
            val total = getFileSize(filePath)
            if (total > 0L) total - start else -1L
        } else {
            end - start + 1L
        }
        return object : RequestBody() {
            override fun contentType() = "application/octet-stream".toMediaType()
            override fun contentLength(): Long = partLen
            override fun writeTo(sink: BufferedSink) {
                openInputStream(filePath).use { input ->
                    var skipped = 0L
                    while (skipped < start) {
                        val s = input.skip(start - skipped)
                        if (s <= 0) break
                        skipped += s
                    }
                    val buf = ByteArray(64 * 1024)
                    var remaining = if (partLen < 0L) Long.MAX_VALUE else partLen
                    while (remaining > 0L) {
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

    // ── File-based progress (read by Dart poll cycle) ─────────────────────

    /**
     * Write current progress (0-100) to a temp file so the Dart side can read
     * it every poll cycle and update the UI in real-time.
     * Pass -1 to delete the progress file (job finished).
     */
    private fun writeProgress(jobId: String, pct: Int) {
        try {
            if (pct < 0) {
                store.deleteProgress(jobId)
                return
            }
            store.saveProgress(jobId, pct)
        } catch (e: Exception) {
            Log.w(TAG, "writeProgress error: ${e.message}")
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

    private fun showFailureNotification(job: UploadJobData, error: String?) {
        createChannel()
        val message = if (error != null && error.contains("Callback failed"))
            "Uploaded to server, waiting to save…"
        else
            "Upload failed — $error"
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(job.title)
            .setContentText(message)
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
        private const val PRESIGNED_REFRESH_MS = 30 * 60 * 1000L
        private val NOTIFICATION_ID = 20250709
    }
}
