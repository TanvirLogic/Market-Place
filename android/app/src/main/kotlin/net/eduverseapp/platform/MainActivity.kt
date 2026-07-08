package net.eduverseapp.platform

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import net.eduverseapp.platform.upload.UploadJobData
import net.eduverseapp.platform.upload.UploadManager
import net.eduverseapp.platform.upload.UploadStore
import net.eduverseapp.platform.upload.TokenManager
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val videoChannel = "eduverse/video_metadata"
    private val uploadChannel = "eduverse/native_upload"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Video metadata channel (used by VideoMetadataHelper on the Dart side).
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

        // Native upload bridge — enqueues jobs into the WorkManager pipeline that
        // runs to completion even while the app is killed.
        val store = UploadStore(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, uploadChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncTokens" -> {
                        TokenManager.updateTokens(
                            applicationContext,
                            call.argument<String>("accessToken") ?: "",
                            call.argument<String>("refreshToken") ?: "",
                            call.argument<String>("refreshUrl") ?: "",
                        )
                        result.success(true)
                    }
                    "enqueueUpload" -> {
                        val jobData = call.argument<String>("jobData")
                        if (jobData == null) {
                            result.error("INVALID_ARG", "jobData required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val job = UploadJobData.fromJson(JSONObject(jobData))
                            UploadManager.enqueue(applicationContext, job)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ENQUEUE_ERROR", e.message, null)
                        }
                    }
                    "getCompletedJobs" -> {
                        result.success(store.allResults().map { it.toString() }.toList())
                    }
                    "clearResult" -> {
                        val jobId = call.argument<String>("jobId")
                        if (jobId != null) store.clearResult(jobId)
                        result.success(true)
                    }
                    "cancelAll" -> {
                        UploadManager.cancelAll(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
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
