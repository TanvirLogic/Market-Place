package net.eduverseapp.platform.upload

import android.content.Context
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Auth for the native upload pipeline.
 *
 * The Dart side mirrors the current access + refresh tokens (and the refresh
 * endpoint) into a plain app-private SharedPreferences file the moment an upload
 * is enqueued. The worker reads those here and — critically — can refresh the
 * access token itself by calling the refresh endpoint when the backend returns
 * 401, so uploads keep working while the app is dead and the token expires.
 */
class TokenManager(private val context: Context) {

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    @Volatile
    private var accessToken: String = prefs.getString(KEY_ACCESS, "") ?: ""

    fun currentToken(): String = accessToken

    /** Attempt a token refresh. Returns true and updates [accessToken] on success. */
    @Synchronized
    fun refresh(): Boolean {
        val refreshToken = prefs.getString(KEY_REFRESH, "") ?: ""
        val refreshUrl = prefs.getString(KEY_REFRESH_URL, "") ?: ""
        if (refreshToken.isEmpty() || refreshUrl.isEmpty()) return false
        return try {
            val body = JSONObject().put("refreshToken", refreshToken).toString()
            val req = Request.Builder()
                .url(refreshUrl)
                .header("content-type", "application/json")
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return false
                val respBody = resp.body?.string() ?: return false
                val data = JSONObject(respBody).optJSONObject("data") ?: return false
                val newAccess = data.optString("accessToken", "")
                if (newAccess.isEmpty()) return false
                val newRefresh = data.optString("refreshToken", refreshToken)
                accessToken = newAccess
                prefs.edit()
                    .putString(KEY_ACCESS, newAccess)
                    .putString(KEY_REFRESH, newRefresh)
                    .apply()
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val PREFS = "eduverse_upload_auth"
        private const val KEY_ACCESS = "access_token"
        private const val KEY_REFRESH = "refresh_token"
        private const val KEY_REFRESH_URL = "refresh_url"

        /** Called from the MethodChannel to keep native auth in sync with Dart. */
        fun updateTokens(
            context: Context,
            accessToken: String,
            refreshToken: String,
            refreshUrl: String,
        ) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_ACCESS, accessToken)
                .putString(KEY_REFRESH, refreshToken)
                .putString(KEY_REFRESH_URL, refreshUrl)
                .apply()
        }
    }
}
