package ai.allo.allo_phone

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

object EggInputBridge {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var requestId: String? = null

    fun attach(engine: FlutterEngine, host: Activity) {
        detach()
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "allo/egg-input").apply {
            setMethodCallHandler { call, result ->
                if (call.method != "speech" && call.method != "photo") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "Another input request is active.", null)
                } else {
                    val from = runCatching {
                        Class.forName("com.unity3d.player.UnityPlayer")
                            .getField("currentActivity").get(null) as? Activity
                    }.getOrNull()?.takeUnless { it.isFinishing || it.isDestroyed } ?: host
                    if (from.isFinishing || from.isDestroyed) {
                        result.error("unavailable", "The application activity is unavailable.", null)
                    } else {
                        val id = UUID.randomUUID().toString()
                        pending = result
                        requestId = id
                        try {
                            from.startActivity(Intent(from, EggInputActivity::class.java)
                                .putExtra("requestId", id).putExtra("kind", call.method))
                        } catch (_: Exception) {
                            complete(id, error = "unavailable", message = "Cannot open the input service.")
                        }
                    }
                }
            }
        }
    }

    fun isPending(id: String): Boolean = pending != null && requestId == id

    fun complete(id: String, value: Any? = null, error: String? = null, message: String? = null) {
        if (!isPending(id)) return
        val result = pending
        pending = null
        requestId = null
        if (error == null) result?.success(value) else result?.error(error, message, null)
    }

    fun detach() {
        pending?.error("interrupted", "The input connection was closed. Please retry.", null)
        pending = null
        requestId = null
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
