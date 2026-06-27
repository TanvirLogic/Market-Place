package net.eduverseapp.platform

import android.content.Context

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
    val uploadId: String? = null,
)

data class UploadState(
    val items: MutableList<PendingUpload>,
    val activeIndex: Int = 0,
    val isUploading: Boolean = false,
)

/// In-memory only state manager. No file I/O.
/// State is rebuilt from SQLite on every app restart, so persistence is unnecessary.
object UploadStateManager {
    private var _state: UploadState = UploadState(mutableListOf())

    fun save(context: Context, items: List<PendingUpload>, activeIndex: Int = 0, isUploading: Boolean = false) {
        _state = UploadState(items.toMutableList(), activeIndex, isUploading)
    }

    fun load(context: Context): UploadState? = _state

    fun clear(context: Context) {
        _state = UploadState(mutableListOf())
    }

    fun removeCompletedAndFailed(context: Context) {
        _state.items.removeAll { it.status == UploadConstants.STATUS_COMPLETED || it.status == UploadConstants.STATUS_FAILED }
    }

    fun getNextPending(context: Context): PendingUpload? {
        return _state.items.firstOrNull { it.status == UploadConstants.STATUS_PENDING }
    }

    fun markItemStatus(context: Context, itemId: Long, status: String, error: String? = null) {
        val index = _state.items.indexOfFirst { it.id == itemId }
        if (index == -1) return
        _state.items[index] = _state.items[index].copy(status = status, errorMessage = error)
    }

    fun updateItemProgress(context: Context, itemId: Long, progress: Int) {
        val index = _state.items.indexOfFirst { it.id == itemId }
        if (index == -1) return
        _state.items[index] = _state.items[index].copy(progress = progress)
    }
}
