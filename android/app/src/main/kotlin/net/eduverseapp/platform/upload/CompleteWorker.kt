package net.eduverseapp.platform.upload

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker that calls the server's complete-multipart endpoint,
 * telling the backend to assemble uploaded parts on S3.
 *
 * Chained after [UploadWorker] parts, before [CallbackWorker].
 *
 * Input keys:
 *   completeUrl   — server endpoint
 *   completeBody  — JSON body (uploadId + parts ETags) as string
 *   authToken     — bearer token
 *   taskId        — DB task id (for logging)
 *
 * Output keys:
 *   fileUrl       — assembled file URL from server response
 *   completeSuccess — true on success
 */
class CompleteWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result {
        val completeUrl = inputData.getString("completeUrl") ?: return Result.failure()
        val completeBody = inputData.getString("completeBody") ?: return Result.failure()
        var authToken = inputData.getString("authToken") ?: return Result.failure()
        val taskId = inputData.getLong("taskId", 0L)
        val refreshEndpoint = inputData.getString("refreshEndpoint")
        val refreshToken = inputData.getString("refreshToken")

        android.util.Log.d("CompleteWorker", "completing multipart for task $taskId → $completeUrl")
        android.util.Log.d("CompleteWorker", "task $taskId requestBody=$completeBody")

        // Use in-memory cached token if available (from a prior refresh)
        val cached = TokenRefreshUtil.getCachedToken()
        if (cached != null) {
            android.util.Log.d("CompleteWorker", "using cached refreshed token for task $taskId")
            authToken = cached
        }

        try {
            val request = Request.Builder()
                .url(completeUrl)
                .post(completeBody.toRequestBody("application/json".toMediaType()))
                .header("Authorization", "Bearer $authToken")
                .header("Content-Type", "application/json")
                .build()

            val response = withContext(Dispatchers.IO) {
                client.newCall(request).execute()
            }

            val responseBody = response.body?.string() ?: ""
            android.util.Log.d("CompleteWorker", "task $taskId HTTP ${response.code} responseBody=$responseBody")

            // On 401, try token refresh then retry
            if (response.code == 401 &&
                refreshEndpoint != null && refreshToken != null &&
                runAttemptCount < 2
            ) {
                android.util.Log.d("CompleteWorker", "attempting token refresh for task $taskId")
                val newToken = TokenRefreshUtil.refresh(refreshEndpoint, refreshToken)
                if (newToken != null) {
                    TokenRefreshUtil.persistAccessToken(newToken)
                    android.util.Log.d("CompleteWorker", "token refreshed, retrying task $taskId")
                    return Result.retry()
                }
            }

            if (response.isSuccessful) {
                val fileUrl = try {
                    JSONObject(responseBody.ifEmpty { "{}" }).optString("fileUrl", "")
                } catch (_: Exception) { "" }
                // Persist intermediate chain progress so a killed app can
                // observe that the complete step succeeded before the
                // callback runs.
                UploadBridgeHandler.writeChainStatus(
                    applicationContext,
                    taskId,
                    state = "running",
                    fileUrl = fileUrl.ifEmpty { null },
                )
                return Result.success(outputDataOf(
                    "fileUrl" to fileUrl,
                    "completeSuccess" to true,
                ))
            }

            return if (runAttemptCount < 2) {
                android.util.Log.d("CompleteWorker", "retrying task $taskId (attempt $runAttemptCount)")
                Result.retry()
            } else {
                UploadBridgeHandler.writeChainStatus(
                    applicationContext,
                    taskId,
                    state = "failed",
                    error = "Complete HTTP ${response.code}",
                )
                Result.failure(outputDataOf(
                    "completeSuccess" to false,
                    "error" to "HTTP ${response.code}"
                ))
            }
        } catch (e: Exception) {
            android.util.Log.e("CompleteWorker", "task $taskId exception: ${e.message}")
            return if (runAttemptCount < 2) {
                Result.retry()
            } else {
                UploadBridgeHandler.writeChainStatus(
                    applicationContext,
                    taskId,
                    state = "failed",
                    error = e.message ?: "Unknown",
                )
                Result.failure(outputDataOf(
                    "completeSuccess" to false,
                    "error" to (e.message ?: "Unknown")
                ))
            }
        }
    }
}
