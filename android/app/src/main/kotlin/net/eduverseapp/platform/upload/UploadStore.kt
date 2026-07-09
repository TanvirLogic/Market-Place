package net.eduverseapp.platform.upload

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * File-backed persistence for the native upload pipeline. Two areas:
 *  - `pending/<jobId>.json`  : the [UploadJobData] for a job not yet finished.
 *    Written when enqueued, deleted when the job reaches a terminal state.
 *  - `results/<jobId>.json`  : the terminal [UploadResult] for the Dart side to
 *    read and reconcile. Deleted once Dart acknowledges via clearResult.
 *
 * Because both live in the app's private filesDir, they survive app kill and
 * device reboot, which is what lets WorkManager resume the queue unattended.
 */
class UploadStore(context: Context) {

    private val pendingDir = File(context.filesDir, "eduverse_upload/pending").apply { mkdirs() }
    private val resultsDir = File(context.filesDir, "eduverse_upload/results").apply { mkdirs() }

    fun savePending(job: UploadJobData) {
        File(pendingDir, "${job.jobId}.json").writeText(job.toJson().toString())
    }

    fun loadPending(jobId: String): UploadJobData? {
        val f = File(pendingDir, "$jobId.json")
        if (!f.exists()) return null
        return try {
            UploadJobData.fromJson(JSONObject(f.readText()))
        } catch (e: Exception) {
            null
        }
    }

    fun deletePending(jobId: String) {
        File(pendingDir, "$jobId.json").delete()
    }

    fun saveResult(result: UploadResult) {
        File(resultsDir, "${result.jobId}.json").writeText(result.toJson().toString())
    }

    fun allResults(): List<JSONObject> {
        return resultsDir.listFiles()
            ?.filter { it.extension == "json" }
            ?.mapNotNull { runCatching { JSONObject(it.readText()) }.getOrNull() }
            ?: emptyList()
    }

    fun clearResult(jobId: String) {
        File(resultsDir, "$jobId.json").delete()
    }

    // MARK: - Progress tracking (read by Dart poll cycle for real-time UI)

    private val progressDir = File(context.filesDir, "eduverse_upload/progress").apply { mkdirs() }

    fun saveProgress(jobId: String, pct: Int) {
        try {
            File(progressDir, "$jobId.json").writeText("{\"progress\":$pct}")
        } catch (_: Exception) {}
    }

    fun loadProgress(jobId: String): Int? {
        val f = File(progressDir, "$jobId.json")
        if (!f.exists()) return null
        return try {
            JSONObject(f.readText()).optInt("progress", -1).let { if (it < 0) null else it }
        } catch (_: Exception) { null }
    }

    fun deleteProgress(jobId: String) {
        try { File(progressDir, "$jobId.json").delete() } catch (_: Exception) {}
    }
}
