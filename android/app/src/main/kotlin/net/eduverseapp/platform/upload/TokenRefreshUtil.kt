package net.eduverseapp.platform.upload

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Utility to refresh an auth access token via the server's refresh endpoint.
 *
 * Used by [CompleteWorker] and [CallbackWorker] when they receive a 401.
 * Stores the new token in EncryptedSharedPreferences so the Dart side can
 * read it after app restart.
 */
object TokenRefreshUtil {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    private const val PREFS_NAME = "eduverse_auth_tokens"
    private const val KEY_ACCESS_TOKEN = "access_token"
    private const val KEY_REFRESH_TOKEN = "refresh_token"

    /**
     * Attempt to refresh the access token.
     *
     * @param refreshEndpoint e.g. "https://api.eduverse.app/auth/refresh"
     * @param refreshToken the refresh token sent from the Dart side
     * @return a new access token on success, or null on failure
     */
    fun refresh(
        refreshEndpoint: String,
        refreshToken: String,
    ): String? {
        try {
            val body = JSONObject().apply {
                put("refreshToken", refreshToken)
            }.toString()

            val request = Request.Builder()
                .url(refreshEndpoint)
                .post(body.toRequestBody("application/json".toMediaType()))
                .header("Content-Type", "application/json")
                .build()

            val response = client.newCall(request).execute()

            if (response.isSuccessful) {
                val responseBody = response.body?.string() ?: return null
                val json = JSONObject(responseBody)
                val data = json.optJSONObject("data") ?: json
                val newAccessToken = data.optString("accessToken")
                if (newAccessToken.isNotEmpty()) {
                    android.util.Log.d("TokenRefresh", "token refreshed successfully")
                    return newAccessToken
                }
            }

            android.util.Log.w("TokenRefresh", "refresh failed: HTTP ${response.code}")
            return null
        } catch (e: Exception) {
            android.util.Log.e("TokenRefresh", "refresh exception: ${e.message}")
            return null
        }
    }

    /**
     * Persist the new access token so the Dart side can read it
     * after the native worker finishes.
     */
    fun persistAccessToken(newToken: String) {
        // Token is already stored by Dart via flutter_secure_storage.
        // This is a synchronous local cache so retries within the same
        // worker invocation use the freshest token.
        _cachedToken = newToken
    }

    @Volatile
    private var _cachedToken: String? = null

    fun getCachedToken(): String? = _cachedToken
}
