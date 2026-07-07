package net.eduverseapp.platform.upload

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkQuery
import java.util.concurrent.TimeUnit

/**
 * Foreground service that keeps the upload alive with a visible notification
 * while WorkManager tasks are running.
 *
 * Started/stopped by [UploadBridgeHandler] on first/last upload — but it also
 * self-heals: on every start it re-checks WorkManager for any non-finished
 * `eduverse_upload_*` work and only stops itself when nothing remains. This
 * makes the service resilient to process death (START_STICKY restarts do not
 * lose accounting, because there is no in-process counter to lose).
 */
class UploadForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "eduverse_upload_service"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val EXTRA_PROGRESS = "progress"
        private const val TAG_PREFIX = "eduverse_upload_"
        private const val POLL_INTERVAL_MS = 15_000L

        fun buildNotification(
            context: Context,
            title: String = "Uploading...",
            content: String = "Processing your files",
            progress: Int = -1,
        ): Notification {
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(content)
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setSilent(true)
                .setOnlyAlertOnce(true)
            if (progress >= 0) {
                builder.setProgress(100, progress, false)
            }
            return builder.build()
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val stopIfIdleRunnable = object : Runnable {
        override fun run() {
            if (hasNoActiveWork()) {
                android.util.Log.d(
                    "UploadForegroundService",
                    "no active upload work — stopping foreground",
                )
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }
            mainHandler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(stopIfIdleRunnable)
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, buildNotification(this))
                scheduleIdleCheck()
            }
            ACTION_UPDATE -> {
                val progress = intent.getIntExtra(EXTRA_PROGRESS, -1)
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(
                        this,
                        progress = progress,
                        content = if (progress >= 0) "Uploading $progress%" else "Processing your files",
                    ),
                )
                scheduleIdleCheck()
            }
            ACTION_STOP -> {
                // Only actually stop if WorkManager confirms nothing is left.
                // Prevents accidental teardown mid-upload from stale intents.
                if (hasNoActiveWork()) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    startForeground(NOTIFICATION_ID, buildNotification(this))
                    scheduleIdleCheck()
                }
            }
            else -> {
                // System restarted the service after being killed (START_STICKY).
                // Must call startForeground() or system kills us with FGS timeout.
                startForeground(NOTIFICATION_ID, buildNotification(this))
                scheduleIdleCheck()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** Poll WorkManager periodically and shut down as soon as no upload work remains. */
    private fun scheduleIdleCheck() {
        mainHandler.removeCallbacks(stopIfIdleRunnable)
        mainHandler.postDelayed(stopIfIdleRunnable, POLL_INTERVAL_MS)
    }

    /** True when no non-finished WorkManager job tagged with our prefix exists. */
    private fun hasNoActiveWork(): Boolean {
        return try {
            val wm = WorkManager.getInstance(applicationContext)
            // Query WorkManager for any non-finished job whose state is one of the
            // "not yet terminal" states. We can't match by tag-prefix, so we scan
            // all non-terminal work and filter by our tag namespace.
            val query = WorkQuery.Builder.fromStates(
                listOf(
                    WorkInfo.State.ENQUEUED,
                    WorkInfo.State.RUNNING,
                    WorkInfo.State.BLOCKED,
                )
            ).build()
            val infos = wm.getWorkInfos(query).get(2, TimeUnit.SECONDS).orEmpty()
            infos.none { info ->
                info.tags.any { it.startsWith(TAG_PREFIX) }
            }
        } catch (e: Exception) {
            // On error, err on the side of keeping the service alive
            android.util.Log.w("UploadForegroundService", "hasNoActiveWork error: ${e.message}")
            false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Upload Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows upload progress"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
