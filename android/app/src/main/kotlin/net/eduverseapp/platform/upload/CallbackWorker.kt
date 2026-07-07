package net.eduverseapp.platform.upload

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker that sends the server callback (lesson creation).
 *
 * Chained after [UploadWorker] (or [CompleteWorker]) so the lesson is
 * created natively — survives app kill.
 *
 * Input keys:
 *   callbackUrl   — server endpoint for lesson creation
 *   callbackBody  — JSON body as a string
 *   authToken     — bearer token
 *   idempotencyKey — optional idempotency key
 *   taskId        — DB task id (for logging)
 *
 * Output keys:
 *   callbackSuccess — true if server accepted the callback
 */
class CallbackWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result {
        val callbackUrl = inputData.getString("callbackUrl") ?: return Result.failure()
        val callbackBody = inputData.getString("callbackBody") ?: return Result.failure()
        var authToken = inputData.getString("authToken") ?: return Result.failure()
        val taskId = inputData.getLong("taskId", 0L)
        val idempotencyKey = inputData.getString("idempotencyKey")
        val refreshEndpoint = inputData.getString("refreshEndpoint")
        val refreshToken = inputData.getString("refreshToken")

        android.util.Log.d("CallbackWorker", "sending callback for task $taskId → $callbackUrl")

        // Use in-memory cached token if available (from a prior refresh in this worker chain)
        val cached = TokenRefreshUtil.getCachedToken()
        if (cached != null) {
            android.util.Log.d("CallbackWorker", "using cached refreshed token for task $taskId")
            authToken = cached
        }

        try {
            val requestBuilder = Request.Builder()
                .url(callbackUrl)
                .post(callbackBody.toRequestBody("application/json".toMediaType()))
                .header("Authorization", "Bearer $authToken")
                .header("Content-Type", "application/json")

            if (idempotencyKey != null) {
                requestBuilder.header("Idempotency-Key", idempotencyKey)
            }

            val response = withContext(Dispatchers.IO) {
                client.newCall(requestBuilder.build()).execute()
            }

            android.util.Log.d("CallbackWorker", "task $taskId HTTP ${response.code}")

            // On 401, try token refresh then retry
            if (response.code == 401 &&
                refreshEndpoint != null && refreshToken != null &&
                runAttemptCount < 3
            ) {
                android.util.Log.d("CallbackWorker", "attempting token refresh for task $taskId")
                val newToken = TokenRefreshUtil.refresh(refreshEndpoint, refreshToken)
                if (newToken != null) {
                    TokenRefreshUtil.persistAccessToken(newToken)
                    android.util.Log.d("CallbackWorker", "token refreshed, retrying task $taskId")
                    return Result.retry()
                }
            }

            return when {
                response.isSuccessful || response.code == 409 -> {
                    UploadBridgeHandler.writeChainStatus(
                        applicationContext,
                        taskId,
                        state = "success",
                    )
                    Result.success(outputDataOf("callbackSuccess" to true))
                }
                runAttemptCount < 3 -> {
                    android.util.Log.d("CallbackWorker", "retrying task $taskId (attempt $runAttemptCount)")
                    Result.retry()
                }
                else -> {
                    UploadBridgeHandler.writeChainStatus(
                        applicationContext,
                        taskId,
                        state = "failed",
                        error = "Callback HTTP ${response.code}",
                    )
                    Result.failure(outputDataOf(
                        "callbackSuccess" to false,
                        "error" to "HTTP ${response.code}"
                    ))
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("CallbackWorker", "task $taskId exception: ${e.message}")
            return if (runAttemptCount < 3) {
                Result.retry()
            } else {
                UploadBridgeHandler.writeChainStatus(
                    applicationContext,
                    taskId,
                    state = "failed",
                    error = e.message ?: "Unknown",
                )
                Result.failure(outputDataOf(
                    "callbackSuccess" to false,
                    "error" to (e.message ?: "Unknown")
                ))
            }
        }
    }
}
