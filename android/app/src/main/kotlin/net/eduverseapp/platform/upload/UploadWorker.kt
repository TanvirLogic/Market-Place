package net.eduverseapp.platform.upload

import android.content.Context
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.logging.HttpLoggingInterceptor
import okio.BufferedSink
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * WorkManager worker that uploads a single file (or part of a file) via PUT.
 *
 * Input keys:
 *   uploadUrl   — presigned S3 URL
 *   filePath    — path to the source file
 *   startByte   — byte offset (0 for full file, >0 for a part)
 *   partLength  — number of bytes to upload (0 for full file)
 *   partNumber  — part index (0 for direct uploads)
 *   contentType — MIME type
 *   authToken   — bearer token for auth headers
 *
 * Output keys:
 *   success     — true/false
 *   eTag        — ETag header from response
 *   error       — error message if failed
 */
class UploadWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    companion object {
        private const val TAG_PREFIX = "eduverse_upload_"

        private val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(120, TimeUnit.SECONDS)
            .addInterceptor(HttpLoggingInterceptor { msg ->
                android.util.Log.d("UploadWorker", msg)
            }.apply {
                level = HttpLoggingInterceptor.Level.BODY
            })
            .build()
    }

    override suspend fun doWork(): Result {
        val uploadUrl = inputData.getString("uploadUrl") ?: return Result.failure()
        val filePath = inputData.getString("filePath") ?: return Result.failure()
        val startByte = inputData.getLong("startByte", 0L)
        val partLength = inputData.getLong("partLength", 0L)
        val partNumber = inputData.getInt("partNumber", 0)
        val contentType = inputData.getString("contentType") ?: "application/octet-stream"

        android.util.Log.d("UploadWorker", "doWork starting part=$partNumber file=$filePath url=$uploadUrl")

        val file = File(filePath)
        if (!file.exists()) {
            android.util.Log.e("UploadWorker", "File not found: $filePath")
            return Result.failure(outputDataOf("error" to "File not found"))
        }

        val runAttempts = runAttemptCount
        val taskId = inputData.getLong("taskId", 0L)
        val tag = "${TAG_PREFIX}${taskId}_$partNumber"

        // Absolute bytes uploaded for THIS part. The bridge sums this across all
        // part-workers of the task to compute a smooth whole-file percentage
        // (important for 2 GB files where per-part granularity is coarse).
        val currentBytes = AtomicLong(0L)
        val partTotalBytes = if (partLength > 0) partLength else file.length()

        val reportProgress: (Double, Int) -> Unit = { progress, _ ->
            currentBytes.set((progress * partTotalBytes).toLong())
        }

        return coroutineScope {
            val progressJob = launch {
                try {
                    while (true) {
                        val uploaded = currentBytes.get()
                        if (uploaded > 0) {
                            setProgress(
                                Data.Builder()
                                    .putLong("bytesUploaded", uploaded)
                                    .putLong("partTotalBytes", partTotalBytes)
                                    .putInt("partNumber", partNumber)
                                    .putLong("taskId", taskId)
                                    .build()
                            )
                        }
                        delay(500)
                    }
                } catch (_: kotlinx.coroutines.CancellationException) {
                    // cancelled normally
                }
            }

            try {
                val requestBody: RequestBody = if (partLength > 0) {
                    // Part upload: read byte range
                    PartRequestBody(file, startByte, partLength, contentType, reportProgress, partNumber)
                } else {
                    // Full file upload
                    object : RequestBody() {
                        override fun contentType() = contentType.toMediaType()
                        override fun contentLength() = file.length()
                        override fun writeTo(sink: BufferedSink) {
                            file.inputStream().buffered().use { input ->
                                val buffer = ByteArray(8192)
                                var total = 0L
                                val fileLen = file.length()
                                var bytes: Int
                                while (input.read(buffer).also { bytes = it } >= 0) {
                                    sink.write(buffer, 0, bytes)
                                    total += bytes
                                    if (fileLen > 0) {
                                        reportProgress(total.toDouble() / fileLen, partNumber)
                                    }
                                }
                            }
                        }
                    }
                }

                val request = Request.Builder()
                    .url(uploadUrl)
                    .put(requestBody)
                    .build()

                val response = withContext(Dispatchers.IO) {
                    client.newCall(request).execute()
                }

                android.util.Log.d("UploadWorker", "doWork part=$partNumber HTTP ${response.code} ${response.message}")
                progressJob.cancel()

                return@coroutineScope if (response.isSuccessful) {
                    // Preserve the ETag exactly as S3 returns it in the header
                    // (canonical quoted form, e.g. "abc123"). The backend's
                    // complete-multipart endpoint expects the raw header value.
                    val eTag = response.header("ETag")
                    Result.success(outputDataOf(
                        "success" to true,
                        "eTag" to (eTag ?: ""),
                        "partNumber" to partNumber,
                        "partTotalBytes" to partTotalBytes,
                    ))
                } else if (response.code == 403) {
                    Result.retry()
                } else {
                    if (runAttempts < 2) {
                        Result.retry()
                    } else {
                        Result.failure(outputDataOf(
                            "success" to false,
                            "error" to "HTTP ${response.code}",
                            "partNumber" to partNumber,
                        ))
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("UploadWorker", "doWork part=$partNumber exception: ${e.message}")
                progressJob.cancel()
                return@coroutineScope if (runAttempts < 2) {
                    Result.retry()
                } else {
                    Result.failure(outputDataOf(
                        "success" to false,
                        "error" to (e.message ?: "Unknown error"),
                        "partNumber" to partNumber,
                    ))
                }
            }
        }
    }

}

/** RequestBody that reads a byte range from a file. */
private class PartRequestBody(
    private val file: File,
    private val startByte: Long,
    private val partLength: Long,
    private val contentType: String,
    private val onProgress: (Double, Int) -> Unit,
    private val partNumber: Int,
) : RequestBody() {
    override fun contentType() = contentType.toMediaType()
    override fun contentLength() = partLength

    override fun writeTo(sink: BufferedSink) {
        file.inputStream().buffered().use { input ->
            input.skip(startByte)
            var remaining = partLength
            val buffer = ByteArray(8192)
            val totalLen = partLength
            while (remaining > 0) {
                val toRead = minOf(buffer.size.toLong(), remaining).toInt()
                val bytes = input.read(buffer, 0, toRead)
                if (bytes == -1) break
                sink.write(buffer, 0, bytes)
                remaining -= bytes
                val uploaded = partLength - remaining
                if (totalLen > 0) {
                    onProgress(uploaded.toDouble() / totalLen, partNumber)
                }
            }
        }
    }
}

fun outputDataOf(vararg pairs: Pair<String, Any>): Data {
    val builder = Data.Builder()
    for ((key, value) in pairs) {
        when (value) {
            is Boolean -> builder.putBoolean(key, value)
            is String -> builder.putString(key, value)
            is Int -> builder.putInt(key, value)
            is Long -> builder.putLong(key, value)
            is Float -> builder.putFloat(key, value)
            is Double -> builder.putDouble(key, value)
        }
    }
    return builder.build()
}
