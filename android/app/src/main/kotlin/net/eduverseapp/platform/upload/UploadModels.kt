package net.eduverseapp.platform.upload

import org.json.JSONArray
import org.json.JSONObject

/**
 * A single upload job the native pipeline runs end-to-end:
 * init -> transfer (direct or multipart) -> complete -> callback.
 *
 * All fields needed to run WITHOUT the Flutter/Dart isolate are captured here
 * and persisted in [UploadStore] so the job survives app kill and device reboot.
 */
data class UploadJobData(
    val jobId: String,
    val filePath: String,
    val fileSize: Long,
    val title: String,
    // ── endpoints (already resolved on the Dart side) ──
    val initUrl: String,
    val completeUrl: String,
    val abortUrl: String,
    val callbackUrl: String,
    val callbackMethod: String,
    // JSON body sent to the init endpoint
    val initBody: String,
    // For the course endpoints that return data.thumbnail/data.video; else null
    val courseAssetKey: String?,
    // Callback body template with a __FILE_URL__ placeholder for the final url
    val callbackBodyTemplate: String,
    // For multipart complete/abort we always POST to completeUrl/abortUrl
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("jobId", jobId)
        put("filePath", filePath)
        put("fileSize", fileSize)
        put("title", title)
        put("initUrl", initUrl)
        put("completeUrl", completeUrl)
        put("abortUrl", abortUrl)
        put("callbackUrl", callbackUrl)
        put("callbackMethod", callbackMethod)
        put("initBody", initBody)
        put("courseAssetKey", courseAssetKey ?: JSONObject.NULL)
        put("callbackBodyTemplate", callbackBodyTemplate)
    }

    companion object {
        fun fromJson(o: JSONObject): UploadJobData = UploadJobData(
            jobId = o.getString("jobId"),
            filePath = o.getString("filePath"),
            fileSize = o.getLong("fileSize"),
            title = o.optString("title", "Upload"),
            initUrl = o.getString("initUrl"),
            completeUrl = o.getString("completeUrl"),
            abortUrl = o.getString("abortUrl"),
            callbackUrl = o.getString("callbackUrl"),
            callbackMethod = o.optString("callbackMethod", "POST"),
            initBody = o.getString("initBody"),
            courseAssetKey = if (o.isNull("courseAssetKey")) null else o.optString("courseAssetKey"),
            callbackBodyTemplate = o.getString("callbackBodyTemplate"),
        )
    }
}

/** Parsed init response (direct or multipart). */
data class InitResult(
    val isMultipart: Boolean,
    val uploadUrl: String?,
    val fileUrl: String,
    val key: String?,
    val s3UploadId: String?,
    val parts: List<PartUrl>,
)

data class PartUrl(val partNumber: Int, val uploadUrl: String)

/** Terminal result persisted for the Dart side to reconcile. */
data class UploadResult(
    val jobId: String,
    val status: String, // completed | failed
    val fileUrl: String?,
    val error: String?,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("jobId", jobId)
        put("status", status)
        put("fileUrl", fileUrl ?: "")
        put("error", error ?: "")
        put("completedAt", System.currentTimeMillis())
    }
}

/** Parse the backend init envelope into an [InitResult]. */
object InitParser {
    fun parse(body: String, courseAssetKey: String?): InitResult? {
        return try {
            val root = JSONObject(body)
            // Unwrap { data: {...} }
            var d: JSONObject = root.optJSONObject("data") ?: root
            // Course endpoints nest one more level: data.data.{thumbnail|video}
            val nested = d.optJSONObject("data")
            if (nested != null && (nested.has("thumbnail") || nested.has("video"))) {
                val sectionKey = courseAssetKey ?: "thumbnail"
                nested.optJSONObject(sectionKey)?.let { d = it }
            }
            val isMultipart = d.optBoolean("isMultipart", false)
            val partsArr: JSONArray = d.optJSONArray("parts") ?: JSONArray()
            val parts = ArrayList<PartUrl>()
            for (i in 0 until partsArr.length()) {
                val p = partsArr.getJSONObject(i)
                parts.add(PartUrl(p.optInt("partNumber"), p.optString("uploadUrl")))
            }
            InitResult(
                isMultipart = isMultipart,
                uploadUrl = d.optString("uploadUrl").ifEmpty { null },
                fileUrl = d.optString("fileUrl", ""),
                key = d.optString("key").ifEmpty { null },
                s3UploadId = if (isMultipart) d.optString("uploadId").ifEmpty { null } else null,
                parts = parts,
            )
        } catch (e: Exception) {
            null
        }
    }

    fun extractFileUrl(body: String): String? {
        return try {
            val o = JSONObject(body)
            val data = o.optJSONObject("data")
            (data?.optString("fileUrl") ?: o.optString("fileUrl")).ifEmpty { null }
        } catch (_: Exception) {
            null
        }
    }
}
