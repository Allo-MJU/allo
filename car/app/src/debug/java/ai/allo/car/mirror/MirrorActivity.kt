package ai.allo.car.mirror

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import ai.allo.car.BuildConfig
import ai.allo.mirror.MirrorConfig
import ai.allo.mirror.MirrorTransport
import java.util.concurrent.Executors

/** Debug-only, non-DO activity. The OS restriction and our independent AAOS gate both apply. */
class MirrorActivity : Activity() {
    companion object {
        private var rememberedConfig: MirrorConfig? = null
        private var closedForDriving = false
        @JvmStatic fun hasConnection(): Boolean = rememberedConfig != null
        @JvmStatic fun takeDrivingTransition(): Boolean = closedForDriving.also { closedForDriving = false }
    }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val policy = MirrorDisplayPolicy()
    private var gate: ParkedMirrorGate? = null
    private var transport: MirrorTransport? = null
    private var foreground = false
    private var fetching = false
    private var lastFetchAt = -1000L
    private var visibleUntil = 0L
    private var displayed: Bitmap? = null
    private lateinit var image: ImageView
    private lateinit var status: TextView
    private lateinit var connection: EditText
    private lateinit var connect: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG) { finish(); return }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_SECURE)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 12, 24, 12)
            setBackgroundColor(Color.BLACK)
        }
        status = TextView(this).apply { setTextColor(Color.WHITE); textSize = 20f }
        layout.addView(status)
        connection = EditText(this).apply {
            hint = "폰과 같은 연결 정보 붙여넣기"
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            maxLines = 3
            isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        layout.addView(connection)
        val actions = LinearLayout(this)
        connect = Button(this).apply {
            text = "화면 보기"
            setOnClickListener { startViewing() }
        }
        actions.addView(connect)
        actions.addView(Button(this).apply {
            text = "연결 중지"
            setOnClickListener { rememberedConfig = null; stopViewing("연결을 중지했어요") }
        })
        actions.addView(Button(this).apply {
            text = "돌아가기"
            setOnClickListener { finish() }
        })
        layout.addView(actions)
        image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "공유 중인 휴대폰 화면"
        }
        layout.addView(image, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(layout)
        status.text = "주차 상태를 확인하고 있어요"
        transport = rememberedConfig?.let { MirrorTransport(it) }
    }

    override fun onStart() {
        super.onStart()
        if (!BuildConfig.DEBUG) return
        foreground = true
        gate = ParkedMirrorGate(this) { connected, parked, allowed ->
            policy.update(connected, foreground, parked, allowed, SystemClock.elapsedRealtime())
            if (parked == false || allowed == false) {
                if (connected && parked == false) closedForDriving = true
                clearImage()
                finish()
                return@ParkedMirrorGate
            }
            if (!policy.allowed(SystemClock.elapsedRealtime())) {
                clearImage()
                status.text = "주차와 화면 표시 허용을 확인해야 볼 수 있어요"
            }
            connect.isEnabled = policy.allowed(SystemClock.elapsedRealtime())
        }.also { it.start() }
        main.post(tick)
    }

    private fun startViewing() {
        if (!policy.allowed(SystemClock.elapsedRealtime())) return
        try {
            val config = MirrorConfig.parse(connection.text.toString())
            val next = MirrorTransport(config)
            rememberedConfig = config
            policy.invalidate()
            transport = next
            clearImage()
            connection.setText("")
            status.text = "폰에서 공유를 시작해 주세요"
        } catch (_: Exception) {
            stopViewing("연결 정보를 확인해 주세요")
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            if (!foreground) return
            val now = SystemClock.elapsedRealtime()
            val allowed = policy.allowed(now)
            connect.isEnabled = allowed
            if (!allowed) {
                // A safety read stalled: fence off outstanding fetches, including repark races.
                policy.invalidate()
                clearImage()
                status.text = "주차와 화면 표시 허용을 확인해야 볼 수 있어요"
            } else {
                if (displayed != null && now >= visibleUntil) {
                    clearImage()
                    status.text = "새 화면을 기다리고 있어요"
                }
                val current = transport
                if (current != null && !fetching && now - lastFetchAt >= 200) fetch(current, now)
            }
            main.postDelayed(this, 100)
        }
    }

    private fun fetch(current: MirrorTransport, requestAt: Long) {
        fetching = true
        lastFetchAt = requestAt
        val ticket = policy.generation
        worker.execute {
            var bitmap: Bitmap? = null
            var age = -1L
            var receivedAt = requestAt
            var failed = false
            try {
                val frame = current.fetch()
                // Transport's age already includes the transfer. Only add decode/UI time below.
                receivedAt = SystemClock.elapsedRealtime()
                if (frame != null) {
                    age = frame.ageMs
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(frame.bytes, 0, frame.bytes.size, bounds)
                    // The prototype emits <=640px. Bound decode memory even for malformed peers.
                    if (bounds.outWidth in 1..640 && bounds.outHeight in 1..640) {
                        bitmap = BitmapFactory.decodeByteArray(frame.bytes, 0, frame.bytes.size)
                        if (bitmap == null) failed = true
                    } else {
                        failed = true
                    }
                }
            } catch (_: Exception) { failed = true }
            val result = bitmap
            val resultAge = age
            val resultReceivedAt = receivedAt
            main.post {
                fetching = false
                val now = SystemClock.elapsedRealtime()
                if (transport !== current || !foreground ||
                    !policy.accepts(ticket, resultAge, resultReceivedAt, now)) {
                    result?.recycle()
                    if (ticket == policy.generation && transport === current) {
                        clearImage()
                        status.text = if (failed) "연결을 확인해 주세요" else "새 화면을 기다리고 있어요"
                    }
                    return@post
                }
                clearImage()
                if (result != null) {
                    displayed = result
                    visibleUntil = now + MirrorDisplayPolicy.remainingMs(resultAge, resultReceivedAt, now)
                    image.setImageBitmap(result)
                    status.text = "폰 화면 공유 중 · 조작은 폰에서 해 주세요"
                } else {
                    status.text = "화면을 읽을 수 없어요. 연결을 확인해 주세요"
                }
            }
        }
    }

    private fun clearImage() {
        if (!::image.isInitialized) return
        image.setImageDrawable(null)
        // ImageView/RenderThread can still reference the prior bitmap until a draw completes.
        // Let GC reclaim displayed bitmaps; only recycle images that were never displayed.
        displayed = null
        visibleUntil = 0
    }

    private fun stopViewing(message: String) {
        policy.invalidate()
        transport = null
        clearImage()
        status.text = message
    }

    override fun onStop() {
        foreground = false
        policy.update(false, false, null, null, SystemClock.elapsedRealtime())
        main.removeCallbacks(tick)
        gate?.close()
        gate = null
        stopViewing("다시 연결해 주세요")
        super.onStop()
        // Never restore a video surface directly after backgrounding or OS driving restriction.
        // MainActivity must establish a fresh parking decision first.
        if (!isFinishing) finish()
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }
}
