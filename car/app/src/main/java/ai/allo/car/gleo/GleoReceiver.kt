package ai.allo.car.gleo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ai.allo.car.AlloApp
import ai.allo.car.BuildConfig
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Gleo → 앱 브로드캐스트. action = schema.json 의 function.name.
 * 응답은 APP_ACTION_RESPONSE 브로드캐스트로 돌려준다 (검증 #7 에서 실제 포맷 확인 후 조정).
 * 보낸 쪽 신원을 확인할 방법이 문서에 없으므로 입력 extras 를 신뢰하지 않는다.
 * 유일한 예외는 SUGGEST_DESTINATION 의 `confirm` 이고, 이것도 직전에 우리가 제안한 고정 목적지만 설정할 수 있다 (DestinationFlow).
 */
class GleoReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val function = intent.action?.takeIf { it in GleoFunctions.FUNCTIONS } ?: return
        val app = context.applicationContext as AlloApp
        val session = app.session
        val callback = when {
            function != GleoFunctions.SUGGEST_DESTINATION -> GleoFunctions.respond(function, session.game.value)
            isConfirm(intent) -> GleoFunctions.respondAccept(session.acceptDestination())
            else -> GleoFunctions.respond(function, session.game.value, session.suggestDestination())
        }
        if (BuildConfig.DEBUG) android.util.Log.d("GleoReceiver", "$function → ${callback.status}: ${callback.message}")
        context.sendBroadcast(Intent(RESPONSE_ACTION).apply {
            putExtra("result", callback.status)
            putExtra("packageName", context.packageName)
            putExtra("response", Json.encodeToString(callback))
        })
    }

    /**
     * schema.json 의 `confirm` 파라미터. Gleo 가 파라미터를 extras 로 넘기는 실제 형식은 미확인이라
     * boolean 과 문자열 "true" 를 모두 받는다.
     */
    private fun isConfirm(intent: Intent): Boolean = parseConfirm(intent.extras?.get("confirm"))

    companion object {
        internal fun parseConfirm(value: Any?): Boolean = when (value) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            else -> false
        }

        const val RESPONSE_ACTION = "ai.pleos.playground.intent.action.APP_ACTION_RESPONSE"
    }
}
