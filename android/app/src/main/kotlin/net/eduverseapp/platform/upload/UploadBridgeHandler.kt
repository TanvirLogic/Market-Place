package net.eduverseapp.platform.upload

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.lifecycle.LiveData
import androidx.lifecycle.Observer
import androidx.work.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * MethodChannel handler for [CHANNEL].
 *
 * Delegates actual data transfer to WorkManager so uploads survive
 * process death and Android Doze/battery optimizations.
 *
 * Channels:
 *   eduverse/upload_engine    — MethodChannel (Dart → Native)
 *   eduverse/upload_progress  — EventChannel (Native → Dart, progress)
 */
class UploadBridgeHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "eduverse/upload_engine"
        private const val TAG_PREFIX = "eduverse_upload_"

        // Persistent chain-result store. Survives process death so the
        // Dart side can query it via getChainStatus after app relaunch.
        private const val CHAIN_PREFS = "eduverse_upload_chain_status"
        private const val KEY_STATE = "state"      // success|failed|running|unknown
        private const val KEY_FILE_URL = "fileUrl"
        private const val KEY_ERROR = "error"
        private const val KEY_UPDATED_AT = "updatedAt"

        // Maps taskId → workId so we can cancel/resume
        private val workIdMap = ConcurrentHashMap<Long, List<UUID>>()

        // Maps taskId → total file bytes, so byte-level aggregate progress can
        // be computed as (sum of per-part bytes) / totalBytes. Essential for
        // smooth progress on large (300 MB – 2 GB) multipart uploads.
        private val taskTotalBytes = ConcurrentHashMap<Long, Long>()

        internal fun writeChainStatus(
            context: Context,
            taskId: Long,
            state: String,
            fileUrl: String? = null,
            error: String? = null,
        ) {
            val prefs = context.getSharedPreferences(CHAIN_PREFS, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putString("${taskId}_$KEY_STATE", state)
                if (fileUrl != null) putString("${taskId}_$KEY_FILE_URL", fileUrl)
                if (error != null) putString("${taskId}_$KEY_ERROR", error)
                putLong("${taskId}_$KEY_UPDATED_AT", System.currentTimeMillis())
                apply()
            }
        }

        internal fun readChainStatus(context: Context, taskId: Long): Map<String, Any?>? {
            val prefs = context.getSharedPreferences(CHAIN_PREFS, Context.MODE_PRIVATE)
            val state = prefs.getString("${taskId}_$KEY_STATE", null) ?: return null
            return mapOf(
                "state" to state,
                "fileUrl" to prefs.getString("${taskId}_$KEY_FILE_URL", null),
                "error" to prefs.getString("${taskId}_$KEY_ERROR", null),
                "updatedAt" to prefs.getLong("${taskId}_$KEY_UPDATED_AT", 0L),
            )
        }
    }

    // Tracks how many uploads need the foreground service active.
    // WorkManager's SystemForegroundService crashes on API 36 when 9+
    // parallel part workers all call setForeground(), so we manage our own.
    private var activeForegroundCount = 0

    // EventChannel sink for native → Dart progress events
    private var progressEventSink: EventChannel.EventSink? = null

    val progressStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            progressEventSink = events
        }

        override fun onCancel(arguments: Any?) {
            progressEventSink = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "directUpload" -> onDirectUpload(call, result)
            "uploadParts" -> onUploadParts(call, result)
            "getUploadStatus" -> onGetUploadStatus(call, result)
            "getChainStatus" -> onGetChainStatus(call, result)
            "cancelTask" -> onCancelTask(call, result)
            "scheduleCallback" -> onScheduleCallback(call, result)
            "scheduleCompleteAndCallback" -> onScheduleCompleteAndCallback(call, result)
            else -> result.notImplemented()
        }
    }

    /** Build upload constraints, honoring the Wi-Fi-only preference. */
    private fun buildConstraints(wifiOnly: Boolean): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(
                if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED
            )
            .build()

    // ── Direct upload (single PUT) ──

    private fun onDirectUpload(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId") ?: return result.error("INVALID_ARG", "taskId required", null)
        val filePath = call.arg<String>("filePath") ?: return result.error("INVALID_ARG", "filePath required", null)
        val uploadUrl = call.arg<String>("uploadUrl") ?: return result.error("INVALID_ARG", "uploadUrl required", null)
        val contentType = call.arg<String>("contentType") ?: "application/octet-stream"
        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false

        android.util.Log.d("UploadBridge", "onDirectUpload taskId=$taskId filePath=$filePath uploadUrl=$uploadUrl wifiOnly=$wifiOnly")

        if (!File(Uri.parse(filePath).path ?: filePath).exists()) {
            android.util.Log.e("UploadBridge", "File not found: $filePath")
            result.error("FILE_NOT_FOUND", "File not found: $filePath", null)
            return
        }

        val inputData = Data.Builder()
            .putString("uploadUrl", uploadUrl)
            .putString("filePath", filePath)
            .putString("contentType", contentType)
            .putLong("taskId", taskId)
            .putInt("partNumber", 0)
            .putLong("startByte", 0L)
            .putLong("partLength", 0L)
            .build()

        val workRequest = OneTimeWorkRequestBuilder<UploadWorker>()
            .setInputData(inputData)
            .setConstraints(buildConstraints(wifiOnly))
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                10,
                TimeUnit.SECONDS
            )
            .addTag("${TAG_PREFIX}${taskId}_0")
            .addTag("${TAG_PREFIX}${taskId}")
            .build()

        workIdMap[taskId] = listOf(workRequest.id)
        android.util.Log.d("UploadBridge", "enqueuing work ${workRequest.id} for task $taskId")
        WorkManager.getInstance(context).enqueue(workRequest)
        startForegroundService()

        // Observe and return result when done
        observeWork(taskId, listOf(workRequest.id), result, isMultipart = false)
    }

    // ── Multipart upload (separate WorkManager task per part) ──

    private fun onUploadParts(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId") ?: return result.error("INVALID_ARG", "taskId required", null)
        val filePath = call.arg<String>("filePath") ?: return result.error("INVALID_ARG", "filePath required", null)
        val partsArgs = call.arg<List<Map<String, Any?>>>("parts") ?: return result.error("INVALID_ARG", "parts required", null)
        val partSize = call.intArg("partSize") ?: return result.error("INVALID_ARG", "partSize required", null)
        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false

        android.util.Log.d("UploadBridge", "onUploadParts taskId=$taskId partsCount=${partsArgs.size} partSize=$partSize wifiOnly=$wifiOnly")

        val file = File(Uri.parse(filePath).path ?: filePath)
        if (!file.exists()) {
            android.util.Log.e("UploadBridge", "File not found: $filePath")
            result.error("FILE_NOT_FOUND", "File not found: $filePath", null)
            return
        }

        val fileSize = file.length()
        taskTotalBytes[taskId] = fileSize
        val workRequests = mutableListOf<OneTimeWorkRequest>()
        val workIds = mutableListOf<UUID>()

        for (partArg in partsArgs) {
            val partNumber = (partArg["partNumber"] as Number).toInt()
            val uploadUrl = partArg["uploadUrl"] as String
            val startByte = (partNumber - 1).toLong() * partSize
            val partLength = minOf(startByte + partSize, fileSize) - startByte
            android.util.Log.d("UploadBridge", "  part=$partNumber startByte=$startByte partLength=$partLength url=$uploadUrl")

            val inputData = Data.Builder()
                .putString("uploadUrl", uploadUrl)
                .putString("filePath", filePath)
                .putString("contentType", "application/octet-stream")
                .putLong("taskId", taskId)
                .putInt("partNumber", partNumber)
                .putLong("startByte", startByte)
                .putLong("partLength", partLength)
                .build()

            val workRequest = OneTimeWorkRequestBuilder<UploadWorker>()
                .setInputData(inputData)
                .setConstraints(buildConstraints(wifiOnly))
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
                .addTag("${TAG_PREFIX}${taskId}_$partNumber")
                .addTag("${TAG_PREFIX}${taskId}")
                .build()

            workRequests.add(workRequest)
            workIds.add(workRequest.id)
        }

        workIdMap[taskId] = workIds

        // Enqueue all parts in parallel
        android.util.Log.d("UploadBridge", "enqueuing ${workRequests.size} workers for task $taskId")
        WorkManager.getInstance(context)
            .beginWith(workRequests)
            .enqueue()
        startForegroundService()

        // Observe all and return when done
        observeWork(taskId, workIds, result, isMultipart = true)
    }

    // ── Query upload status (used by _resume after app relaunch) ──

    private fun onGetUploadStatus(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId") ?: return result.error("INVALID_ARG", "taskId required", null)

        val tag = "${TAG_PREFIX}${taskId}"
        val workInfos = WorkManager.getInstance(context)
            .getWorkInfosByTag(tag)
            .get(5, TimeUnit.SECONDS)

        val completed = mutableListOf<Map<String, Any?>>()
        val failed = mutableListOf<Map<String, Any?>>()

        for (info in workInfos) {
            val partNumber = info.progress.getInt("partNumber", 0)

            when (info.state) {
                WorkInfo.State.SUCCEEDED -> {
                    completed.add(mapOf(
                        "partNumber" to partNumber,
                        "eTag" to (info.outputData.getString("eTag") ?: ""),
                        "success" to true,
                    ))
                }
                WorkInfo.State.FAILED -> {
                    failed.add(mapOf(
                        "partNumber" to partNumber,
                        "success" to false,
                        "errorMessage" to (info.outputData.getString("error") ?: "Unknown"),
                    ))
                }
                else -> {
                    // Still running or enqueued — not yet complete
                }
            }
        }

        val allDone = workInfos.all { it.state.isFinished }
        result.success(mapOf(
            "completed" to completed,
            "failed" to failed,
            "allDone" to allDone,
            "totalParts" to workInfos.size,
        ))
    }

    // ── Query native complete+callback chain status (survives app kill) ──

    private fun onGetChainStatus(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId") ?: return result.error("INVALID_ARG", "taskId required", null)

        // First, check persisted state from SharedPreferences (fastest,
        // works even if WorkManager already GC'd the finished jobs).
        val persisted = readChainStatus(context, taskId)
        if (persisted != null && persisted["state"] != "running") {
            result.success(persisted)
            return
        }

        // No persisted terminal state — inspect live WorkManager records
        // (they may still be running after a process restart).
        val chainTag = "${TAG_PREFIX}chain_${taskId}"
        val callbackTag = "${TAG_PREFIX}callback_${taskId}"
        val completeTag = "${TAG_PREFIX}complete_${taskId}"
        val wm = WorkManager.getInstance(context)
        val chainInfos = try {
            wm.getWorkInfosByTag(chainTag).get(3, TimeUnit.SECONDS)
        } catch (_: Exception) { emptyList<WorkInfo>() }
        val callbackInfos = try {
            wm.getWorkInfosByTag(callbackTag).get(3, TimeUnit.SECONDS)
        } catch (_: Exception) { emptyList<WorkInfo>() }
        val completeInfos = try {
            wm.getWorkInfosByTag(completeTag).get(3, TimeUnit.SECONDS)
        } catch (_: Exception) { emptyList<WorkInfo>() }

        val combined = (chainInfos + callbackInfos + completeInfos)
            .distinctBy { it.id }

        if (combined.isEmpty()) {
            // Fall back to persisted "running" if we set it earlier but jobs
            // are already gone; otherwise unknown.
            result.success(persisted ?: mapOf("state" to "unknown"))
            return
        }

        if (combined.any { !it.state.isFinished }) {
            result.success(mapOf("state" to "running"))
            return
        }

        val callbackInfo = combined.firstOrNull { it.tags.contains(callbackTag) }
        val completeInfo = combined.firstOrNull { it.tags.contains(completeTag) }
        val cbSuccess = callbackInfo?.outputData?.getBoolean("callbackSuccess", false) ?: false
        val fileUrl = completeInfo?.outputData?.getString("fileUrl")
        val error = callbackInfo?.outputData?.getString("error")
            ?: completeInfo?.outputData?.getString("error")

        val state = if (cbSuccess) "success" else "failed"
        // Cache in prefs so future queries are cheap and outlive WM GC
        writeChainStatus(context, taskId, state, fileUrl = fileUrl?.ifEmpty { null }, error = error)

        result.success(mapOf(
            "state" to state,
            "fileUrl" to fileUrl,
            "error" to error,
        ))
    }

    // ── Cancel ──

    private fun onCancelTask(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId")
        if (taskId != null) {
            WorkManager.getInstance(context)
                .cancelAllWorkByTag("${TAG_PREFIX}$taskId")
            workIdMap.remove(taskId)
        }
        result.success(true)
    }

    // ── Schedule native CallbackWorker (survives app kill) ──

    private fun onScheduleCallback(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId") ?: return result.error("INVALID_ARG", "taskId required", null)
        val callbackUrl = call.arg<String>("callbackUrl") ?: return result.error("INVALID_ARG", "callbackUrl required", null)
        val callbackBody = call.arg<String>("callbackBody") ?: return result.error("INVALID_ARG", "callbackBody required", null)
        val authToken = call.arg<String>("authToken") ?: return result.error("INVALID_ARG", "authToken required", null)
        val idempotencyKey = call.arg<String>("idempotencyKey")
        val refreshEndpoint = call.arg<String>("refreshEndpoint")
        val refreshToken = call.arg<String>("refreshToken")

        android.util.Log.d("UploadBridge", "onScheduleCallback taskId=$taskId url=$callbackUrl")

        val inputData = Data.Builder()
            .putString("callbackUrl", callbackUrl)
            .putString("callbackBody", callbackBody)
            .putString("authToken", authToken)
            .putLong("taskId", taskId)
            .apply {
                if (idempotencyKey != null) putString("idempotencyKey", idempotencyKey)
                if (refreshEndpoint != null) putString("refreshEndpoint", refreshEndpoint)
                if (refreshToken != null) putString("refreshToken", refreshToken)
            }
            .build()

        val callbackWork = OneTimeWorkRequestBuilder<CallbackWorker>()
            .setInputData(inputData)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .addTag("${TAG_PREFIX}callback_${taskId}")
            .addTag("${TAG_PREFIX}${taskId}")
            .build()

        val workId = callbackWork.id
        val tag = "${TAG_PREFIX}callback_${taskId}"
        val liveData = WorkManager.getInstance(context)
            .getWorkInfosByTagLiveData(tag)

        // Mark chain as running so a killed-then-restarted app can see
        // "still running" instead of "unknown" via getChainStatus.
        writeChainStatus(context, taskId, "running")

        // Guards against the LiveData observer delivering a finished state more
        // than once, which would call result.success() twice and crash with
        // "Reply already submitted".
        val replied = AtomicBoolean(false)

        val observer = object : Observer<List<WorkInfo>> {
            override fun onChanged(workInfos: List<WorkInfo>) {
                if (workInfos.isEmpty()) return
                val info = workInfos.first()
                android.util.Log.d("UploadBridge", "scheduleCallback task=$taskId state=${info.state}")
                if (!info.state.isFinished) return

                // Only reply once, even if onChanged re-fires.
                if (!replied.compareAndSet(false, true)) return

                android.util.Log.d("UploadBridge", "scheduleCallback task=$taskId DONE")
                liveData.removeObserver(this)
                stopForegroundService()

                val cbSuccess = info.outputData.getBoolean("callbackSuccess", false)
                val error = info.outputData.getString("error")
                writeChainStatus(
                    context,
                    taskId,
                    if (cbSuccess) "success" else "failed",
                    error = error,
                )
                result.success(mapOf(
                    "success" to cbSuccess,
                    "errorMessage" to error,
                ))
            }
        }

        liveData.observeForever(observer)
        android.util.Log.d("UploadBridge", "enqueuing CallbackWorker $workId for task $taskId")
        WorkManager.getInstance(context).enqueue(callbackWork)
        startForegroundService()
    }

    // ── Schedule native CompleteWorker + CallbackWorker (multipart survival) ──

    private fun onScheduleCompleteAndCallback(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.longArg("taskId") ?: return result.error("INVALID_ARG", "taskId required", null)
        val completeUrl = call.arg<String>("completeUrl") ?: return result.error("INVALID_ARG", "completeUrl required", null)
        val completeBody = call.arg<String>("completeBody") ?: return result.error("INVALID_ARG", "completeBody required", null)
        val callbackUrl = call.arg<String>("callbackUrl") ?: return result.error("INVALID_ARG", "callbackUrl required", null)
        val callbackBody = call.arg<String>("callbackBody") ?: return result.error("INVALID_ARG", "callbackBody required", null)
        val authToken = call.arg<String>("authToken") ?: return result.error("INVALID_ARG", "authToken required", null)
        val idempotencyKey = call.arg<String>("idempotencyKey")
        val refreshEndpoint = call.arg<String>("refreshEndpoint")
        val refreshToken = call.arg<String>("refreshToken")

        android.util.Log.d("UploadBridge", "onScheduleCompleteAndCallback taskId=$taskId")

        val completeInput = Data.Builder()
            .putString("completeUrl", completeUrl)
            .putString("completeBody", completeBody)
            .putString("authToken", authToken)
            .putLong("taskId", taskId)
            .apply {
                if (refreshEndpoint != null) putString("refreshEndpoint", refreshEndpoint)
                if (refreshToken != null) putString("refreshToken", refreshToken)
            }
            .build()

        val completeWork = OneTimeWorkRequestBuilder<CompleteWorker>()
            .setInputData(completeInput)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .addTag("${TAG_PREFIX}complete_${taskId}")
            .addTag("${TAG_PREFIX}${taskId}")
            .build()

        val callbackInput = Data.Builder()
            .putString("callbackUrl", callbackUrl)
            .putString("callbackBody", callbackBody)
            .putString("authToken", authToken)
            .putLong("taskId", taskId)
            .apply {
                if (idempotencyKey != null) putString("idempotencyKey", idempotencyKey)
                if (refreshEndpoint != null) putString("refreshEndpoint", refreshEndpoint)
                if (refreshToken != null) putString("refreshToken", refreshToken)
            }
            .build()

        val chainTag = "${TAG_PREFIX}chain_${taskId}"
        val callbackWork = OneTimeWorkRequestBuilder<CallbackWorker>()
            .setInputData(callbackInput)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .addTag("${TAG_PREFIX}callback_${taskId}")
            .addTag(chainTag)
            .addTag("${TAG_PREFIX}${taskId}")
            .build()

        // Chain: complete → callback
        WorkManager.getInstance(context)
            .beginWith(completeWork)
            .then(callbackWork)
            .enqueue()

        // Mark chain as running so a killed-then-restarted app can see
        // "still running" instead of "unknown" via getChainStatus.
        writeChainStatus(context, taskId, "running")

        val liveData = WorkManager.getInstance(context)
            .getWorkInfosByTagLiveData(chainTag)

        val chainWorkIds = listOf(completeWork.id, callbackWork.id)
        workIdMap[taskId] = chainWorkIds

        // Guards against replying to Flutter more than once (crash:
        // "Reply already submitted") if the observer re-fires after finishing.
        val replied = AtomicBoolean(false)

        val observer = object : Observer<List<WorkInfo>> {
            override fun onChanged(workInfos: List<WorkInfo>) {
                if (workInfos.isEmpty()) return
                val states = workInfos.map { "${it.id}:${it.state.name}" }
                android.util.Log.d("UploadBridge", "complete+callback task=$taskId states=$states")

                if (!workInfos.all { it.state.isFinished }) return

                // Only reply once, even if onChanged re-fires.
                if (!replied.compareAndSet(false, true)) return

                android.util.Log.d("UploadBridge", "complete+callback task=$taskId ALL FINISHED")
                liveData.removeObserver(this)
                stopForegroundService()

                val callbackInfo = workInfos.firstOrNull { it.tags.contains("${TAG_PREFIX}callback_${taskId}") }
                val completeInfo = workInfos.firstOrNull { it.tags.contains("${TAG_PREFIX}complete_${taskId}") }

                val cbSuccess = callbackInfo?.outputData?.getBoolean("callbackSuccess", false) ?: false
                val fileUrl = completeInfo?.outputData?.getString("fileUrl") ?: ""
                val error = callbackInfo?.outputData?.getString("error")
                    ?: completeInfo?.outputData?.getString("error")

                writeChainStatus(
                    context,
                    taskId,
                    if (cbSuccess) "success" else "failed",
                    fileUrl = fileUrl.ifEmpty { null },
                    error = error,
                )

                result.success(mapOf(
                    "success" to cbSuccess,
                    "fileUrl" to fileUrl,
                    "errorMessage" to error,
                ))
            }
        }

        liveData.observeForever(observer)
        startForegroundService()
    }

    // ── Observe Worker result ──

    private fun observeWork(
        taskId: Long,
        workIds: List<UUID>,
        result: MethodChannel.Result,
        isMultipart: Boolean,
    ) {
        val tag = "${TAG_PREFIX}${taskId}"
        val liveData = WorkManager.getInstance(context)
            .getWorkInfosByTagLiveData(tag)

        // Guards against replying to Flutter more than once (crash:
        // "Reply already submitted") if the observer re-fires after finishing.
        val replied = AtomicBoolean(false)

        val observer = object : Observer<List<WorkInfo>> {
            override fun onChanged(workInfos: List<WorkInfo>) {
                if (workInfos.isEmpty()) return

                val states = workInfos.map { "${it.id}:${it.state.name}" }
                android.util.Log.d("UploadBridge", "observeWork task=$taskId states=$states")
                pushProgress(workInfos, taskId, isMultipart)

                if (!workInfos.all { it.state.isFinished }) return

                // Only reply once, even if onChanged re-fires.
                if (!replied.compareAndSet(false, true)) return

                android.util.Log.d("UploadBridge", "observeWork task=$taskId ALL FINISHED")
                stopForegroundService()
                liveData.removeObserver(this)
                taskTotalBytes.remove(taskId)

                if (isMultipart) {
                    val partResults = workInfos.map { info ->
                        val partNum = info.outputData.getInt("partNumber", 0)
                        if (info.state == WorkInfo.State.SUCCEEDED) {
                            mapOf(
                                "partNumber" to partNum,
                                "success" to true,
                                "eTag" to (info.outputData.getString("eTag") ?: ""),
                            )
                        } else {
                            mapOf(
                                "partNumber" to partNum,
                                "success" to false,
                                "errorMessage" to (info.outputData.getString("error") ?: "Work failed"),
                            )
                        }
                    }
                    android.util.Log.d("UploadBridge", "observeWork multipart result=$partResults")
                    result.success(partResults)
                } else {
                    val succeeded = workInfos.any { it.state == WorkInfo.State.SUCCEEDED }
                    val msg = if (!succeeded) workInfos.firstOrNull()?.outputData?.getString("error") else null
                    android.util.Log.d("UploadBridge", "observeWork direct succeeded=$succeeded error=$msg")
                    result.success(mapOf(
                        "success" to succeeded,
                        "errorMessage" to msg,
                    ))
                }
            }
        }

        liveData.observeForever(observer)
    }

    private fun pushProgress(workInfos: List<WorkInfo>, taskId: Long, isMultipart: Boolean) {
        val sink = progressEventSink
        val pct: Int
        if (isMultipart) {
            val completed = workInfos.count { it.state == WorkInfo.State.SUCCEEDED }
            val total = workInfos.size

            // ── Byte-level aggregate progress ──
            // Sum bytes across all part-workers: SUCCEEDED parts count their
            // full size, RUNNING parts count their live in-flight bytes.
            // This produces a smooth 0–100% for large files instead of coarse
            // completed-part jumps (e.g. 0% → 11% → 22% for a 9-part 2 GB file).
            val totalBytes = taskTotalBytes[taskId] ?: 0L
            var uploadedBytes = 0L
            for (info in workInfos) {
                when (info.state) {
                    WorkInfo.State.SUCCEEDED -> {
                        val partBytes = info.outputData.getLong("partTotalBytes", 0L)
                        uploadedBytes += partBytes
                    }
                    WorkInfo.State.RUNNING -> {
                        uploadedBytes += info.progress.getLong("bytesUploaded", 0L)
                    }
                    else -> { /* enqueued / blocked contribute 0 */ }
                }
            }

            val byteFraction = if (totalBytes > 0) {
                (uploadedBytes.toDouble() / totalBytes).coerceIn(0.0, 1.0)
            } else {
                // Fallback to part-count if we don't know the file size
                if (total > 0) completed.toDouble() / total else 0.0
            }
            pct = (byteFraction * 100).toInt().coerceIn(0, 100)

            android.util.Log.d(
                "UploadBridge",
                "pushProgress multipart task=$taskId parts=$completed/$total bytes=$uploadedBytes/$totalBytes ($pct%)",
            )
            sink?.success(mapOf(
                "taskId" to taskId,
                "type" to "multipartProgress",
                "completed" to completed,
                "total" to total,
                "uploadedBytes" to uploadedBytes,
                "totalBytes" to totalBytes,
                "progress" to byteFraction,
            ))
        } else {
            // Direct upload: prefer byte-level, fall back to legacy fraction.
            val info = workInfos.firstOrNull()
            val uploaded = info?.progress?.getLong("bytesUploaded", 0L) ?: 0L
            val partTotal = info?.progress?.getLong("partTotalBytes", 0L) ?: 0L
            val progress = if (partTotal > 0) {
                (uploaded.toDouble() / partTotal).coerceIn(0.0, 1.0)
            } else {
                info?.progress?.getDouble("progress", 0.0) ?: 0.0
            }
            pct = (progress * 100).toInt().coerceIn(0, 100)
            android.util.Log.d("UploadBridge", "pushProgress direct task=$taskId progress=$progress ($pct%)")
            sink?.success(mapOf(
                "taskId" to taskId,
                "type" to "directProgress",
                "progress" to progress,
            ))
        }
        // Update the notification with progress percentage
        updateNotification(pct)
    }

    private fun updateNotification(pct: Int) {
        val intent = Intent(context, UploadForegroundService::class.java).apply {
            action = UploadForegroundService.ACTION_UPDATE
            putExtra(UploadForegroundService.EXTRA_PROGRESS, pct)
        }
        // Starting/updating a foreground service is not allowed while the app
        // is in the background on Android 12+. If it fails, swallow it — the
        // upload itself continues via WorkManager; only the progress
        // notification is skipped.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.w("UploadBridge", "updateNotification skipped: ${e.message}")
        }
    }

    fun dispose() {
        progressEventSink = null
        // WorkManager tasks continue independently
    }

    // ── Foreground service management ──

    private fun startForegroundService() {
        activeForegroundCount++
        android.util.Log.d("UploadBridge", "startForegroundService count=$activeForegroundCount")
        if (activeForegroundCount == 1) {
            val intent = Intent(context, UploadForegroundService::class.java).apply {
                action = UploadForegroundService.ACTION_START
            }
            // Android 12+ forbids starting an FGS from the background. If the
            // app is backgrounded when a chain worker schedules, this throws.
            // Swallow it — WorkManager keeps the upload alive on its own; we
            // just lose the custom progress notification for this leg.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                android.util.Log.w("UploadBridge", "startForegroundService skipped: ${e.message}")
                // Keep count consistent so stop logic still balances.
            }
        }
    }

    private fun stopForegroundService() {
        activeForegroundCount--
        android.util.Log.d("UploadBridge", "stopForegroundService count=$activeForegroundCount")
        if (activeForegroundCount <= 0) {
            activeForegroundCount = 0
            val intent = Intent(context, UploadForegroundService::class.java).apply {
                action = UploadForegroundService.ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (e: Exception) {
                android.util.Log.w("UploadBridge", "stopForegroundService skipped: ${e.message}")
            }
        }
    }
}

/** Convenience extension for nullable call.argument.
 *  Flutter sends all [int] as Java [Long]; cast via [Number] instead
 *  of a direct generic cast to avoid ClassCastException. */
private fun MethodCall.intArg(key: String): Int? =
    (argument<Any>(key) as? Number)?.toInt()

private fun MethodCall.longArg(key: String): Long? =
    (argument<Any>(key) as? Number)?.toLong()

@Suppress("UNCHECKED_CAST")
private fun <T> MethodCall.arg(key: String): T? = argument<T>(key)
