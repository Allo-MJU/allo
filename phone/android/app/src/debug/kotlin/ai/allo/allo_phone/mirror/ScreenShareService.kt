package ai.allo.allo_phone.mirror

import android.app.*
import android.content.*
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.DisplayMetrics
import android.view.WindowManager
import ai.allo.mirror.MirrorConfig
import ai.allo.mirror.MirrorTransport
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt

/** Debug-only, single outstanding frame. No frames or connection credentials are persisted. */
class ScreenShareService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val captureThread = HandlerThread("allo-screen-capture")
    private lateinit var captureHandler: Handler
    private val uploads = Executors.newSingleThreadExecutor()
    private val frames = LatestFrameBuffer()
    private val stopped = AtomicBoolean(false)
    private var transport: MirrorTransport? = null
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var screenReceiverRegistered = false
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { stopSelf() }
    }
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() { stopSelf() }
        override fun onCapturedContentVisibilityChanged(isVisible: Boolean) {
            // Avoid repeating stale private content when the selected app is hidden.
            if (!isVisible) stopSelf()
        }
        override fun onCapturedContentResize(width: Int, height: Int) {
            if (width <= 0 || height <= 0 || stopped.get()) return
            captureHandler.post {
                if (!stopped.get()) try { resize(width, height) } catch (_: Exception) { fail() }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        captureThread.start()
        captureHandler = Handler(captureThread.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP || applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            stopSelf(); return START_NOT_STICKY
        }
        if (projection != null || running) return START_NOT_STICKY
        try {
            val config = MirrorConfig.parse(requireNotNull(intent?.getStringExtra("connection")))
            @Suppress("DEPRECATION")
            val consent = requireNotNull(intent.getParcelableExtra<Intent>("projectionData"))
            require(intent.getIntExtra("resultCode", Activity.RESULT_CANCELED) == Activity.RESULT_OK)
            transport = MirrorTransport(config)
            foreground()
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(Activity.RESULT_OK, consent)
            requireNotNull(projection).registerCallback(projectionCallback, main)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
            }
            screenReceiverRegistered = true
            running = true
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
            captureHandler.post {
                if (!stopped.get()) try {
                    val size = dimensions(metrics.widthPixels, metrics.heightPixels)
                    reader = newReader(size.first, size.second)
                    display = projection?.createVirtualDisplay("ALLO screen share", size.first, size.second,
                        resources.displayMetrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                        reader!!.surface, null, captureHandler)
                    check(display != null)
                    captureHandler.post(frameTick)
                } catch (_: Exception) { fail() }
            }
        } catch (_: Exception) { fail() }
        return START_NOT_STICKY
    }

    private fun foreground() {
        val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(NotificationChannel(CHANNEL, "알로 화면 공유", NotificationManager.IMPORTANCE_LOW))
        }
        val stop = PendingIntent.getService(this, 0, Intent(this, ScreenShareService::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder.setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentTitle("알로 화면 공유 중")
            .setContentText("공유를 끝내려면 중지를 눌러 주세요.")
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "중지", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(NOTIFICATION, notification)
    }

    private fun dimensions(width: Int, height: Int): Pair<Int, Int> {
        val scale = minOf(1.0, 640.0 / max(width, height))
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    private fun resize(width: Int, height: Int) {
        val vd = display ?: return
        val (w, h) = dimensions(width, height)
        if (reader?.width == w && reader?.height == h) return
        frames.clear()
        val replacement = newReader(w, h)
        vd.surface = null
        val old = reader
        reader = replacement
        vd.resize(w, h, resources.displayMetrics.densityDpi)
        vd.surface = replacement.surface
        old?.close()
    }

    private fun newReader(width: Int, height: Int): ImageReader =
        ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

    // Poll acquisition rather than discarding callbacks while busy: even the final screen
    // change is acquired on the next tick. Static screens resend the latest JPEG heartbeat.
    private val frameTick = object : Runnable {
        override fun run() {
            if (stopped.get()) return
            try {
                reader?.acquireLatestImage()?.use { image ->
                    val plane = image.planes[0]
                    require(plane.pixelStride == 4 && plane.rowStride >= image.width * 4)
                    val pixels = java.nio.ByteBuffer.allocate(image.width * image.height * 4)
                    for (row in 0 until image.height) {
                        val line = plane.buffer.duplicate()
                        line.position(row * plane.rowStride)
                        line.limit(row * plane.rowStride + image.width * 4)
                        pixels.put(line)
                    }
                    pixels.rewind()
                    val frame = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
                    val bytes = try {
                        frame.copyPixelsFromBuffer(pixels)
                        ByteArrayOutputStream().use { out ->
                            check(frame.compress(Bitmap.CompressFormat.JPEG, 60, out))
                            out.toByteArray()
                        }
                    } finally { frame.recycle() }
                    frames.offer(bytes)
                }
                val bytes = frames.beginUpload(SystemClock.elapsedRealtime())
                if (bytes != null) uploads.execute {
                    try {
                        if (!stopped.get()) check(transport?.upload(bytes) == true)
                    } catch (_: Exception) { fail() }
                    finally { frames.finishUpload() }
                }
                if (!stopped.get()) captureHandler.postDelayed(this, 200)
            } catch (_: Exception) { fail() }
        }
    }

    private fun fail() {
        main.post {
            if (!stopped.get()) {
                android.widget.Toast.makeText(this, "화면 공유가 중지됐어요. 연결 상태를 확인해 주세요.", android.widget.Toast.LENGTH_LONG).show()
                stopSelf()
            }
        }
    }

    override fun onDestroy() {
        stopped.set(true)
        frames.stop()
        captureHandler.removeCallbacks(frameTick)
        if (screenReceiverRegistered) unregisterReceiver(screenOff)
        projection?.unregisterCallback(projectionCallback)
        projection?.stop()
        projection = null
        captureHandler.post {
            display?.release(); display = null
            reader?.close(); reader = null
            captureThread.quitSafely()
        }
        // Ordered after any in-flight upload, so an upload cannot restore a frame after DELETE.
        uploads.execute {
            try { transport?.clear() } catch (_: Exception) { /* relay expires frames */ }
            finally { running = false }
        }
        uploads.shutdown()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?) = null
    companion object {
        @Volatile var running = false
            private set
        private const val CHANNEL = "allo_screen_share"
        private const val NOTIFICATION = 7202
        private const val STOP = "ai.allo.screen_share.STOP"
    }
}
