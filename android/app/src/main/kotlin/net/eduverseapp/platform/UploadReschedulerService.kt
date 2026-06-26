package net.eduverseapp.platform

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class UploadReschedulerService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val isProcessing = AtomicBoolean(false)
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private lateinit var notificationManager: NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_UPLOAD -> {
                val filePath = intent.getStringExtra(EXTRA_FILE_PATH)
                val uploadUrl = intent.getStringExtra(EXTRA_UPLOAD_URL)
                val title = intent.getStringExtra(EXTRA_TITLE)
                val contentType = intent.getStringExtra(EXTRA_CONTENT_TYPE)
                val uploadType = intent.getStringExtra(EXTRA_UPLOAD_TYPE) ?: "video_post"
                val metadata = intent.getStringExtra(EXTRA_METADATA)
                val itemId = intent.getLongExtra(EXTRA_ITEM_ID, -1L)

                if (filePath != null && uploadUrl != null) {
                    startForegroundSafe("Starting: $title", 0, true)
                    processQueue(queue = listOf(
                        PendingUpload(
                            id = itemId, filePath = filePath, title = title ?: "Upload",
                            uploadUrl = uploadUrl, fileUrl = null,
                            contentType = contentType, uploadType = uploadType,
                            authToken = null, callbackUrl = null, callbackBody = null,
                            metadata = metadata,
                            status = UploadConstants.STATUS_PENDING,
                        )
                    ))
                }
            }

            ACTION_PROCESS_QUEUE -> {
                val state = UploadStateManager.load(this)
                if (state != null && state.items.isNotEmpty()) {
                    val items = state.items.sortedBy { it.id }
                    if (startForegroundSafe("Resuming uploads...", 0, true)) {
                        processQueue(items)
                    }
                } else {
                    stopSelf()
                }
            }

            ACTION_SYNC_QUEUE -> {
                val itemsJson = intent.getStringExtra(EXTRA_QUEUE_JSON)
                if (itemsJson != null) {
                    syncQueueFromJson(itemsJson)
                }
            }

            ACTION_STOP -> {
                cleanupAndStop()
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun startForegroundSafe(text: String, progress: Int, indeterminate: Boolean): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                val state = UploadStateManager.load(this)
                state?.items?.forEach { item ->
                    if (item.status == UploadConstants.STATUS_PENDING ||
                        item.status == UploadConstants.STATUS_UPLOADING
                    ) {
                        UploadStateManager.markItemStatus(
                            this, item.id,
                            UploadConstants.STATUS_FAILED,
                            "Notification permission required for background upload"
                        )
                    }
                }
                stopSelf()
                return false
            }
        }
        return try {
            val notification = buildNotification(text, progress, indeterminate)
            startForeground(NOTIFICATION_ID, notification)
            true
        } catch (e: SecurityException) {
            val state = UploadStateManager.load(this)
            state?.items?.forEach { item ->
                if (item.status == UploadConstants.STATUS_PENDING ||
                    item.status == UploadConstants.STATUS_UPLOADING
                ) {
                    UploadStateManager.markItemStatus(
                        this, item.id,
                        UploadConstants.STATUS_FAILED,
                        "Failed to start foreground service: ${e.message}"
                    )
                }
            }
            stopSelf()
            false
        }
    }

    private fun acquireLocks() {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Eduverse:UploadWakeLock"
        ).apply {
            setReferenceCounted(false)
            acquire(60 * 60 * 1000L)
        }

        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        wifiLock = wifiManager.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "Eduverse:UploadWifiLock"
        ).apply {
            acquire()
        }
    }

    private fun releaseLocks() {
        try { wakeLock?.release() } catch (_: Exception) {}
        try { wifiLock?.release() } catch (_: Exception) {}
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val progressChannel = NotificationChannel(
                CHANNEL_ID,
                "Upload Service",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Handles video and file uploads in background"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(progressChannel)

            val completionChannel = NotificationChannel(
                COMPLETION_CHANNEL_ID,
                "Upload Complete",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Alerts when uploads finish"
            }
            notificationManager.createNotificationChannel(completionChannel)
        }
    }

    private fun buildNotification(text: String, progress: Int, indeterminate: Boolean = false): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Asset Upload")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .apply {
                if (indeterminate) {
                    setProgress(0, 0, true)
                } else if (progress > 0) {
                    setProgress(100, progress, false)
                }
            }
            .build()
    }

    private fun processQueue(queue: List<PendingUpload>) {
        if (!isProcessing.compareAndSet(false, true)) return

        executor.execute {
            try {
                var currentBatch = queue.toMutableList()
                var completedCount = 0

                while (true) {
                    var index = 0
                    while (index < currentBatch.size) {
                        val item = currentBatch[index]
                        val globalPos = completedCount + index + 1
                        val totalItems = completedCount + currentBatch.size

                        if (!isNetworkAvailable()) {
                            showPersistentNotification("Waiting for network...", 0, true)
                            if (!waitForNetwork()) {
                                markItemFailed(item, "No network after waiting 5 minutes")
                                index++
                                continue
                            }
                        }

                        val file = File(item.filePath)
                        if (!file.exists() || file.length() == 0L) {
                            markItemFailed(item, "File not found or empty")
                            index++
                            continue
                        }

                        val uploadUrl = resolveUploadUrl(item)
                        if (uploadUrl == null) {
                            markItemFailed(item, "No upload URL available")
                            index++
                            continue
                        }

                        UploadStateManager.markItemStatus(this, item.id, UploadConstants.STATUS_UPLOADING)
                        persistCurrentState(currentBatch, index)

                        val notif = buildNotification(
                            "Uploading ${item.title} ($globalPos/$totalItems)...",
                            0, true,
                        )
                        notificationManager.notify(NOTIFICATION_ID, notif)

                        val s3Success = performS3Upload(
                            file = file,
                            uploadUrl = uploadUrl,
                            title = item.title,
                            contentType = item.contentType ?: "application/octet-stream",
                            queueIndex = globalPos,
                            queueTotal = totalItems,
                            itemId = item.id,
                        )

                        if (!s3Success) {
                            markItemFailed(item, "S3 upload failed after retries")
                            showItemFailedNotification(item)
                            persistCurrentState(currentBatch, index)
                            index++
                            continue
                        }

                        if (item.authToken != null && item.callbackUrl != null && item.callbackBody != null) {
                            val callbackSuccess = performServerCallback(item)
                            if (!callbackSuccess) {
                                markItemFailed(item, "Uploaded to S3 but server callback failed")
                                showItemFailedNotification(item)
                                persistCurrentState(currentBatch, index)
                                index++
                                continue
                            }
                        }

                        markItemCompleted(item)
                        showItemCompleteNotification(item, globalPos, totalItems)
                        persistCurrentState(currentBatch, index)
                        index++
                    }

                    completedCount += currentBatch.size

                    val state = UploadStateManager.load(this)
                    val newPending = state?.items?.filter {
                        it.status == UploadConstants.STATUS_PENDING
                    }?.sortedBy { it.id } ?: break
                    if (newPending.isEmpty()) break
                    currentBatch = newPending.toMutableList()
                }
            } finally {
                isProcessing.set(false)
                showAllCompleteNotification()
                UploadStateManager.removeCompletedAndFailed(this)
                val remaining = UploadStateManager.load(this)
                if (remaining?.items?.isEmpty() != false) {
                    UploadStateManager.clear(this)
                    stopSelf()
                }
            }
        }
    }

    private fun performS3Upload(
        file: File,
        uploadUrl: String,
        title: String,
        contentType: String,
        queueIndex: Int,
        queueTotal: Int,
        itemId: Long = -1L,
    ): Boolean {
        val maxRetries = 3
        val fileSize = file.length()

        for (attempt in 1..maxRetries) {
            var connection: HttpURLConnection? = null
            try {
                val url = URL(uploadUrl)
                connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "PUT"
                connection.setRequestProperty("Content-Type", contentType)
                connection.setRequestProperty("Content-Length", fileSize.toString())
                connection.doOutput = true
                connection.useCaches = false
                connection.connectTimeout = 60000
                connection.readTimeout = 600000

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    connection.setFixedLengthStreamingMode(fileSize)
                }

                val outputStream = connection.outputStream

                FileInputStream(file).use { inputStream ->
                    val buffer = ByteArray(65536)
                    var bytesRead: Int
                    var totalRead = 0L
                    var lastReportedProgress = -1

                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                        totalRead += bytesRead
                        val progress = if (fileSize > 0) {
                            ((totalRead * 100) / fileSize).toInt()
                        } else 0

                        // Report progress on first chunk + every 1% thereafter
                        // The first-chunk report ensures small files show some progress
                        val shouldReport = lastReportedProgress < 0 ||
                            progress >= lastReportedProgress + 1
                        if (shouldReport) {
                            lastReportedProgress = progress
                            if (itemId >= 0) {
                                UploadStateManager.updateItemProgress(
                                    this@UploadReschedulerService, itemId, progress
                                )
                            }
                            val label = "Uploading $title ($queueIndex/$queueTotal)"
                            val notif = buildNotification(label, progress, false)
                            notificationManager.notify(NOTIFICATION_ID, notif)
                        }
                    }
                }

                outputStream.flush()
                outputStream.close()

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    return true
                }

                if (attempt < maxRetries) {
                    val backoff = (attempt * 5000).toLong()
                    Thread.sleep(backoff)
                }
            } catch (e: Exception) {
                if (attempt < maxRetries) {
                    val backoff = (attempt * 5000).toLong()
                    Thread.sleep(backoff)
                }
            } finally {
                try { connection?.disconnect() } catch (_: Exception) {}
            }
        }
        return false
    }

    private fun performServerCallback(item: PendingUpload): Boolean {
        val maxRetries = 3
        for (attempt in 1..maxRetries) {
            var connection: HttpURLConnection? = null
            try {
                val url = URL(item.callbackUrl)
                connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Authorization", "Bearer ${item.authToken}")
                connection.doOutput = true
                connection.useCaches = false
                connection.connectTimeout = 30000
                connection.readTimeout = 30000

                val bodyBytes = item.callbackBody?.toByteArray(Charsets.UTF_8) ?: ByteArray(0)
                connection.setFixedLengthStreamingMode(bodyBytes.size)
                connection.outputStream.write(bodyBytes)
                connection.outputStream.flush()
                connection.outputStream.close()

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    return true
                }

                if (responseCode == 401) return false

                if (attempt < maxRetries) {
                    val backoff = (attempt * 3000).toLong()
                    Thread.sleep(backoff)
                }
            } catch (e: Exception) {
                if (attempt < maxRetries) {
                    val backoff = (attempt * 3000).toLong()
                    Thread.sleep(backoff)
                }
            } finally {
                try { connection?.disconnect() } catch (_: Exception) {}
            }
        }
        return false
    }

    private fun resolveUploadUrl(item: PendingUpload): String? {
        if (!item.uploadUrl.isNullOrBlank()) return item.uploadUrl
        return null
    }

    private fun markItemCompleted(item: PendingUpload) {
        UploadStateManager.markItemStatus(this, item.id, UploadConstants.STATUS_COMPLETED)
    }

    private fun markItemFailed(item: PendingUpload, error: String) {
        UploadStateManager.markItemStatus(this, item.id, UploadConstants.STATUS_FAILED, error)
    }

    private fun persistCurrentState(queue: MutableList<PendingUpload>, activeIndex: Int) {
        val existingState = UploadStateManager.load(this)
        val base = (existingState?.items ?: emptyList()).toMutableList()
        for (item in queue) {
            if (base.none { it.id == item.id }) {
                base.add(item)
            }
        }
        UploadStateManager.save(this, base, activeIndex, isUploading = true)
    }

    private fun showItemCompleteNotification(item: PendingUpload, index: Int, total: Int) {
        val notif = NotificationCompat.Builder(this, COMPLETION_CHANNEL_ID)
            .setContentTitle("Upload Complete")
            .setContentText("${item.title} ($index/$total)")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        notificationManager.notify(NOTIFICATION_ID + 1, notif)
    }

    private fun showItemFailedNotification(item: PendingUpload) {
        val notif = NotificationCompat.Builder(this, COMPLETION_CHANNEL_ID)
            .setContentTitle("Upload Failed")
            .setContentText(item.title)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        notificationManager.notify(NOTIFICATION_ID + 2, notif)
    }

    private fun showAllCompleteNotification() {
        val notif = NotificationCompat.Builder(this, COMPLETION_CHANNEL_ID)
            .setContentTitle("All Uploads Complete")
            .setContentText("All items in the queue have been processed.")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        notificationManager.notify(NOTIFICATION_ID + 3, notif)
    }

    private fun showPersistentNotification(text: String, progress: Int, indeterminate: Boolean) {
        val notif = buildNotification(text, progress, indeterminate)
        notificationManager.notify(NOTIFICATION_ID, notif)
    }

    private fun isNetworkAvailable(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun waitForNetwork(): Boolean {
        if (isNetworkAvailable()) return true

        val latch = CountDownLatch(1)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                latch.countDown()
            }
        }

        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.registerNetworkCallback(
            NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build(),
            callback
        )

        val available = try {
            latch.await(5, TimeUnit.MINUTES)
        } catch (_: InterruptedException) {
            false
        }

        try { cm.unregisterNetworkCallback(callback) } catch (_: Exception) {}

        return available
    }

    private fun syncQueueFromJson(itemsJson: String) {
        try {
            val state = UploadStateManager.load(this)
            val existing = state?.items?.toMutableList() ?: mutableListOf()

            val arr = org.json.JSONArray(itemsJson)
            val newItems = mutableListOf<PendingUpload>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                newItems.add(PendingUpload(
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

            for (newItem in newItems) {
                existing.removeAll { it.id == newItem.id }
                existing.add(newItem)
            }

            UploadStateManager.save(this, existing, 0, false)
        } catch (_: Exception) {}
    }

    private fun cleanupAndStop() {
        isProcessing.set(false)
        UploadStateManager.clear(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        const val CHANNEL_ID = "eduverse_upload_service"
        const val COMPLETION_CHANNEL_ID = "eduverse_upload_complete"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START_UPLOAD = "net.eduverseapp.platform.START_UPLOAD"
        const val ACTION_PROCESS_QUEUE = "net.eduverseapp.platform.PROCESS_QUEUE"
        const val ACTION_SYNC_QUEUE = "net.eduverseapp.platform.SYNC_QUEUE"
        const val ACTION_STOP = "net.eduverseapp.platform.STOP_UPLOAD"

        const val EXTRA_FILE_PATH = "filePath"
        const val EXTRA_UPLOAD_URL = "uploadUrl"
        const val EXTRA_TITLE = "title"
        const val EXTRA_CONTENT_TYPE = "contentType"
        const val EXTRA_UPLOAD_TYPE = "uploadType"
        const val EXTRA_METADATA = "metadata"
        const val EXTRA_ITEM_ID = "itemId"
        const val EXTRA_QUEUE_JSON = "queueJson"
    }
}
