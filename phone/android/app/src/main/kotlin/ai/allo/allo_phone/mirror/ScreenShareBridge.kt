package ai.allo.allo_phone.mirror

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** No debug implementation or capture service is packaged into release builds. */
object ScreenShareBridge {
    private var channel: MethodChannel? = null
    fun attach(engine: FlutterEngine, activity: Activity) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "ai.allo/screen_share").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                    result.error("unavailable", "개발 빌드에서만 사용할 수 있어요.", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "open" -> {
                            val target = Class.forName("ai.allo.allo_phone.mirror.ScreenShareSetupActivity")
                            activity.startActivity(Intent(activity, target))
                            result.success(true)
                        }
                        "stop" -> {
                            val target = Class.forName("ai.allo.allo_phone.mirror.ScreenShareService")
                            activity.stopService(Intent(activity, target))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("unavailable", "화면 공유를 열 수 없어요.", null)
                }
            }
        }
    }
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
