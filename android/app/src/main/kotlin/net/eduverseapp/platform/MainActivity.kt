package net.eduverseapp.platform

import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val videoChannel = "eduverse/video_metadata"
    private val uploadChannel = "eduverse/upload_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        WorkManager.getInstance(this)

        // Video metadata channel (existing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getVideoInfo") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARG", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val retriever = MediaMetadataRetriever()
                        retriever.setDataSource(this, Uri.parse(path))
                        val durationStr =
                            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val duration = (durationStr?.toIntOrNull() ?: 0) / 1000
                        retriever.release()

                        val fileSize = getFileSize(this, path)

                        result.success(
                            mapOf(
                                "duration" to duration,
                                "fileSize" to fileSize,
                            )
                        )
                    } catch (e: Exception) {
                        result.error("METADATA_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // Upload bridge channel (enhanced)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, uploadChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncQueueToNative" -> {
                        val itemsJson = call.argument<String>("itemsJson")
                        if (itemsJson != null) {
                            // Save to state file
                            syncQueueFromFlutter(itemsJson)
                            // Also sync to the running service if it's alive
                            val intent = Intent(this, UploadReschedulerService::class.java).apply {
                                action = UploadReschedulerService.ACTION_SYNC_QUEUE
                                putExtra(UploadReschedulerService.EXTRA_QUEUE_JSON, itemsJson)
                            }
                            try { startService(intent) } catch (_: Exception) {}
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "itemsJson required", null)
                        }
                    }

                    "startNativeUpload" -> {
                        val filePath = call.argument<String>("filePath")
                        val uploadUrl = call.argument<String>("uploadUrl")
                        val fileUrl = call.argument<String>("fileUrl")
                        val title = call.argument<String>("title")
                        val contentType = call.argument<String>("contentType")
                        val uploadType = call.argument<String>("uploadType") ?: "video_post"
                        val authToken = call.argument<String>("authToken")
                        val callbackUrl = call.argument<String>("callbackUrl")
                        val callbackBody = call.argument<String>("callbackBody")
                        val metadata = call.argument<String>("metadata")
                        val itemId = (call.argument<Int>("itemId")?.toLong()
                            ?: call.argument<Long>("itemId")) ?: -1L

                        if (filePath == null || uploadUrl == null) {
                            result.error("INVALID_ARG", "filePath and uploadUrl required", null)
                            return@setMethodCallHandler
                        }

                        // Persist state for crash survival
                        val state = UploadStateManager.load(this)
                        val existingItems = state?.items?.toMutableList() ?: mutableListOf()
                        val newItem = PendingUpload(
                            id = itemId,
                            filePath = filePath,
                            title = title ?: "Upload",
                            uploadUrl = uploadUrl,
                            fileUrl = fileUrl,
                            contentType = contentType,
                            uploadType = uploadType,
                            authToken = authToken,
                            callbackUrl = callbackUrl,
                            callbackBody = callbackBody,
                            metadata = metadata,
                            status = UploadConstants.STATUS_PENDING,
                        )
                        existingItems.removeAll { it.id == itemId }
                        existingItems.add(0, newItem)
                        UploadStateManager.save(this, existingItems, 0, true)

                        result.success(true)
                    }

                    "startQueueProcessing" -> {
                        // Start the native service to process the full queue
                        val state = UploadStateManager.load(this)
                        if (state != null && state.items.isNotEmpty()) {
                            val intent = Intent(this, UploadReschedulerService::class.java).apply {
                                action = UploadReschedulerService.ACTION_PROCESS_QUEUE
                            }
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                        }
                        result.success(true)
                    }

                    "getNativePendingUploads" -> {
                        val state = UploadStateManager.load(this)
                        if (state != null && state.items.isNotEmpty()) {
                            val arr = JSONArray()
                            for (item in state.items) {
                                val obj = JSONObject().apply {
                                    put("id", item.id)
                                    put("filePath", item.filePath)
                                    put("title", item.title)
                                    put("uploadUrl", item.uploadUrl ?: "")
                                    put("fileUrl", item.fileUrl ?: "")
                                    put("contentType", item.contentType ?: "")
                                    put("uploadType", item.uploadType)
                                    put("authToken", item.authToken ?: "")
                                    put("callbackUrl", item.callbackUrl ?: "")
                                    put("callbackBody", item.callbackBody ?: "")
                                    put("metadata", item.metadata ?: "")
                                    put("status", item.status)
                                    put("errorMessage", item.errorMessage ?: "")
                                }
                                arr.put(obj)
                            }
                            result.success(arr.toString())
                        } else {
                            result.success("[]")
                        }
                    }

                    "getNativeQueueStatus" -> {
                        val state = UploadStateManager.load(this)
                        if (state != null) {
                            val pending = state.items.count { it.status == UploadConstants.STATUS_PENDING }
                            val uploading = state.items.count { it.status == UploadConstants.STATUS_UPLOADING }
                            val completed = state.items.count { it.status == UploadConstants.STATUS_COMPLETED }
                            val failed = state.items.count { it.status == UploadConstants.STATUS_FAILED }
                            val statusJson = JSONObject().apply {
                                put("totalItems", state.items.size)
                                put("pending", pending)
                                put("uploading", uploading)
                                put("completed", completed)
                                put("failed", failed)
                                put("isUploading", state.isUploading)
                            }
                            result.success(statusJson.toString())
                        } else {
                            result.success(JSONObject().apply {
                                put("totalItems", 0)
                                put("pending", 0)
                                put("uploading", 0)
                                put("completed", 0)
                                put("failed", 0)
                                put("isUploading", false)
                            }.toString())
                        }
                    }

                    "getNativeQueueItems" -> {
                        val state = UploadStateManager.load(this)
                        if (state != null) {
                            val itemsArr = JSONArray()
                            for (item in state.items) {
                                val obj = JSONObject().apply {
                                    put("id", item.id)
                                    put("title", item.title)
                                    put("status", item.status)
                                    put("progress", item.progress)
                                    put("uploadType", item.uploadType)
                                    put("fileUrl", item.fileUrl ?: "")
                                    put("errorMessage", item.errorMessage ?: "")
                                }
                                itemsArr.put(obj)
                            }
                            val root = JSONObject().apply {
                                put("items", itemsArr)
                                put("isUploading", state.isUploading)
                            }
                            result.success(root.toString())
                        } else {
                            result.success(JSONObject().apply {
                                put("items", JSONArray())
                                put("isUploading", false)
                            }.toString())
                        }
                    }

                    "clearNativeState" -> {
                        UploadStateManager.clear(this)
                        result.success(true)
                    }

                    "processPendingQueue" -> {
                        startNativeUploadService()
                        result.success(true)
                    }

                    "startServiceForUpload" -> {
                        val filePath = call.argument<String>("filePath")
                        val uploadUrl = call.argument<String>("uploadUrl")
                        val title = call.argument<String>("title")
                        val contentType = call.argument<String>("contentType")
                        val uploadType = call.argument<String>("uploadType")
                        val metadata = call.argument<String>("metadata")
                        val itemId = call.argument<Int>("itemId")?.toLong()
                            ?: call.argument<Long>("itemId")

                        val intent = Intent(this, UploadReschedulerService::class.java).apply {
                            action = UploadReschedulerService.ACTION_START_UPLOAD
                            filePath?.let { putExtra(UploadReschedulerService.EXTRA_FILE_PATH, it) }
                            uploadUrl?.let { putExtra(UploadReschedulerService.EXTRA_UPLOAD_URL, it) }
                            title?.let { putExtra(UploadReschedulerService.EXTRA_TITLE, it) }
                            contentType?.let { putExtra(UploadReschedulerService.EXTRA_CONTENT_TYPE, it) }
                            uploadType?.let { putExtra(UploadReschedulerService.EXTRA_UPLOAD_TYPE, it) }
                            metadata?.let { putExtra(UploadReschedulerService.EXTRA_METADATA, it) }
                            itemId?.let { putExtra(UploadReschedulerService.EXTRA_ITEM_ID, it) }
                        }
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }

                    "cancelNativeUpload" -> {
                        val intent = Intent(this, UploadReschedulerService::class.java).apply {
                            action = UploadReschedulerService.ACTION_STOP
                        }
                        stopService(intent)
                        UploadStateManager.clear(this)
                        result.success(true)
                    }

                    "openNotificationSettings" -> {
                        val intent = Intent(
                            android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS
                        ).apply {
                            putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        try { startActivity(intent) } catch (_: Exception) {
                            // Fallback: open app settings
                            val fallback = Intent(
                                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName")
                            )
                            try { startActivity(fallback) } catch (_: Exception) {}
                        }
                        result.success(true)
                    }

                    "scheduleWorkManager" -> {
                        UploadWorker.enqueuePeriodic(this)
                        UploadWorker.enqueueOneTime(this)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun startNativeUploadService() {
        val state = UploadStateManager.load(this) ?: return
        if (state.items.isEmpty()) return

        val intent = Intent(this, UploadReschedulerService::class.java).apply {
            action = UploadReschedulerService.ACTION_PROCESS_QUEUE
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun syncQueueFromFlutter(itemsJson: String) {
        try {
            val arr = JSONArray(itemsJson)
            val items = mutableListOf<PendingUpload>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                items.add(PendingUpload(
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
                    status = UploadConstants.STATUS_PENDING,
                ))
            }
            UploadStateManager.save(this, items, 0, false)
        } catch (_: Exception) {}
    }

    private fun getFileSize(context: Context, uriString: String): Long {
        return try {
            context.contentResolver.openFileDescriptor(Uri.parse(uriString), "r")?.use { pfd ->
                pfd.statSize
            } ?: 0L
        } catch (e: Exception) {
            0L
        }
    }
}
