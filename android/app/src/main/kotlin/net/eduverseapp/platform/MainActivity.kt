package net.eduverseapp.platform

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val videoChannel = "eduverse/video_metadata"

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
