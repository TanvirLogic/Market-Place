package net.eduverseapp.platform

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import net.eduverseapp.platform.upload.UploadBridgeHandler

class MainActivity : FlutterActivity() {
    private val videoChannel = "eduverse/video_metadata"
    private val uploadChannel = "eduverse/upload_engine"
    private val progressChannel = "eduverse/upload_progress"
    private var uploadBridgeHandler: UploadBridgeHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

        // Upload engine channel (WorkManager-based — survives app kill)
        val handler = UploadBridgeHandler(this)
        uploadBridgeHandler = handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, uploadChannel)
            .setMethodCallHandler(handler)

        // Upload progress event channel (native -> Dart)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, progressChannel)
            .setStreamHandler(handler.progressStreamHandler)
    }

    override fun onDestroy() {
        uploadBridgeHandler?.dispose()
        uploadBridgeHandler = null
        super.onDestroy()
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
