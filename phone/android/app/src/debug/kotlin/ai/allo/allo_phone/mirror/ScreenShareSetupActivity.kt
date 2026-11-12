package ai.allo.allo_phone.mirror

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import ai.allo.mirror.MirrorConfig

/** Credentials stay in memory and never enter saved state, logs, or screenshots. */
class ScreenShareSetupActivity : Activity() {
    private var connection: String? = null
    private lateinit var notice: TextView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) { finish(); return }
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val padding = (20 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        notice = TextView(this).apply {
            text = "주차 화면 공유 시제품\n연결 정보를 붙여넣고 시스템 화면에서 알로 앱을 선택해 주세요. 소리는 공유하지 않아요."
        }
        val input = EditText(this).apply {
            hint = "연결 정보 붙여넣기"
            isSaveEnabled = false
            importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            maxLines = 4
        }
        val start = Button(this).apply {
            text = "공유할 화면 선택"
            setOnClickListener {
                try {
                    check(!ScreenShareService.running) { "already sharing" }
                    val value = input.text.toString().trim()
                    MirrorConfig.parse(value)
                    connection = value
                    input.text.clear()
                    val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    // Android 14+ defaults to the system choice of a single app or entire screen.
                    // Do not opt out of single-app capture.
                    @Suppress("DEPRECATION")
                    startActivityForResult(manager.createScreenCaptureIntent(), CAPTURE_REQUEST)
                    isEnabled = false
                } catch (_: Exception) {
                    notice.text = "이미 공유 중이면 먼저 중지해 주세요. 연결 정보도 다시 확인해 주세요."
                }
            }
        }
        layout.addView(notice)
        layout.addView(input)
        layout.addView(start)
        layout.addView(Button(this).apply {
            text = "공유 중지하고 돌아가기"
            setOnClickListener { stopService(Intent(this@ScreenShareSetupActivity, ScreenShareService::class.java)); finish() }
        })
        setContentView(android.widget.ScrollView(this).apply { addView(layout) })
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 7203)
        }
    }

    @Deprecated("Platform callback used for debug capture consent")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_REQUEST) return
        val config = connection
        connection = null
        if (resultCode == RESULT_OK && data != null && config != null) {
            try {
                val intent = Intent(this, ScreenShareService::class.java)
                    .putExtra("connection", config)
                    .putExtra("resultCode", resultCode)
                    .putExtra("projectionData", data)
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            } catch (_: Exception) {
                android.widget.Toast.makeText(this, "화면 공유를 시작할 수 없어요.", android.widget.Toast.LENGTH_LONG).show()
            }
        }
        finish()
    }
    companion object { private const val CAPTURE_REQUEST = 7201 }
}
