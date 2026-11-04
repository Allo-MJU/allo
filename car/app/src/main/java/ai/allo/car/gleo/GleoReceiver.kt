package ai.allo.car.gleo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import ai.allo.car.AlloApp
import ai.allo.car.BuildConfig
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * Gleo → 앱 브로드캐스트. action = schema.json 의 function.name (`component: service` = sendBroadcast).
 * 파라미터는 `ACTION_PARAM` extra 의 JSON 문자열로 온다 (Pleos App Integration Guide · Examples).
 * 응답은 APP_ACTION_RESPONSE 브로드캐스트로 돌려준다.
 *
 * ⚠️ 보낸 쪽 신원을 확인할 방법이 Pleos 문서에 없다 (권한·서명·토큰 모두 언급 없음, 2026-11-04 확인).
 * 그래서 같은 기기의 다른 앱도 제안 → 수락을 보낼 수 있다 (PR #10 리뷰 P1). 완화:
 *  - 목적지는 직전에 우리가 제안한 고정 목록 중 하나만, 제안 후 2분 안에만 (DestinationFlow)
 *  - 이미 내비 안내 중이면 제안·수락 모두 거절 — 진행 중인 경로를 바꾸지 않는다
 *  - 목적지가 바뀌면 차량 앱이 직접 소리 내어 알린다 (응답은 silent). Gleo 를 거치지 않은 호출도 운전자가 듣는다
 */
class GleoReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val function = intent.action?.takeIf { it in GleoFunctions.FUNCTIONS } ?: return
        val app = context.applicationContext as AlloApp
        val session = app.session
        val callback = when {
            function != GleoFunctions.SUGGEST_DESTINATION -> GleoFunctions.respond(function, session.game.value, bank = session.dialogue)
            isConfirm(intent) -> GleoFunctions.respondAccept(session.acceptDestination(), session.dialogue)
                .also { if (it.status == "success") session.voice.speak(it.message) }
            else -> GleoFunctions.respond(function, session.game.value, session.suggestDestination(), session.dialogue)
        }
        if (BuildConfig.DEBUG) android.util.Log.d("GleoReceiver", "$function → ${callback.status}: ${callback.message}")
        context.sendBroadcast(Intent(RESPONSE_ACTION).apply {
            putExtra("result", callback.status)
            putExtra("packageName", context.packageName)
            putExtra("response", Json.encodeToString(callback))
        })
    }

    /** `ACTION_PARAM` 의 confirm. adb 확인용으로 `--es confirm true` extra 도 받는다 */
    private fun isConfirm(intent: Intent): Boolean =
        parseParams(intent.getStringExtra(ACTION_PARAM))?.get("confirm")?.let { parseConfirm(it) }
            ?: parseConfirm(intent.extras?.get("confirm"))

    companion object {
        const val ACTION_PARAM = "ACTION_PARAM"
        const val RESPONSE_ACTION = "ai.pleos.playground.intent.action.APP_ACTION_RESPONSE"

        /**
         * `ACTION_PARAM` → JSON 객체. 문서 예시는 JSON 을 따옴표로 한 번 더 감싸서 보내므로
         * 그 형태(`"{...}"`, 또는 JSON 문자열 안의 JSON)도 받는다. 읽을 수 없으면 null.
         */
        internal fun parseParams(raw: String?): JsonObject? {
            var s = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            repeat(3) {
                val el = runCatching { Json.parseToJsonElement(s) }.getOrNull()
                when {
                    el is JsonObject -> return el
                    el is JsonPrimitive && el.isString -> s = el.content.trim()
                    el == null && s.length >= 2 && s.first() == '"' && s.last() == '"' -> s = s.substring(1, s.length - 1).trim()
                    else -> return null
                }
            }
            return null
        }

        /** boolean, 문자열 "true", JSON 의 true/"true" 를 모두 받는다 */
        internal fun parseConfirm(value: Any?): Boolean = when (value) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            is JsonPrimitive -> value.booleanOrNull ?: value.content.equals("true", ignoreCase = true)
            else -> false
        }
    }
}
