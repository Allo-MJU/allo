package ai.allo.allo_phone

import android.app.Activity
import android.app.Application
import android.os.Build
import android.os.Bundle
import org.json.JSONObject
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter ↔ Unity 탐험 화면 연결 (Unity as a Library).
 *
 * - Flutter → Unity: `send` → `UnityPlayer.UnitySendMessage("FlutterBridge", "OnFlutterMessage", json)`
 * - Unity → Flutter: C# 가 [fromUnity] 를 부르고, 메인 스레드에서 Flutter 로 `fromUnity` 를 보낸다
 * - Unity 클래스는 리플렉션으로 부른다. Unity 내보내기 결과가 없어도 이 파일은 컴파일된다
 * - 닫을 때 Unity 를 종료하지 않는다 (같은 프로세스라 앱이 같이 죽는다). Flutter 화면을 앞으로 가져온다
 */
object ExploreBridge {
    private const val TAG = "ExploreBridge"
    private const val CHANNEL = "allo/explore"
    private const val UNITY_PLAYER = "com.unity3d.player.UnityPlayer"
    private const val UNITY_ACTIVITY = "com.unity3d.player.UnityPlayerActivity"

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var host: Activity? = null
    private var appMode = false
    private var readyActivity: Activity? = null
    private var application: Application? = null
    private val activityCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) { main.post { updateNativeBack() } }
        override fun onActivityDestroyed(activity: Activity) {
            if (readyActivity === activity) readyActivity = null
            updateNativeBack()
        }
        override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    }

    fun attach(engine: FlutterEngine, activity: Activity) {
        detach()
        host = activity
        if (Build.VERSION.SDK_INT >= 33) {
            application = activity.application.also { it.registerActivityLifecycleCallbacks(activityCallbacks) }
        }
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(unityAvailable())
                    "open" -> result.success(open())
                    "send" -> {
                        send(call.arguments as String)
                        result.success(null)
                    }
                    "close" -> { // Flutter 가 먼저 내린다 (주행 종료·도착)
                        closeUnity()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        appMode = false
        readyActivity = null
        if (Build.VERSION.SDK_INT >= 33) NativeBackApi33.clear()
        application?.unregisterActivityLifecycleCallbacks(activityCallbacks)
        application = null
        channel?.setMethodCallHandler(null)
        channel = null
        host = null
    }

    private fun unityAvailable(): Boolean =
        runCatching { Class.forName(UNITY_PLAYER); true }.getOrDefault(false)

    private fun open(): Boolean {
        val activity = host ?: return false
        if (!unityAvailable()) return false
        activity.startActivity(
            Intent().setClassName(activity, UNITY_ACTIVITY)
                .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
        )
        return true
    }

    private fun send(json: String) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post { send(json) }
            return
        }
        val settings = runCatching { JSONObject(json) }.getOrNull()
        if (settings?.optString("type") == "settings") {
            appMode = settings.optBoolean("appMode", false)
            updateNativeBack()
        }
        runCatching {
            Class.forName(UNITY_PLAYER)
                .getMethod("UnitySendMessage", String::class.java, String::class.java, String::class.java)
                .invoke(null, "FlutterBridge", "OnFlutterMessage", json)
        }.onFailure { Log.w(TAG, "send failed") }
    }

    /**
     * Flutter 화면을 다시 앞으로 가져온다. Unity 는 종료하지 않고 뒤에 남는다.
     * 지금 앞에 떠 있는 Unity 화면에서 부른다 (백그라운드에서 부르면 실행 제한에 막힐 수 있고,
     * Unity 를 moveTaskToBack 하면 Flutter 대신 홈 화면이 드러날 수 있다).
     */
    private fun closeUnity() {
        val from = currentUnityActivity() ?: host ?: return
        from.startActivity(
            Intent(from, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
    }

    /** Unity(C#) 가 부른다. `close` 면 Flutter 화면을 앞으로 가져온다 ([closeUnity]) */
    @JvmStatic
    fun fromUnity(json: String) {
        Log.i(TAG, "Unity message received")
        main.post {
            if (runCatching { JSONObject(json).optString("type") }.getOrNull() == "ready") {
                readyActivity = currentUnityActivity()
            }
            updateNativeBack()
            if (json.contains("\"type\":\"close\"")) closeUnity()
            channel?.invokeMethod("fromUnity", json)
        }
    }

    private fun currentUnityActivity(): Activity? = runCatching {
        Class.forName(UNITY_PLAYER).getField("currentActivity").get(null) as? Activity
    }.getOrNull()?.takeUnless { it.isFinishing || it.isDestroyed }

    private fun updateNativeBack() {
        if (Build.VERSION.SDK_INT < 33) return
        val current = currentUnityActivity()
        val target = current?.takeIf { appMode && it === readyActivity }
        NativeBackApi33.update(target)
    }

    // Isolate API 33 types so older Android versions never load them.
    @android.annotation.TargetApi(33)
    private object NativeBackApi33 {
        private var activity: Activity? = null
        private var callback: android.window.OnBackInvokedCallback? = null

        fun update(target: Activity?) {
            if (activity === target) return
            clear()
            if (target == null) return
            val back = android.window.OnBackInvokedCallback {
                if (!appMode || currentUnityActivity() !== target) {
                    updateNativeBack()
                    return@OnBackInvokedCallback
                }
                runCatching {
                    Class.forName(UNITY_PLAYER)
                        .getMethod("UnitySendMessage", String::class.java, String::class.java, String::class.java)
                        .invoke(null, "FlutterBridge", "OnNativeBack", "")
                }.onFailure { Log.w(TAG, "Native back delivery failed") }
            }
            runCatching {
                target.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                    android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, back,
                )
                activity = target
                callback = back
            }.onFailure { Log.w(TAG, "Native back registration failed") }
        }

        fun clear() {
            callback?.let { back ->
                runCatching { activity?.onBackInvokedDispatcher?.unregisterOnBackInvokedCallback(back) }
            }
            callback = null
            activity = null
        }
    }

}
