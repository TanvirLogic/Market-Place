package net.eduverseapp.platform

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class PendingUpload(
    val id: Long,
    val filePath: String,
    val title: String,
    val uploadUrl: String?,
    val fileUrl: String?,
    val contentType: String?,
    val uploadType: String,
    val authToken: String?,
    val callbackUrl: String?,
    val callbackBody: String?,
    val metadata: String?,
    val status: String = UploadConstants.STATUS_PENDING,
    val errorMessage: String? = null,
    val progress: Int = 0,
)

data class UploadState(
    val items: MutableList<PendingUpload>,
    val activeIndex: Int = 0,
    val isUploading: Boolean = false,
)

object UploadStateManager {
    private const val FILE_NAME = "native_uploads.json"

    fun getFile(context: Context): File =
        File(context.filesDir, FILE_NAME)

    fun save(context: Context, items: List<PendingUpload>, activeIndex: Int = 0, isUploading: Boolean = false) {
        try {
            val arr = JSONArray()
            for (item in items) {
                val obj = JSONObject().apply {
                    put("id", item.id)
                    put("filePath", item.filePath)
                    put("title", item.title)
                    put("uploadUrl", item.uploadUrl ?: JSONObject.NULL)
                    put("fileUrl", item.fileUrl ?: JSONObject.NULL)
                    put("contentType", item.contentType ?: JSONObject.NULL)
                    put("uploadType", item.uploadType)
                    put("authToken", item.authToken ?: JSONObject.NULL)
                    put("callbackUrl", item.callbackUrl ?: JSONObject.NULL)
                    put("callbackBody", item.callbackBody ?: JSONObject.NULL)
                    put("metadata", item.metadata ?: JSONObject.NULL)
                    put("status", item.status)
                    put("errorMessage", item.errorMessage ?: JSONObject.NULL)
                    put("progress", item.progress)
                }
                arr.put(obj)
            }
            val root = JSONObject().apply {
                put("items", arr)
                put("activeIndex", activeIndex)
                put("isUploading", isUploading)
                put("lastUpdated", System.currentTimeMillis())
            }
            val file = getFile(context)
            file.parentFile?.mkdirs()
            file.writeText(root.toString(2))
        } catch (_: Exception) {}
    }

    fun load(context: Context): UploadState? {
        return try {
            val file = getFile(context)
            if (!file.exists()) return null
            val content = file.readText()
            if (content.isBlank()) return null
            val root = JSONObject(content)
            val arr = root.getJSONArray("items")
            val items = mutableListOf<PendingUpload>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                items.add(
                    PendingUpload(
                        id = obj.getLong("id"),
                        filePath = obj.getString("filePath"),
                        title = obj.getString("title"),
                        uploadUrl = obj.optString("uploadUrl", null)?.takeIf { it != "null" },
                        fileUrl = obj.optString("fileUrl", null)?.takeIf { it != "null" },
                        contentType = obj.optString("contentType", null)?.takeIf { it != "null" },
                        uploadType = obj.optString("uploadType", "video_post"),
                        authToken = obj.optString("authToken", null)?.takeIf { it != "null" },
                        callbackUrl = obj.optString("callbackUrl", null)?.takeIf { it != "null" },
                        callbackBody = obj.optString("callbackBody", null)?.takeIf { it != "null" },
                        metadata = obj.optString("metadata", null)?.takeIf { it != "null" },
                        status = obj.optString("status", UploadConstants.STATUS_PENDING),
                        errorMessage = obj.optString("errorMessage", null)?.takeIf { it != "null" },
                        progress = obj.optInt("progress", 0),
                    )
                )
            }
            UploadState(
                items = items.toMutableList(),
                activeIndex = root.optInt("activeIndex", 0),
                isUploading = root.optBoolean("isUploading", false),
            )
        } catch (_: Exception) {
            null
        }
    }

    fun clear(context: Context) {
        try {
            getFile(context).delete()
        } catch (_: Exception) {}
    }

    fun removeCompletedAndFailed(context: Context) {
        try {
            val state = load(context) ?: return
            state.items.removeAll { it.status == UploadConstants.STATUS_COMPLETED || it.status == UploadConstants.STATUS_FAILED }
            save(context, state.items, 0, false)
        } catch (_: Exception) {}
    }

    fun getNextPending(context: Context): PendingUpload? {
        val state = load(context) ?: return null
        return state.items.firstOrNull { it.status == UploadConstants.STATUS_PENDING }
    }

    fun markItemStatus(context: Context, itemId: Long, status: String, error: String? = null) {
        try {
            val state = load(context) ?: return
            val index = state.items.indexOfFirst { it.id == itemId }
            if (index == -1) return
            val updated = state.items[index].copy(status = status, errorMessage = error)
            state.items[index] = updated
            save(context, state.items, state.activeIndex, status == UploadConstants.STATUS_UPLOADING)
        } catch (_: Exception) {}
    }

    fun updateItemProgress(context: Context, itemId: Long, progress: Int) {
        try {
            val state = load(context) ?: return
            val index = state.items.indexOfFirst { it.id == itemId }
            if (index == -1) return
            state.items[index] = state.items[index].copy(progress = progress)
            save(context, state.items, state.activeIndex, isUploading = true)
        } catch (_: Exception) {}
    }
}
